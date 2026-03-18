defmodule ControlKeel.Analytics.Event do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Workspace}

  schema "analytics_events" do
    field :event, :string
    field :source, :string
    field :project_root, :string
    field :metadata, :map, default: %{}
    field :happened_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event,
      :source,
      :session_id,
      :workspace_id,
      :project_root,
      :metadata,
      :happened_at
    ])
    |> validate_required([:event, :source, :metadata, :happened_at])
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:workspace_id)
  end
end
