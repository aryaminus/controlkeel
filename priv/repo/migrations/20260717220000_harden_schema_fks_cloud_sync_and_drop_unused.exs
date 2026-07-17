defmodule ControlKeel.Repo.Migrations.HardenSchemaFksCloudSyncAndDropUnused do
  @moduledoc """
  Schema hardening migration that ties up foreign-key constraints, adds cloud
  sync columns to remaining core tables, and drops unused tables.

  ## Foreign-key constraints

  Several columns were created as plain integers (or had ``belongs_to``
  associations in their Ecto schemas) without a database-level FK constraint:

    * ``workspace_keys.org_id``               → ``orgs.id``
    * ``memory_records.shared_org_id``         → ``orgs.id``
    * ``cloud_mcp_tool_calls.workspace_id``    → ``workspaces.id``
    * ``cloud_mcp_tool_calls.service_account_id`` → ``service_accounts.id``

  On Postgres we add the constraints with ``ALTER TABLE … ADD CONSTRAINT``.
  On SQLite we recreate the tables (SQLite cannot add FKs to existing tables)
  following the same recreation pattern used by earlier migrations.

  ## Cloud sync columns

  ``external_id``, ``synced_at`` and (where applicable) ``lock_version`` are
  added to ``invocations``, ``proof_bundles``, ``session_events``,
  ``task_checkpoints`` and ``rollback_snapshots`` so that local-to-cloud
  migration works for older, current and new database versions.

  ## Unused tables

  ``policy_training_runs`` and ``policy_artifacts`` were created by an earlier
  migration but never received Ecto schemas or any application code.  They are
  dropped here.
  """

  use Ecto.Migration

  def up do
    add_foreign_key_constraints()
    add_cloud_sync_columns()
    drop_unused_tables()
  end

  def down do
    # Restoring the dropped tables is intentionally not supported — the
    # policy-training pipeline was never implemented and re-creating empty
    # tables adds no value.  Cloud-sync columns and FK constraints are
    # reversible.
    remove_cloud_sync_columns()
    remove_foreign_key_constraints()
  end

  # ------------------------------------------------------------------ FKs

  defp add_foreign_key_constraints do
    if sqlite_repo?() do
      recreate_workspace_keys_with_fks()
      recreate_memory_records_with_fks()
      recreate_cloud_mcp_tool_calls_with_fks()
    else
      execute(
        "ALTER TABLE workspace_keys " <>
          "ADD CONSTRAINT workspace_keys_org_id_fkey " <>
          "FOREIGN KEY (org_id) REFERENCES orgs(id) ON DELETE SET NULL"
      )

      execute(
        "ALTER TABLE memory_records " <>
          "ADD CONSTRAINT memory_records_shared_org_id_fkey " <>
          "FOREIGN KEY (shared_org_id) REFERENCES orgs(id) ON DELETE SET NULL"
      )

      execute(
        "ALTER TABLE cloud_mcp_tool_calls " <>
          "ADD CONSTRAINT cloud_mcp_tool_calls_workspace_id_fkey " <>
          "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE SET NULL"
      )

      execute(
        "ALTER TABLE cloud_mcp_tool_calls " <>
          "ADD CONSTRAINT cloud_mcp_tool_calls_service_account_id_fkey " <>
          "FOREIGN KEY (service_account_id) REFERENCES service_accounts(id) ON DELETE SET NULL"
      )
    end
  end

  defp remove_foreign_key_constraints do
    if sqlite_repo?() do
      # SQLite: FK constraints are embedded in the table definition, so the
      # down-direction recreation would remove them.  We skip the complex
      # table recreation on rollback — the constraints are harmless to keep.
      :ok
    else
      execute(
        "ALTER TABLE cloud_mcp_tool_calls DROP CONSTRAINT IF EXISTS cloud_mcp_tool_calls_service_account_id_fkey"
      )

      execute(
        "ALTER TABLE cloud_mcp_tool_calls DROP CONSTRAINT IF EXISTS cloud_mcp_tool_calls_workspace_id_fkey"
      )

      execute(
        "ALTER TABLE memory_records DROP CONSTRAINT IF EXISTS memory_records_shared_org_id_fkey"
      )

      execute("ALTER TABLE workspace_keys DROP CONSTRAINT IF EXISTS workspace_keys_org_id_fkey")
    end
  end

  # --- SQLite table recreations -------------------------------------------

  defp recreate_workspace_keys_with_fks do
    # SQLite cannot ADD a FK to an existing table; recreate with the constraint.
    # Column order matches the live table after all prior ALTER ADD COLUMN
    # migrations have run.
    execute("""
    CREATE TABLE workspace_keys_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workspace_id TEXT NOT NULL,
      public_key TEXT NOT NULL,
      fingerprint TEXT NOT NULL,
      algorithm TEXT NOT NULL DEFAULT 'ed25519',
      name TEXT,
      org_id INTEGER REFERENCES orgs(id) ON DELETE SET NULL,
      last_seen_at DATETIME,
      revoked_at DATETIME,
      mission_workspace_id INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
      inserted_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO workspace_keys_new (
      id, workspace_id, public_key, fingerprint, algorithm, name, org_id,
      last_seen_at, revoked_at, mission_workspace_id, inserted_at, updated_at
    )
    SELECT
      id, workspace_id, public_key, fingerprint, algorithm, name, org_id,
      last_seen_at, revoked_at, mission_workspace_id, inserted_at, updated_at
    FROM workspace_keys
    """)

    execute("DROP TABLE workspace_keys")
    execute("ALTER TABLE workspace_keys_new RENAME TO workspace_keys")

    create unique_index(:workspace_keys, [:workspace_id])
    create unique_index(:workspace_keys, [:fingerprint])
    create index(:workspace_keys, [:org_id])
    create index(:workspace_keys, [:revoked_at])
    create index(:workspace_keys, [:mission_workspace_id])

    create unique_index(:workspace_keys, [:org_id, :mission_workspace_id],
             name: :workspace_keys_org_mission_workspace_unique,
             where: "mission_workspace_id IS NOT NULL AND org_id IS NOT NULL"
           )
  end

  defp recreate_memory_records_with_fks do
    # Drop FTS triggers before recreating the base table.
    execute("DROP TRIGGER IF EXISTS memory_records_au")
    execute("DROP TRIGGER IF EXISTS memory_records_ad")
    execute("DROP TRIGGER IF EXISTS memory_records_ai")

    execute("""
    CREATE TABLE memory_records_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
      external_id TEXT,
      record_type TEXT NOT NULL,
      title TEXT NOT NULL,
      summary TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '[]',
      source_type TEXT NOT NULL,
      source_id TEXT,
      metadata TEXT NOT NULL,
      archived_at DATETIME,
      visibility TEXT NOT NULL DEFAULT 'workspace',
      shared_org_id INTEGER REFERENCES orgs(id) ON DELETE SET NULL,
      synced_at DATETIME,
      inserted_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO memory_records_new (
      id, workspace_id, session_id, task_id, external_id, record_type, title,
      summary, body, tags, source_type, source_id, metadata, archived_at,
      visibility, shared_org_id, synced_at, inserted_at, updated_at
    )
    SELECT
      id, workspace_id, session_id, task_id, external_id, record_type, title,
      summary, body, tags, source_type, source_id, metadata, archived_at,
      visibility, shared_org_id, synced_at, inserted_at, updated_at
    FROM memory_records
    """)

    execute("DROP TABLE memory_records")
    execute("ALTER TABLE memory_records_new RENAME TO memory_records")

    # Recreate all indexes (single + composite from performance migration).
    create index(:memory_records, [:workspace_id])
    create index(:memory_records, [:session_id])
    create index(:memory_records, [:task_id])
    create index(:memory_records, [:record_type])
    create index(:memory_records, [:archived_at])
    create index(:memory_records, [:visibility])
    create index(:memory_records, [:shared_org_id])
    create index(:memory_records, [:synced_at])
    create unique_index(:memory_records, [:external_id], where: "external_id IS NOT NULL")

    create index(:memory_records, [:workspace_id, :archived_at, :inserted_at],
             name: :memory_records_workspace_archived_inserted_idx
           )

    create index(:memory_records, [:workspace_id, :record_type, :inserted_at],
             name: :memory_records_workspace_type_inserted_idx
           )

    # Recreate all three FTS5 triggers (the prior table-recreation migration
    # inadvertently dropped the AFTER DELETE trigger).
    execute("""
    CREATE TRIGGER memory_records_ai AFTER INSERT ON memory_records BEGIN
      INSERT INTO memory_records_fts(memory_record_id, document)
      VALUES (
        new.id,
        trim(
          coalesce(new.title, '') || ' ' ||
          coalesce(new.summary, '') || ' ' ||
          coalesce(new.body, '') || ' ' ||
          coalesce(json_extract(new.tags, '$'), '')
        )
      );
    END;
    """)

    execute("""
    CREATE TRIGGER memory_records_ad AFTER DELETE ON memory_records BEGIN
      DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
    END;
    """)

    execute("""
    CREATE TRIGGER memory_records_au AFTER UPDATE ON memory_records BEGIN
      DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
      INSERT INTO memory_records_fts(memory_record_id, document)
      VALUES (
        new.id,
        trim(
          coalesce(new.title, '') || ' ' ||
          coalesce(new.summary, '') || ' ' ||
          coalesce(new.body, '') || ' ' ||
          coalesce(json_extract(new.tags, '$'), '')
        )
      );
    END;
    """)
  end

  defp recreate_cloud_mcp_tool_calls_with_fks do
    execute("""
    CREATE TABLE cloud_mcp_tool_calls_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workspace_id INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
      service_account_id INTEGER REFERENCES service_accounts(id) ON DELETE SET NULL,
      resource TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      outcome TEXT NOT NULL,
      denial_reason TEXT,
      scopes_granted TEXT,
      argument_keys TEXT,
      requested_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO cloud_mcp_tool_calls_new (
      id, workspace_id, service_account_id, resource, tool_name, outcome,
      denial_reason, scopes_granted, argument_keys, requested_at
    )
    SELECT
      id, workspace_id, service_account_id, resource, tool_name, outcome,
      denial_reason, scopes_granted, argument_keys, requested_at
    FROM cloud_mcp_tool_calls
    """)

    execute("DROP TABLE cloud_mcp_tool_calls")
    execute("ALTER TABLE cloud_mcp_tool_calls_new RENAME TO cloud_mcp_tool_calls")

    create index(:cloud_mcp_tool_calls, [:workspace_id, :requested_at])
    create index(:cloud_mcp_tool_calls, [:tool_name, :requested_at])
    create index(:cloud_mcp_tool_calls, [:outcome, :requested_at])
  end

  # ------------------------------------------------------- Cloud sync cols

  defp add_cloud_sync_columns do
    alter table(:invocations) do
      add :external_id, :string
      add :synced_at, :utc_datetime
      add :lock_version, :integer, default: 1, null: false
    end

    alter table(:proof_bundles) do
      add :external_id, :string
      add :synced_at, :utc_datetime
      add :lock_version, :integer, default: 1, null: false
    end

    alter table(:session_events) do
      add :external_id, :string
      add :synced_at, :utc_datetime
      add :lock_version, :integer, default: 1, null: false
    end

    alter table(:task_checkpoints) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    alter table(:rollback_snapshots) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    create unique_index(:invocations, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:proof_bundles, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:session_events, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:task_checkpoints, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:rollback_snapshots, [:external_id], where: "external_id IS NOT NULL")

    create index(:invocations, [:synced_at])
    create index(:proof_bundles, [:synced_at])
    create index(:session_events, [:synced_at])
    create index(:task_checkpoints, [:synced_at])
    create index(:rollback_snapshots, [:synced_at])
  end

  defp remove_cloud_sync_columns do
    drop index(:rollback_snapshots, [:synced_at])
    drop index(:task_checkpoints, [:synced_at])
    drop index(:session_events, [:synced_at])
    drop index(:proof_bundles, [:synced_at])
    drop index(:invocations, [:synced_at])

    drop unique_index(:rollback_snapshots, [:external_id])
    drop unique_index(:task_checkpoints, [:external_id])
    drop unique_index(:session_events, [:external_id])
    drop unique_index(:proof_bundles, [:external_id])
    drop unique_index(:invocations, [:external_id])

    alter table(:rollback_snapshots) do
      remove :synced_at
      remove :external_id
    end

    alter table(:task_checkpoints) do
      remove :synced_at
      remove :external_id
    end

    alter table(:session_events) do
      remove :lock_version
      remove :synced_at
      remove :external_id
    end

    alter table(:proof_bundles) do
      remove :lock_version
      remove :synced_at
      remove :external_id
    end

    alter table(:invocations) do
      remove :lock_version
      remove :synced_at
      remove :external_id
    end
  end

  # --------------------------------------------------------- Unused tables

  defp drop_unused_tables do
    drop_if_exists table(:policy_artifacts)
    drop_if_exists table(:policy_training_runs)
  end

  # ----------------------------------------------------------------- helpers

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
