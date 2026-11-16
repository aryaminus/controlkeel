defmodule ControlKeel.Accounts.DataLifecycleEvent do
  @moduledoc """
  Durable audit record of an erasure performed by
  `ControlKeel.Accounts.DataLifecycle` (user account or whole org).

  The subject of a `user_erased` event is the user's pseudonymous erasure
  marker (`"erased-user-…"`) — the user row is gone, the marker is what the
  audit rows now reference. The subject of an `org_erased` event is the org id
  as a string, with the slug and deletion counts in `details`. Events are
  inserted inside the erasure transactions, so they only exist for committed
  erasures.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_event_types ~w(user_erased org_erased)

  schema "data_lifecycle_events" do
    field :event_type, :string
    field :subject, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :subject, :details])
    |> validate_required([:event_type, :subject])
    |> validate_inclusion(:event_type, @valid_event_types)
  end
end
