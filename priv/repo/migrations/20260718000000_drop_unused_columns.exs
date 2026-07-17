defmodule ControlKeel.Repo.Migrations.DropUnusedColumns do
  @moduledoc """
  Drops two vestigial columns that were never populated by application code:

    * ``session_digests.circuit_breaker_trips`` — declared in the original
      ``create_session_digests`` migration but never referenced in the
      ``SessionDigest`` schema, changeset, ``sync_fields/0``, or any lib/ or
      test/ code. The circuit-breaker concept was abandoned before shipping.

    * ``rollback_snapshots.safety_check`` — declared as a ``:map`` column but
      never written to. The runtime safety check in
      ``ControlKeel.Governance.RollbackExecutor.safety_check/3`` inspects
      downstream tasks at execution time and does not persist its result.

  ## SQLite

  SQLite did not support ``ALTER TABLE DROP COLUMN`` until 3.35.0 (2021-03-12).
  To remain compatible with older bundled SQLite versions that users may still
  run, we recreate both tables without the dead columns, following the same
  pattern used by migrations ``20260530052757`` and ``20260717220000``.

  ## Postgres

  Postgres supports ``ALTER TABLE … DROP COLUMN`` directly.

  ## Cloud sync safety

  Neither column is in the ``sync_fields/0`` allowlist for its schema
  (``circuit_breaker_trips`` was never in the schema at all; ``safety_check``
  is removed from ``RollbackSnapshot.sync_fields/0`` in the same commit that
  adds this migration). Existing cloud-sync envelopes that happen to carry
  these fields are handled by ``Cloud.Sync.payload_to_attrs/2``, which drops
  unknown payload fields — so pulling from an older cloud node that still has
  the column will not crash a newer local node, and vice-versa.
  """

  use Ecto.Migration

  def up do
    drop_circuit_breaker_trips()
    drop_safety_check()
  end

  def down do
    # Restoring vestigial columns that were never populated adds no value.
    # The down direction is intentionally a no-op so rollback is safe without
    # re-introducing dead schema.
    :ok
  end

  # ------------------------------------------------- circuit_breaker_trips

  defp drop_circuit_breaker_trips do
    if sqlite_repo?() do
      recreate_session_digests_without_circuit_breaker_trips()
    else
      alter table(:session_digests) do
        remove :circuit_breaker_trips
      end
    end
  end

  defp recreate_session_digests_without_circuit_breaker_trips do
    execute("""
    CREATE TABLE session_digests_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      external_id TEXT,
      digest_type TEXT NOT NULL DEFAULT 'session',
      period_start DATETIME NOT NULL,
      period_end DATETIME NOT NULL,
      tasks_completed INTEGER DEFAULT 0,
      tasks_failed INTEGER DEFAULT 0,
      findings_raised INTEGER DEFAULT 0,
      findings_blocked INTEGER DEFAULT 0,
      reviews_pending INTEGER DEFAULT 0,
      reviews_approved INTEGER DEFAULT 0,
      budget_spent_cents INTEGER DEFAULT 0,
      budget_remaining_cents INTEGER DEFAULT 0,
      top_rule_ids TEXT NOT NULL DEFAULT '{}',
      top_categories TEXT NOT NULL DEFAULT '{}',
      highlights TEXT NOT NULL DEFAULT '{}',
      needs_attention INTEGER DEFAULT 0,
      generated_at DATETIME NOT NULL,
      metadata TEXT NOT NULL DEFAULT '{}',
      synced_at DATETIME,
      inserted_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO session_digests_new (
      id, session_id, external_id, digest_type, period_start, period_end,
      tasks_completed, tasks_failed, findings_raised, findings_blocked,
      reviews_pending, reviews_approved, budget_spent_cents,
      budget_remaining_cents, top_rule_ids, top_categories, highlights,
      needs_attention, generated_at, metadata, synced_at, inserted_at, updated_at
    )
    SELECT
      id, session_id, external_id, digest_type, period_start, period_end,
      tasks_completed, tasks_failed, findings_raised, findings_blocked,
      reviews_pending, reviews_approved, budget_spent_cents,
      budget_remaining_cents, top_rule_ids, top_categories, highlights,
      needs_attention, generated_at, metadata, synced_at, inserted_at, updated_at
    FROM session_digests
    """)

    execute("DROP TABLE session_digests")
    execute("ALTER TABLE session_digests_new RENAME TO session_digests")

    create index(:session_digests, [:session_id])
    create index(:session_digests, [:needs_attention])
    create unique_index(:session_digests, [:external_id], where: "external_id IS NOT NULL")
    create index(:session_digests, [:synced_at])
  end

  # ------------------------------------------------------- safety_check

  defp drop_safety_check do
    if sqlite_repo?() do
      recreate_rollback_snapshots_without_safety_check()
    else
      alter table(:rollback_snapshots) do
        remove :safety_check
      end
    end
  end

  defp recreate_rollback_snapshots_without_safety_check do
    execute("""
    CREATE TABLE rollback_snapshots_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      external_id TEXT,
      commit_sha_before TEXT NOT NULL,
      commit_sha_after TEXT,
      status TEXT NOT NULL DEFAULT 'available',
      rollback_method TEXT NOT NULL DEFAULT 'git_revert',
      rolled_back_at DATETIME,
      rolled_back_by TEXT,
      finding_id INTEGER REFERENCES findings(id) ON DELETE SET NULL,
      metadata TEXT NOT NULL DEFAULT '{}',
      synced_at DATETIME,
      inserted_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO rollback_snapshots_new (
      id, session_id, task_id, external_id, commit_sha_before, commit_sha_after,
      status, rollback_method, rolled_back_at, rolled_back_by, finding_id,
      metadata, synced_at, inserted_at, updated_at
    )
    SELECT
      id, session_id, task_id, external_id, commit_sha_before, commit_sha_after,
      status, rollback_method, rolled_back_at, rolled_back_by, finding_id,
      metadata, synced_at, inserted_at, updated_at
    FROM rollback_snapshots
    """)

    execute("DROP TABLE rollback_snapshots")
    execute("ALTER TABLE rollback_snapshots_new RENAME TO rollback_snapshots")

    create index(:rollback_snapshots, [:session_id])
    create index(:rollback_snapshots, [:task_id])
    create index(:rollback_snapshots, [:status])
    create unique_index(:rollback_snapshots, [:external_id], where: "external_id IS NOT NULL")
    create index(:rollback_snapshots, [:synced_at])
  end

  # ----------------------------------------------------------------- helpers

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
