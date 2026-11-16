defmodule ControlKeel.Repo.Migrations.AddCreatedByUserIdToServiceAccounts do
  @moduledoc """
  Trusted credential ownership for user erasure (docs/dsar-erasure-plan.md, 1c).

  Before this migration, `DataLifecycle.revoke_credentials/1` matched
  `service_accounts.metadata["created_by_user_id"]` — a key that no code path
  ever wrote, so service accounts minted by an erased user kept authenticating
  forever. Ownership must be a server-side column, not client-castable
  metadata.

  Adds nullable `created_by_user_id` (FK -> users, `on_delete: :nilify_all` so
  the account row itself survives user deletion and stays visibly revoked).
  The historical backfill lives in the *next* migration: Ecto runs each
  migration in its own transaction, and `repo()` inside migration code uses a
  pooled connection that cannot see DDL still uncommitted on the migration
  connection — so the backfill must be a separate, later migration to observe
  the new column.

  Works on SQLite (local) and Postgres (cloud): plain `ALTER TABLE ADD
  COLUMN ... REFERENCES` (house pattern from `20260524142342`).
  """

  use Ecto.Migration

  def up do
    alter table(:service_accounts) do
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:service_accounts, [:created_by_user_id])
  end

  def down do
    drop index(:service_accounts, [:created_by_user_id])

    alter table(:service_accounts) do
      remove :created_by_user_id
    end
  end
end
