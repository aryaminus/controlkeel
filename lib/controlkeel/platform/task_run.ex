defmodule ControlKeel.Platform.TaskRun do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}
  alias ControlKeel.Platform.{ServiceAccount, TaskCheckResult}

  schema "task_runs" do
    field :status, :string, default: "ready"
    field :execution_mode, :string, default: "local"
    field :claimed_at, :utc_datetime
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :external_ref, :string
    field :output, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :task, Task
    belongs_to :session, Session
    belongs_to :service_account, ServiceAccount
    has_many :check_results, TaskCheckResult

    timestamps(type: :utc_datetime)
  end

  def changeset(task_run, attrs) do
    attrs =
      attrs
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)

    task_run
    |> cast(attrs, [
      :task_id,
      :session_id,
      :service_account_id,
      :status,
      :execution_mode,
      :claimed_at,
      :started_at,
      :finished_at,
      :external_ref,
      :output,
      :metadata
    ])
    |> validate_required([:task_id, :session_id, :status, :execution_mode, :output, :metadata])
    |> validate_inclusion(:status, [
      "ready",
      "claimed",
      "in_progress",
      "waiting_callback",
      "paused",
      "blocked",
      "done",
      "failed"
    ])
    |> validate_inclusion(:execution_mode, ["local", "cloud", "external"])
    |> assoc_constraint(:task)
    |> assoc_constraint(:session)
    |> assoc_constraint(:service_account)
  end
end
