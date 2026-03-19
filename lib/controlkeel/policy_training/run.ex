defmodule ControlKeel.PolicyTraining.Run do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.PolicyTraining.Artifact

  schema "policy_training_runs" do
    field :artifact_type, :string
    field :status, :string, default: "queued"
    field :training_scope, :string
    field :dataset_summary, :map, default: %{}
    field :training_metrics, :map, default: %{}
    field :validation_metrics, :map, default: %{}
    field :held_out_metrics, :map, default: %{}
    field :failure_reason, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :artifacts, Artifact, foreign_key: :training_run_id

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :artifact_type,
      :status,
      :training_scope,
      :dataset_summary,
      :training_metrics,
      :validation_metrics,
      :held_out_metrics,
      :failure_reason,
      :started_at,
      :finished_at,
      :metadata
    ])
    |> validate_required([
      :artifact_type,
      :status,
      :training_scope,
      :dataset_summary,
      :training_metrics,
      :validation_metrics,
      :held_out_metrics,
      :metadata
    ])
  end
end
