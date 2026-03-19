defmodule ControlKeel.PolicyTraining.Artifact do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.PolicyTraining.Run

  schema "policy_artifacts" do
    field :artifact_type, :string
    field :version, :integer
    field :status, :string, default: "candidate"
    field :model_family, :string
    field :artifact, :map, default: %{}
    field :feature_spec, :map, default: %{}
    field :metrics, :map, default: %{}
    field :activated_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :training_run, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :training_run_id,
      :artifact_type,
      :version,
      :status,
      :model_family,
      :artifact,
      :feature_spec,
      :metrics,
      :activated_at,
      :archived_at,
      :metadata
    ])
    |> validate_required([
      :training_run_id,
      :artifact_type,
      :version,
      :status,
      :model_family,
      :artifact,
      :feature_spec,
      :metrics,
      :metadata
    ])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:artifact_type, :version])
    |> assoc_constraint(:training_run)
  end
end
