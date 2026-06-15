defmodule ControlKeel.Mission.FindingAuditEvent do
  @moduledoc """
  Append-only audit log for finding disposition lifecycle events.

  Each row captures one terminal transition so historical finding decisions can be
  reconstructed without trusting mutable finding status or metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.User
  alias ControlKeel.Mission.Finding

  @valid_events ~w(approved rejected escalated)

  schema "finding_audit_events" do
    field :event_type, :string
    field :previous_status, :string
    field :new_status, :string
    field :reason, :string
    field :actor_source, :string
    field :actor_identifier, :string
    field :recorded_at, :utc_datetime

    belongs_to :finding, Finding
    belongs_to :actor_user, User, foreign_key: :actor_user_id
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :finding_id,
      :event_type,
      :previous_status,
      :new_status,
      :reason,
      :actor_user_id,
      :actor_source,
      :actor_identifier,
      :recorded_at
    ])
    |> validate_required([
      :finding_id,
      :event_type,
      :previous_status,
      :new_status,
      :recorded_at
    ])
    |> validate_inclusion(:event_type, @valid_events)
    |> assoc_constraint(:finding)
  end
end
