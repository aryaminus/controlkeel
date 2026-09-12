defmodule ControlKeel.Repo.AddOrgFkToWorkspacesMigrationTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MigrationRepo
  alias ControlKeel.Repo.Migrations.AddOrgFkToWorkspaces

  @migration_version 20_260_828_000_001

  @tag :tmp_dir
  test "migrates an existing SQLite workspace FK without rebuilding its referenced table", %{
    tmp_dir: tmp_dir
  } do
    database = Path.join(tmp_dir, "migration.db")

    start_supervised!(
      {MigrationRepo,
       database: database,
       pool_size: 2,
       busy_timeout: 5_000,
       stacktrace: true,
       show_sensitive_data_on_connection_error: true}
    )

    repo = MigrationRepo

    query!(repo, "PRAGMA foreign_keys = OFF")
    create_pre_migration_schema!(repo)
    seed_pre_migration_data!(repo)
    query!(repo, "PRAGMA foreign_keys = ON")

    assert :ok =
             Ecto.Migrator.up(repo, @migration_version, AddOrgFkToWorkspaces, log: false)

    assert [[1, 1], [2, nil]] = rows!(repo, "SELECT id, org_id FROM workspaces ORDER BY id")
    assert [[1, 1]] = rows!(repo, "SELECT id, workspace_id FROM sessions")
    assert [] = rows!(repo, "PRAGMA foreign_key_check")

    assert [[0, 0, "orgs", "org_id", "id", "NO ACTION", "SET NULL", "NONE"]] =
             rows!(repo, "PRAGMA foreign_key_list(workspaces)")

    assert [
             ["workspaces_agent_index"],
             ["workspaces_industry_index"],
             ["workspaces_org_id_index"],
             ["workspaces_slug_index"]
           ] =
             rows!(
               repo,
               "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'workspaces' ORDER BY name"
             )

    assert :ok =
             Ecto.Migrator.down(repo, @migration_version, AddOrgFkToWorkspaces, log: false)

    assert [[0, 0, "orgs", "org_id", "id", "NO ACTION", "SET NULL", "NONE"]] =
             rows!(repo, "PRAGMA foreign_key_list(workspaces)")

    assert [[1, 1]] = rows!(repo, "SELECT id, workspace_id FROM sessions")

    query!(repo, "DELETE FROM orgs WHERE id = 1")
    assert [[1, nil], [2, nil]] = rows!(repo, "SELECT id, org_id FROM workspaces ORDER BY id")
    assert [[1, 1]] = rows!(repo, "SELECT id, workspace_id FROM sessions")
  end

  defp create_pre_migration_schema!(repo) do
    query!(repo, "CREATE TABLE orgs (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")

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
  end

  defp seed_pre_migration_data!(repo) do
    query!(repo, "INSERT INTO orgs (id, name) VALUES (1, 'valid')")

    query!(repo, """
    INSERT INTO workspaces
      (id, name, slug, industry, agent, budget_cents, compliance_profile, status, inserted_at, updated_at, org_id)
    VALUES
      (1, 'valid', 'valid', 'general', 'opencode', 0, 'general', 'active', 'now', 'now', 1),
      (2, 'dangling', 'dangling', 'general', 'opencode', 0, 'general', 'active', 'now', 'now', 999)
    """)

    query!(repo, "INSERT INTO sessions (id, workspace_id) VALUES (1, 1)")
  end

  defp query!(repo, sql), do: Ecto.Adapters.SQL.query!(repo, sql, [])
  defp rows!(repo, sql), do: query!(repo, sql).rows
end
