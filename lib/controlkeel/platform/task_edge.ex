defmodule ControlKeel.Platform.TaskEdge do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}

  schema "task_edges" do
    field :dependency_type, :string, default: "blocks"
    field :metadata, :map, default: %{}

    belongs_to :session, Session
    belongs_to :from_task, Task
    belongs_to :to_task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:session_id, :from_task_id, :to_task_id, :dependency_type, :metadata])
    |> validate_required([:session_id, :from_task_id, :to_task_id, :dependency_type, :metadata])
    |> validate_inclusion(:dependency_type, ["blocks", "soft_gate"])
    |> validate_no_self_dependency()
    |> assoc_constraint(:session)
    |> assoc_constraint(:from_task)
    |> assoc_constraint(:to_task)
    |> unique_constraint([:session_id, :from_task_id, :to_task_id])
  end

  defp validate_no_self_dependency(changeset) do
    if get_field(changeset, :from_task_id) == get_field(changeset, :to_task_id) do
      add_error(changeset, :to_task_id, "cannot depend on itself")
    else
      changeset
    end
  end
end
