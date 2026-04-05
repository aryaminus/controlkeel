defmodule ControlKeel.Mission.SessionEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}

  schema "session_events" do
    field :event_type, :string
    field :actor, :string
    field :summary, :string
    field :body, :string, default: ""
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(session_event, attrs) do
    session_event
    |> cast(attrs, [
      :event_type,
      :actor,
      :summary,
      :body,
      :payload,
      :metadata,
      :session_id,
      :task_id
    ])
    |> validate_required([
      :event_type,
      :actor,
      :summary,
      :payload,
      :metadata,
      :session_id
    ])
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
  end
end
