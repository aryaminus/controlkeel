defmodule ControlKeel.Repo.Migrations.PolicySetOrgOwnership do
  @moduledoc """
  Policy sets become org-owned exclusively (replacing the `scope`
  workspace|global discriminator).

  The column starts nullable so existing users' rows can be backfilled in a
  later, operator-approved data migration; from this point on the changeset
  requires `org_id`, so no new unowned set can be written. Org deletion drops
  its policy sets, and the existing `workspace_policy_sets` FK cascades the
  join rows with it.
  """
  use Ecto.Migration

  def up do
    alter table(:policy_sets) do
      add :org_id, references(:orgs, on_delete: :delete_all)
    end

    create index(:policy_sets, [:org_id])

    drop index(:policy_sets, [:scope])
    alter table(:policy_sets) do
      remove :scope
    end
  end

  def down do
    alter table(:policy_sets) do
      add :scope, :string, null: false, default: "workspace"
    end

    create index(:policy_sets, [:scope])

    drop index(:policy_sets, [:org_id])
    alter table(:policy_sets) do
      remove :org_id
    end
  end
end
