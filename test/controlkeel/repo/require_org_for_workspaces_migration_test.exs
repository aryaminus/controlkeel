defmodule ControlKeel.Repo.RequireOrgForWorkspacesMigrationTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MigrationRepo
  alias ControlKeel.Repo.Migrations.RequireOrgForWorkspaces

  @migration_version 20_261_109_120_000

  @tag :tmp_dir
  test "backfills legacy unbound workspaces and preserves dependent rows", %{tmp_dir: tmp_dir} do
    repo = start_migration_repo(tmp_dir)
    create_pre_migration_schema!(repo)
    seed_pre_migration_data!(repo)

    assert :ok = Ecto.Migrator.up(repo, @migration_version, RequireOrgForWorkspaces, log: false)

    assert [[1, 1], [2, 2]] = rows!(repo, "SELECT id, org_id FROM workspaces ORDER BY id")
    assert [[2, "default-organization"]] = rows!(repo, "SELECT id, slug FROM orgs WHERE id = 2")
    assert [[1, 1]] = rows!(repo, "SELECT id, workspace_id FROM sessions")
    assert [] = rows!(repo, "PRAGMA foreign_key_check")

    assert [[1]] =
             rows!(
               repo,
               "SELECT \"notnull\" FROM pragma_table_info('workspaces') WHERE name = 'org_id'"
             )

    assert [[0, 0, "orgs", "org_id", "id", "NO ACTION", "RESTRICT", "NONE"]] =
             rows!(repo, "PRAGMA foreign_key_list(workspaces)")

    assert {:error, _} = Ecto.Adapters.SQL.query(repo, "DELETE FROM orgs WHERE id = 2", [])
    assert [[2, 2]] = rows!(repo, "SELECT id, org_id FROM workspaces WHERE id = 2")

    assert :ok =
             Ecto.Migrator.down(repo, @migration_version, RequireOrgForWorkspaces, log: false)

    assert [[0]] =
             rows!(
               repo,
               "SELECT \"notnull\" FROM pragma_table_info('workspaces') WHERE name = 'org_id'"
             )

    assert [[0, 0, "orgs", "org_id", "id", "NO ACTION", "SET NULL", "NONE"]] =
             rows!(repo, "PRAGMA foreign_key_list(workspaces)")

    assert [[1, 1]] = rows!(repo, "SELECT id, workspace_id FROM sessions")
  end

  @tag :tmp_dir
  test "does not create a default org when all workspaces are already bound", %{tmp_dir: tmp_dir} do
    repo = start_migration_repo(tmp_dir)
    create_pre_migration_schema!(repo)
    query!(repo, "INSERT INTO orgs (id, name, slug) VALUES (1, 'Tenant', 'tenant')")

    query!(repo, """
    INSERT INTO workspaces
      (id, name, slug, industry, agent, budget_cents, compliance_profile, status,
       inserted_at, updated_at, org_id)
    VALUES (1, 'Bound', 'bound', 'general', 'opencode', 0, 'general', 'active',
            'now', 'now', 1)
    """)

    assert :ok = Ecto.Migrator.up(repo, @migration_version, RequireOrgForWorkspaces, log: false)
    assert [[1]] = rows!(repo, "SELECT COUNT(*) FROM orgs")
    assert [[1, 1]] = rows!(repo, "SELECT id, org_id FROM workspaces")
  end

  defp start_migration_repo(tmp_dir) do
    database = Path.join(tmp_dir, "migration.db")

    start_supervised!(
      {MigrationRepo,
       database: database,
       pool_size: 1,
       busy_timeout: 5_000,
       stacktrace: true,
       show_sensitive_data_on_connection_error: true}
    )

    MigrationRepo
  end

  defp create_pre_migration_schema!(repo) do
    query!(repo, """
    CREATE TABLE orgs (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      settings TEXT NOT NULL DEFAULT '{}',
      inserted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    """)

    query!(repo, "CREATE UNIQUE INDEX orgs_slug_index ON orgs(slug)")

    query!(repo, """
    CREATE TABLE workspaces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      industry TEXT NOT NULL,
      agent TEXT NOT NULL,
      budget_cents INTEGER NOT NULL DEFAULT 0,
      compliance_profile TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      org_id INTEGER REFERENCES orgs(id) ON DELETE SET NULL
    )
    """)

    query!(repo, "CREATE UNIQUE INDEX workspaces_slug_index ON workspaces(slug)")
    query!(repo, "CREATE INDEX workspaces_industry_index ON workspaces(industry)")
    query!(repo, "CREATE INDEX workspaces_agent_index ON workspaces(agent)")
    query!(repo, "CREATE INDEX workspaces_org_id_index ON workspaces(org_id)")

    query!(repo, """
    CREATE TABLE sessions (
      id INTEGER PRIMARY KEY,
      workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE
    )
    """)

    query!(repo, "PRAGMA foreign_keys = ON")
  end

  defp seed_pre_migration_data!(repo) do
    query!(repo, "INSERT INTO orgs (id, name, slug) VALUES (1, 'Tenant', 'tenant')")

    query!(repo, """
    INSERT INTO workspaces
      (id, name, slug, industry, agent, budget_cents, compliance_profile, status,
       inserted_at, updated_at, org_id)
    VALUES
      (1, 'Bound', 'bound', 'general', 'opencode', 0, 'general', 'active', 'now', 'now', 1),
      (2, 'Legacy', 'legacy', 'general', 'opencode', 0, 'general', 'active', 'now', 'now', NULL)
    """)

    query!(repo, "INSERT INTO sessions (id, workspace_id) VALUES (1, 1)")
  end

  defp query!(repo, sql), do: Ecto.Adapters.SQL.query!(repo, sql, [])
  defp rows!(repo, sql), do: query!(repo, sql).rows
end
