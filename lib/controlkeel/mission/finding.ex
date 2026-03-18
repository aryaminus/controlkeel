defmodule ControlKeel.Mission.Finding do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Session

  schema "findings" do
    field :title, :string
    field :severity, :string
    field :category, :string
    field :rule_id, :string
    field :plain_message, :string
    field :status, :string, default: "open"
    field :auto_resolved, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :title,
      :severity,
      :category,
      :rule_id,
      :plain_message,
      :status,
      :auto_resolved,
      :metadata,
      :session_id
    ])
    |> validate_required([
      :title,
      :severity,
      :category,
      :rule_id,
      :plain_message,
      :status,
      :auto_resolved,
      :metadata,
      :session_id
    ])
    |> assoc_constraint(:session)
  end
end
