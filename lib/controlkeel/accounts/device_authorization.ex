defmodule ControlKeel.Accounts.DeviceAuthorization do
  @moduledoc """
  A pending RFC 8628 device-authorization session.

  The CLI asks for a device authorization, shows the user a short `user_code`,
  and polls with the high-entropy `device_code` until the user approves in a
  browser. Both codes are persisted only as SHA-256 hashes — the device code is
  a bearer credential, and the user code is deliberately short enough to be
  typed, so neither may sit in the database in plaintext.

  Status transitions:

      pending ──approve──> approved ──token issued──> consumed
         └─────deny────> denied
         └─────expiry──> expired (implicit, via expires_at)

  RFC 8628 §3.4 requires the client to keep polling, and the token endpoint to
  answer `authorization_pending` / `slow_down` until one of these resolves.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved denied consumed)

  schema "device_authorizations" do
    field :device_code_hash, :string
    field :user_code_hash, :string
    field :client_id, :string
    field :client_name, :string
    field :scope, :string, default: ""
    field :status, :string, default: "pending"
    field :last_polled_at, :utc_datetime
    field :poll_count, :integer, default: 0
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :consumed_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :interval_seconds, :integer, default: 5
    field :verification_uri, :string

    belongs_to :user, ControlKeel.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device_auth, attrs) do
    device_auth
    |> cast(attrs, [
      :device_code_hash,
      :user_code_hash,
      :client_id,
      :client_name,
      :scope,
      :status,
      :user_id,
      :last_polled_at,
      :poll_count,
      :approved_at,
      :denied_at,
      :consumed_at,
      :expires_at,
      :interval_seconds,
      :verification_uri
    ])
    |> validate_required([
      :device_code_hash,
      :user_code_hash,
      :status,
      :expires_at,
      :interval_seconds
    ])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:device_code_hash)
    |> unique_constraint(:user_code_hash)
  end

  @doc "Terminal states can no longer yield a token."
  def terminal?(%__MODULE__{status: status}) when status in ["denied", "consumed"], do: true
  def terminal?(%__MODULE__{}), do: false

  @doc "True once the device session has passed its expiry."
  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt

  def expired?(%__MODULE__{}), do: false

  @doc "Approved and still redeemable."
  def redeemable?(%__MODULE__{} = auth), do: auth.status == "approved" and not expired?(auth)
end
