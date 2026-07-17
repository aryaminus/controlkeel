defmodule ControlKeel.Mission.TaskCheckpoint do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}

  schema "task_checkpoints" do
    field :checkpoint_type, :string
    field :summary, :string
    field :payload, :map, default: %{}
    field :created_by, :string, default: "system"
    field :external_id, :string
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(task_checkpoint, attrs) do
    task_checkpoint
    |> cast(attrs, [
      :session_id,
      :task_id,
      :checkpoint_type,
      :summary,
      :payload,
      :created_by,
      :external_id,
      :synced_at
    ])
    |> validate_required([
      :session_id,
      :task_id,
      :checkpoint_type,
      :summary,
      :payload,
      :created_by
    ])
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> unique_constraint(:external_id)
  end
end
