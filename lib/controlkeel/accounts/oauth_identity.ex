defmodule ControlKeel.Accounts.OAuthIdentity do
  @moduledoc """
  OAuth provider identity linked to a ControlKeel user.

  One user may have multiple identities (e.g. Google + GitHub) so they
  can sign in with either provider. The `provider_data` map stores the
  raw normalized claims returned by Assent for debugging and audit.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.User

  @primary_key {:id, :id, autogenerate: true}
  schema "oauth_identities" do
    field :provider, :string
    field :provider_uid, :string
    field :provider_email, :string
    field :provider_name, :string
    field :provider_avatar_url, :string
    field :provider_data, :map, default: %{}

    belongs_to :user, User
    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :provider,
      :provider_uid,
      :provider_email,
      :provider_name,
      :provider_avatar_url,
      :provider_data,
      :user_id
    ])
    |> validate_required([:provider, :provider_uid, :provider_email, :user_id])
    |> unique_constraint([:provider, :provider_uid])
    |> assoc_constraint(:user)
  end
end
