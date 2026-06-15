defmodule ControlKeel.Accounts.ReviewAuditEvent do
  @moduledoc """
  Append-only audit log for review-assignment lifecycle events.

  Each row captures one transition: assigned, reassigned, approved, denied,
  cleared. Used by team admins to reconstruct who reviewed what and to satisfy
  SOC 2 / GDPR audit requirements.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.User
  alias ControlKeel.Mission.Review

  @valid_events ~w(assigned reassigned approved denied cleared)

  @primary_key {:id, :id, autogenerate: true}
  schema "review_audit_events" do
    field :event_type, :string
    field :required_role, :string
    field :actor_role, :string
    field :actor_source, :string
    field :actor_identifier, :string
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :review, Review
    belongs_to :actor_user, User, foreign_key: :actor_user_id
    belongs_to :target_user, User, foreign_key: :target_user_id
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :review_id,
      :event_type,
      :actor_user_id,
      :target_user_id,
      :required_role,
      :actor_role,
      :actor_source,
      :actor_identifier,
      :note,
      :recorded_at
    ])
    |> validate_required([:review_id, :event_type, :recorded_at])
    |> validate_inclusion(:event_type, @valid_events)
    |> assoc_constraint(:review)
  end
end
