defmodule ControlKeel.Accounts.User do
  @moduledoc """
  Human identity in the cloud control plane.

  Distinct from `ControlKeel.Platform.ServiceAccount` (machine identities).
  Per architectural decision D4, user accounts live in their own context and
  do not share a table with service accounts.

  Auth in this slice is invite-only: users are created via
  `ControlKeel.Accounts.invite_member/3` which produces a high-entropy
  invitation token stored on the corresponding `Membership`. A future Phase 6
  slice can layer SSO/password on top.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.{Membership, User}

  @primary_key {:id, :id, autogenerate: true}
  schema "users" do
    field :email, :string
    field :name, :string
    field :status, :string, default: "active"

    belongs_to :created_by_user, User, foreign_key: :created_by_user_id
    has_many :memberships, Membership
    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(active disabled)
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :status, :created_by_user_id])
    |> validate_required([:email])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, @email_regex)
    |> validate_length(:email, max: 254)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:email)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email),
    do: email |> String.downcase() |> String.trim()
end
