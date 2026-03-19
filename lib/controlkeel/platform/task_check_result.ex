defmodule ControlKeel.Platform.TaskCheckResult do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}
  alias ControlKeel.Platform.TaskRun

  schema "task_check_results" do
    field :check_type, :string
    field :status, :string, default: "passed"
    field :summary, :string
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :task_run, TaskRun
    belongs_to :task, Task
    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  def changeset(check_result, attrs) do
    check_result
    |> cast(attrs, [
      :task_run_id,
      :task_id,
      :session_id,
      :check_type,
      :status,
      :summary,
      :payload,
      :metadata
    ])
    |> validate_required([
      :task_run_id,
      :task_id,
      :session_id,
      :check_type,
      :status,
      :payload,
      :metadata
    ])
    |> validate_inclusion(:status, ["passed", "failed", "warn"])
    |> assoc_constraint(:task_run)
    |> assoc_constraint(:task)
    |> assoc_constraint(:session)
  end
end
