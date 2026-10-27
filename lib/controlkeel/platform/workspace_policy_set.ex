defmodule ControlKeel.Platform.WorkspacePolicySet do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.PolicySet
  alias ControlKeel.Repo

  schema "workspace_policy_sets" do
    field :precedence, :integer, default: 100
    field :enabled, :boolean, default: true

    belongs_to :workspace, Workspace
    belongs_to :policy_set, PolicySet

    timestamps(type: :utc_datetime)
  end

  def changeset(workspace_policy_set, attrs) do
    workspace_policy_set
    |> cast(attrs, [:workspace_id, :policy_set_id, :precedence, :enabled])
    |> validate_required([:workspace_id, :policy_set_id, :precedence, :enabled])
    |> validate_number(:precedence,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 2_147_483_647
    )
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:policy_set)
    |> validate_same_org()
    |> unique_constraint([:workspace_id, :policy_set_id])
  end

  # Org-exclusive linkage invariant (approved plan): a policy set may only be
  # attached to a workspace of the org that owns it. Both ids must resolve and
  # be org-bound — legacy org-less sets fail validation until they are
  # backfilled, and solo (org-nil) workspaces cannot attach org policies.
  defp validate_same_org(changeset) do
    with %{} = workspace when not is_nil(workspace.id) <- fetch_workspace(changeset),
         %{} = policy_set when not is_nil(policy_set.id) <- fetch_policy_set(changeset),
         ws_org_id when is_integer(ws_org_id) <- workspace.org_id,
         set_org_id when is_integer(set_org_id) <- policy_set.org_id,
         true <- ws_org_id == set_org_id do
      changeset
    else
      _ ->
        add_error(changeset, :policy_set_id, "must belong to the workspace's organization")
    end
  end

  defp fetch_workspace(changeset) do
    case get_field(changeset, :workspace_id) do
      nil -> nil
      id -> Repo.get(Workspace, id)
    end
  end

  defp fetch_policy_set(changeset) do
    case get_field(changeset, :policy_set_id) do
      nil -> nil
      id -> Repo.get(PolicySet, id)
    end
  end
end
