defmodule ControlKeel.Platform.WorkspacePolicySet do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.PolicySet

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
    |> validate_number(:precedence, greater_than_or_equal_to: 0)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:policy_set)
    |> unique_constraint([:workspace_id, :policy_set_id])
  end
end
