defmodule ControlKeel.Repo.Migrations.AddOrgFkToWorkspaces do
  @moduledoc """
  Enforces referential integrity for `workspaces.org_id`.

  Every workspace must belong to an org. This migration guarantees that a
  non-null org_id references an existing org row; a later migration backfills
  legacy nulls and adds the NOT NULL constraint.
  """
  use Ecto.Migration

  def up do
    # Clean any dangling references before adding the constraint.
    execute("""
    UPDATE workspaces SET org_id = NULL
    WHERE org_id IS NOT NULL AND org_id NOT IN (SELECT id FROM orgs)
    """)

    # The earlier AddOrgToWorkspaces migration creates this foreign key on
    # SQLite. Rebuilding the referenced parent table here would execute child
    # ON DELETE actions when the old table is dropped.
    unless sqlite_repo?() do
      # On Postgres, 20260524142342_add_org_to_workspaces already added
      # `references(:orgs, on_delete: :nilify_all)` which creates the same FK
      # with name workspaces_org_id_fkey. Guard the ADD so migrate is
      # idempotent on DBs that already have it.
      execute("""
      DO $$ BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'workspaces_org_id_fkey'
        ) THEN
          ALTER TABLE workspaces
            ADD CONSTRAINT workspaces_org_id_fkey
            FOREIGN KEY (org_id) REFERENCES orgs(id) ON DELETE SET NULL;
        END IF;
      END $$
      """)
    end
  end

  def down do
    # SQLite's foreign key predates this migration, so rollback must retain it.
    unless sqlite_repo?() do
      execute("ALTER TABLE workspaces DROP CONSTRAINT workspaces_org_id_fkey")
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
