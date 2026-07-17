defmodule ControlKeel.Accounts.Membership do
  @moduledoc """
  Join between a user and an org, with role and invitation lifecycle.

  Roles ladder (highest to lowest):

    - `owner`   — full org control; can transfer ownership
    - `admin`   — manage members, policies, budgets, but cannot delete org
    - `member`  — read/write within their workspaces
    - `viewer`  — read-only access

  Invitation flow: `Accounts.invite_member/3` creates a `pending` membership
  with `invitation_token_hash` set. The invitee accepts via the raw token,
  which clears the hash and sets `accepted_at`. After acceptance the
  membership becomes `active`.

  An invitation may pre-bind a `mission_workspace_id`. When the same token
  is later presented at cloud workspace enrolment (the laptop redeeming a
  scoped invite), `KeyRegistry.enroll/1` links the new
  `workspace_keys` row to that project workspace, completing the local↔cloud
  identity model from the operator side. The field is harmless after
  user-side acceptance — it just records which workspace the invite was
  scoped to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Org
  alias ControlKeel.Accounts.User

  @primary_key {:id, :id, autogenerate: true}
  schema "memberships" do
    field :role, :string, default: "member"
    field :status, :string, default: "pending"
    field :invitation_token_hash, :string
    field :invited_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :user, User
    belongs_to :org, Org
    belongs_to :invited_by_user, User, foreign_key: :invited_by_user_id
    belongs_to :mission_workspace, ControlKeel.Mission.Workspace
    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(owner admin member viewer)
  @valid_statuses ~w(pending active revoked)

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :user_id,
      :org_id,
      :role,
      :status,
      :invitation_token_hash,
      :invited_at,
      :accepted_at,
      :invited_by_user_id,
      :mission_workspace_id
    ])
    |> validate_required([:user_id, :org_id, :role, :status])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:user)
    |> assoc_constraint(:org)
    |> assoc_constraint(:invited_by_user)
    |> unique_constraint([:user_id, :org_id], name: :memberships_user_id_org_id_index)
    |> unique_constraint(:invitation_token_hash)
  end

  @doc "True when the membership grants active access."
  def active?(%__MODULE__{status: "active"}), do: true
  def active?(%__MODULE__{}), do: false
end
