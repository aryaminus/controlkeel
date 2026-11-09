defmodule ControlKeel.Repo.Migrations.RequireOrgForWorkspaces do
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @default_org_name "Default Organization"
  @default_org_slug "default-organization"

  def up do
    if sqlite_repo?() do
      backfill_unbound_workspaces()
      rebuild_workspaces(org_required?: true)
    else
      run_transaction(fn ->
        backfill_unbound_workspaces()
        replace_postgres_org_fk("RESTRICT")
        repo().query!("ALTER TABLE workspaces ALTER COLUMN org_id SET NOT NULL", [])
      end)
    end
  end

  def down do
    if sqlite_repo?() do
      rebuild_workspaces(org_required?: false)
    else
      run_transaction(fn ->
        repo().query!("ALTER TABLE workspaces ALTER COLUMN org_id DROP NOT NULL", [])
        replace_postgres_org_fk("SET NULL")
      end)
    end
  end

  defp run_transaction(operation) do
    case repo().transaction(operation) do
      {:ok, _result} -> :ok
      {:error, reason} -> raise "workspace org migration failed: #{inspect(reason)}"
    end
  end

  defp replace_postgres_org_fk(on_delete) do
    repo().query!("ALTER TABLE workspaces DROP CONSTRAINT IF EXISTS workspaces_org_id_fkey", [])

    repo().query!(
      "ALTER TABLE workspaces ADD CONSTRAINT workspaces_org_id_fkey " <>
        "FOREIGN KEY (org_id) REFERENCES orgs(id) ON DELETE #{on_delete}",
      []
    )
  end

  defp backfill_unbound_workspaces do
    unbound_count =
      repo().one(
        from(workspace in "workspaces", where: is_nil(workspace.org_id), select: count())
      )

    if unbound_count > 0 do
      repo().query!(
        """
        INSERT INTO orgs (name, slug, status, inserted_at, updated_at)
        VALUES ('#{@default_org_name}', '#{@default_org_slug}', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (slug) DO NOTHING
        """,
        []
      )

      repo().query!(
        """
        UPDATE workspaces
        SET org_id = (SELECT id FROM orgs WHERE slug = '#{@default_org_slug}')
        WHERE org_id IS NULL
        """,
        []
      )

      remaining_count =
        repo().one(
          from(workspace in "workspaces", where: is_nil(workspace.org_id), select: count())
        )

      if remaining_count != 0 do
        raise "expected to backfill #{unbound_count} unbound workspaces, #{remaining_count} remain"
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3

  defp rebuild_workspaces(org_required?: org_required?) do
    repo().checkout(fn ->
      repo().query!("PRAGMA foreign_keys = OFF")

      try do
        case repo().transaction(fn ->
               repo().query!("""
               CREATE TABLE workspaces_new (
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
                 org_id INTEGER #{if org_required?, do: "NOT NULL ", else: ""}REFERENCES orgs(id) ON DELETE #{if org_required?, do: "RESTRICT", else: "SET NULL"}
               )
               """)

               repo().query!("""
               INSERT INTO workspaces_new (
                 id, name, slug, industry, agent, budget_cents, compliance_profile,
                 status, inserted_at, updated_at, org_id
               )
               SELECT
                 id, name, slug, industry, agent, budget_cents, compliance_profile,
                 status, inserted_at, updated_at, org_id
               FROM workspaces
               """)

               repo().query!("DROP TABLE workspaces")
               repo().query!("ALTER TABLE workspaces_new RENAME TO workspaces")

               repo().query!("CREATE UNIQUE INDEX workspaces_slug_index ON workspaces(slug)")
               repo().query!("CREATE INDEX workspaces_industry_index ON workspaces(industry)")
               repo().query!("CREATE INDEX workspaces_agent_index ON workspaces(agent)")
               repo().query!("CREATE INDEX workspaces_org_id_index ON workspaces(org_id)")
             end) do
          {:ok, _result} -> :ok
          {:error, reason} -> raise "failed to rebuild workspaces table: #{inspect(reason)}"
        end
      after
        repo().query!("PRAGMA foreign_keys = ON")
      end
    end)
  end
end
