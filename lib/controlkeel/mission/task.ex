defmodule ControlKeel.Mission.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Memory.Record
  alias ControlKeel.Mission.{ProofBundle, Session, TaskCheckpoint}
  alias ControlKeel.Platform.{TaskCheckResult, TaskEdge, TaskRun}

  schema "tasks" do
    field :title, :string
    field :status, :string, default: "queued"
    field :estimated_cost_cents, :integer, default: 0
    field :validation_gate, :string
    field :position, :integer
    field :metadata, :map, default: %{}
    field :confidence_score, :float
    field :rollback_boundary, :string

    belongs_to :session, Session
    has_many :proof_bundles, ProofBundle
    has_many :task_checkpoints, TaskCheckpoint
    has_many :memory_records, Record
    has_many :outgoing_edges, TaskEdge, foreign_key: :from_task_id
    has_many :incoming_edges, TaskEdge, foreign_key: :to_task_id
    has_many :task_runs, TaskRun
    has_many :task_check_results, TaskCheckResult

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :status,
      :estimated_cost_cents,
      :validation_gate,
      :position,
      :metadata,
      :session_id,
      :confidence_score,
      :rollback_boundary
    ])
    |> validate_required([
      :title,
      :status,
      :estimated_cost_cents,
      :validation_gate,
      :position,
      :metadata,
      :session_id
    ])
    |> validate_number(:estimated_cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> assoc_constraint(:session)
  end
end
