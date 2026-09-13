defmodule ControlKeel.Accounts do
  @moduledoc """
  Cloud accounts context: users, orgs, memberships.

  Per architectural decision D4, this is the human-identity surface. Machine
  identities continue to live under `ControlKeel.Platform.ServiceAccount`.

  Auth is invite-only via high-entropy tokens
  (`invite_member/3` produces the token; `accept_invitation/2` redeems it).
  Browser sign-in (Google/GitHub OAuth) is handled in `ControlKeelWeb`, not
  here; this context is the identity + membership store.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Accounts.ReviewAuditEvent
  alias ControlKeel.Accounts.User
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Mission.Review
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @org_budget_setting_key "budget_cents"

  @role_rank %{
    "owner" => 3,
    "admin" => 2,
    "member" => 1,
    "viewer" => 0
  }

  # ──────────────── Users ──────────────────

  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_user(integer()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(String.trim(email)))
  end

  @doc """
  Find an existing user by email, or create a new one.

  Returns `{:ok, user, created}` where `created` is `true` when a new row was
  inserted and `false` when an existing user was returned. Used by the login
  flow so the same form handles first-time sign-up and subsequent sign-in.
  Name is only persisted when creating.
  """
  @spec find_or_create_user(String.t(), String.t() | nil) ::
          {:ok, User.t(), boolean()} | {:error, Ecto.Changeset.t()}
  def find_or_create_user(email, name \\ nil) when is_binary(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user, false}

      nil ->
        case create_user(%{email: email, name: name}) do
          {:ok, %User{} = user} -> {:ok, user, true}
          {:error, _} = err -> err
        end
    end
  end

  @spec list_users(keyword()) :: [User.t()]
  def list_users(opts \\ []) do
    User
    |> filter_status(Keyword.get(opts, :status))
    |> order_by([u], asc: u.email)
    |> Repo.all()
  end

  @spec disable_user(integer()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def disable_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> user |> User.changeset(%{status: "disabled"}) |> Repo.update()
    end
  end

  # ──────────────── Orgs ───────────────────

  @spec create_org(map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
  def create_org(attrs) do
    %Org{}
    |> Org.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_org(integer()) :: Org.t() | nil
  def get_org(id), do: Repo.get(Org, id)

  @spec get_org_by_slug(String.t()) :: Org.t() | nil
  def get_org_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Org, slug: String.downcase(String.trim(slug)))
  end

  @spec list_orgs(keyword()) :: [Org.t()]
  def list_orgs(opts \\ []) do
    Org
    |> filter_status(Keyword.get(opts, :status))
    |> order_by([o], asc: o.name)
    |> Repo.all()
  end

  @doc """
  Create an org and an active owner membership for `user_id` in one transaction.

  Atomic: if either insert fails, both roll back. Used by the web
  `/organizations/new` flow so a signed-in user becomes the owner of the org
  they create without going through the invite-token lifecycle.
  """
  @spec create_org_with_owner(integer(), map()) ::
          {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
  def create_org_with_owner(user_id, attrs) when is_integer(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.insert(:org, Org.changeset(%Org{}, attrs))
    |> Multi.insert(:membership, fn %{org: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user_id,
        org_id: org.id,
        role: "owner",
        status: "active",
        accepted_at: now
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{org: org}} -> {:ok, org}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  List orgs where `user_id` has an active membership, with the user's role.

  Returns `[%{org: Org.t(), role: String.t()}]` ordered by org name.
  Used by the `/organizations` index in cloud/self_hosted mode so the UI can
  render a role badge per row. In local mode there is no user, so callers
  wrap `list_orgs/1` results with `role: nil` instead.

  Pass `min_role` to keep only orgs where the user holds at least that role
  (e.g. `"admin"` for admin-or-owner surfaces such as the mission onboarding
  org picker).
  """
  @spec list_orgs_for_user(integer(), String.t() | nil) :: [%{org: Org.t(), role: String.t()}]
  def list_orgs_for_user(user_id, min_role \\ nil) when is_integer(user_id) do
    Membership
    |> join(:inner, [m], o in Org, on: o.id == m.org_id)
    |> where([m], m.user_id == ^user_id and m.status == "active")
    |> order_by([_, o], asc: o.name)
    |> select([m, o], %{org: o, role: m.role})
    |> Repo.all()
    |> Enum.filter(fn row -> is_nil(min_role) or role_at_least?(row.role, min_role) end)
  end

  # ──────────────── Memberships ────────────

  @doc """
  Create a `pending` membership with an invitation token.

  Returns `{:ok, membership, raw_token}` so the caller can deliver the token
  out of band (email, copy-link). The token is only available once — the row
  stores its hash.

  If a revoked membership already exists for this `(user_id, org_id)` pair, it
  is revived: status resets to `pending` with a fresh token, new role, and new
  invitor. This allows re-inviting a previously removed member.

  Returns `{:error, :already_member}` if an active or pending membership
  already exists.

  ## Authorization

  When `invited_by_user_id` is supplied, the inviter's role is checked: only
  owners may grant `owner` or `admin`. A `nil` inviter is the trusted operator
  path (e.g. the CLI `org invite` command) and is unrestricted. Returns
  `{:error, :unauthorized}` when a named inviter lacks the required role.
  """
  @spec invite_member(integer(), integer(), keyword()) ::
          {:ok, Membership.t(), String.t()}
          | {:error, :already_member | :unauthorized | Ecto.Changeset.t()}
  def invite_member(user_id, org_id, opts \\ []) do
    role = Keyword.get(opts, :role, "member")
    invited_by = Keyword.get(opts, :invited_by_user_id)
    mission_workspace_id = Keyword.get(opts, :mission_workspace_id)
    raw_token = generate_token()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with :ok <- authorize_invite_role(invited_by, org_id, role) do
      case Repo.get_by(Membership, user_id: user_id, org_id: org_id) do
        nil ->
          %Membership{}
          |> Membership.changeset(%{
            user_id: user_id,
            org_id: org_id,
            role: role,
            status: "pending",
            invitation_token_hash: token_hash(raw_token),
            invited_at: now,
            invited_by_user_id: invited_by,
            mission_workspace_id: mission_workspace_id
          })
          |> Repo.insert()
          |> case do
            {:ok, membership} -> {:ok, membership, raw_token}
            {:error, _} = err -> err
          end

        %Membership{status: "revoked"} = membership ->
          membership
          |> Membership.changeset(%{
            role: role,
            status: "pending",
            invitation_token_hash: token_hash(raw_token),
            invited_at: now,
            invited_by_user_id: invited_by,
            mission_workspace_id: mission_workspace_id,
            accepted_at: nil,
            revoked_at: nil
          })
          |> Repo.update()
          |> case do
            {:ok, membership} -> {:ok, membership, raw_token}
            {:error, _} = err -> err
          end

        %Membership{} ->
          {:error, :already_member}
      end
    end
  end

  # Invite role authorization. When an inviter is named
  # (`invited_by_user_id`), enforce the same privilege boundary as role changes:
  # only owners may grant owner/admin. A `nil` inviter is the trusted operator
  # path (e.g. the CLI `org invite` command, which has no membership) and is
  # left unrestricted.
  defp authorize_invite_role(nil, _org_id, _role), do: :ok

  defp authorize_invite_role(invited_by_user_id, org_id, role) do
    inviter = get_active_membership(invited_by_user_id, org_id)

    cond do
      inviter == nil ->
        {:error, :unauthorized}

      inviter.role == "owner" ->
        :ok

      role in ["owner", "admin"] ->
        {:error, :unauthorized}

      true ->
        :ok
    end
  end

  @doc """
  Look up a pending invitation by raw token without consuming it.

  Returns `{:ok, %{membership, org, user}}` when the token matches a pending
  membership. Returns `{:error, :invalid_token}` for unknown tokens and
  `{:error, :already_accepted}` for already-redeemed memberships.

  Useful for rendering the invitation-acceptance page so the recipient can see
  which org and role they're joining before clicking accept.

  The result also exposes `mission_workspace_id` — when non-nil, the invite
  pre-binds a project workspace and cloud workspace enrolment should link
  the enrolled key to it.
  """
  @spec lookup_invitation(String.t()) ::
          {:ok,
           %{
             membership: Membership.t(),
             org: Org.t(),
             user: User.t(),
             mission_workspace_id: integer() | nil
           }}
          | {:error, :invalid_token | :already_accepted}
  def lookup_invitation(raw_token) when is_binary(raw_token) do
    hash = token_hash(raw_token)

    case Repo.get_by(Membership, invitation_token_hash: hash) do
      nil ->
        {:error, :invalid_token}

      %Membership{status: "pending"} = membership ->
        {:ok,
         %{
           membership: membership,
           org: Repo.get(Org, membership.org_id),
           user: Repo.get(User, membership.user_id),
           mission_workspace_id: membership.mission_workspace_id
         }}

      %Membership{status: "active"} ->
        {:error, :already_accepted}

      _ ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Accept an invitation by presenting the raw token.

  On success the membership flips from `pending` to `active`, the hash is
  cleared, and `accepted_at` is stamped.
  """
  @spec accept_invitation(String.t(), integer()) ::
          {:ok, Membership.t()}
          | {:error, :invalid_token | :already_accepted | Ecto.Changeset.t()}
  def accept_invitation(raw_token, user_id) when is_binary(raw_token) and is_integer(user_id) do
    hash = token_hash(raw_token)

    case Repo.get_by(Membership, invitation_token_hash: hash) do
      nil ->
        {:error, :invalid_token}

      %Membership{user_id: ^user_id, status: "pending"} = membership ->
        membership
        |> Membership.changeset(%{
          status: "active",
          invitation_token_hash: nil,
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      %Membership{status: "active"} ->
        {:error, :already_accepted}

      %Membership{} ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Revoke a membership. Authorization rules:

    * Revoker must be admin+ in the same org.
    * Only owners can revoke their own membership.
    * Owner self-revoke is blocked if they are the last active owner.
    * Only owners can revoke other owners.
    * Admins can revoke members and viewers but not owners or other admins.
  """
  @spec revoke_membership(integer(), integer()) ::
          {:ok, Membership.t()}
          | {:error,
             :not_found
             | :unauthorized
             | :cannot_revoke_owner
             | :cannot_revoke_admin
             | :cannot_self_revoke
             | :last_owner_protected
             | Ecto.Changeset.t()}
  def revoke_membership(membership_id, revoker_user_id) do
    target = Repo.get(Membership, membership_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    cond do
      is_nil(target) ->
        {:error, :not_found}

      true ->
        revoker = get_active_membership(revoker_user_id, target.org_id)

        cond do
          is_nil(revoker) || not role_at_least?(revoker.role, "admin") ->
            {:error, :unauthorized}

          target.user_id == revoker_user_id && revoker.role != "owner" ->
            {:error, :cannot_self_revoke}

          target.role == "owner" && revoker.role != "owner" ->
            {:error, :cannot_revoke_owner}

          target.role == "admin" && revoker.role != "owner" ->
            {:error, :cannot_revoke_admin}

          target.role == "owner" && last_active_owner?(target) ->
            {:error, :last_owner_protected}

          true ->
            target
            |> Membership.changeset(%{
              status: "revoked",
              invitation_token_hash: nil,
              revoked_at: now
            })
            |> Repo.update()
            |> broadcast_on_ok()
        end
    end
  end

  @doc """
  Change a membership's role. Authorization rules:

    * Revoker must be admin+ in the same org.
    * Only owners can change roles of owners and admins (exception: an admin
      may demote *themselves* from admin to member/viewer).
    * Only owners can promote a member/viewer to owner.
    * Only owners can promote a member to admin.
    * Refuses to demote the last remaining active owner.

  Returns:
    - `{:ok, membership}` on success
    - `{:error, :not_found}` if the membership doesn't exist
    - `{:error, :unauthorized}` if the revoker lacks permission
    - `{:error, :invalid_role}` if the new role is not one of owner|admin|member|viewer
    - `{:error, :last_owner_protected}` if demoting the only active owner of an org
  """
  @spec update_membership_role(integer(), String.t(), integer()) ::
          {:ok, Membership.t()}
          | {:error,
             :not_found
             | :unauthorized
             | :invalid_role
             | :last_owner_protected
             | Ecto.Changeset.t()}
  def update_membership_role(membership_id, new_role, revoker_user_id) do
    if new_role in Map.keys(@role_rank) do
      do_update_membership_role(membership_id, new_role, revoker_user_id)
    else
      {:error, :invalid_role}
    end
  end

  defp do_update_membership_role(membership_id, new_role, revoker_user_id) do
    case Repo.get(Membership, membership_id) do
      nil ->
        {:error, :not_found}

      target ->
        revoker = get_active_membership(revoker_user_id, target.org_id)

        cond do
          is_nil(revoker) || not role_at_least?(revoker.role, "admin") ->
            {:error, :unauthorized}

          # No-op: once authorized, re-selecting the current role always
          # succeeds regardless of other restrictions.
          new_role == target.role ->
            {:ok, target}

          (target.role in ["owner", "admin"] && revoker.role != "owner") and
              not (target.role == "admin" and revoker.user_id == target.user_id and
                       new_role in ["member", "viewer"]) ->
            {:error, :unauthorized}

          new_role in ["owner", "admin"] && revoker.role != "owner" ->
            {:error, :unauthorized}

          target.role == "owner" && new_role != "owner" && last_active_owner?(target) ->
            {:error, :last_owner_protected}

          true ->
            target
            |> Membership.changeset(%{role: new_role})
            |> Repo.update()
            |> broadcast_on_ok()
        end
    end
  end

  defp last_active_owner?(%Membership{org_id: org_id}) do
    count =
      Membership
      |> where([x], x.org_id == ^org_id and x.role == "owner" and x.status == "active")
      |> Repo.aggregate(:count)

    count <= 1
  end

  @doc "Update an Org's mutable fields (name, status, settings)."
  @spec update_org(Org.t(), map()) :: {:ok, Org.t()} | {:error, Ecto.Changeset.t()}
  def update_org(%Org{} = org, attrs) do
    org
    |> Org.changeset(attrs)
    |> Repo.update()
  end

  # ──────────────── Real-time membership broadcasts ──────

  @doc """
  PubSub topic for membership changes affecting a specific user. LiveViews
  subscribe to this topic in `LiveAuth.on_mount/4` so a revoke or role-change
  evicts the user across all open tabs within a single PubSub roundtrip.
  """
  @spec membership_topic(integer()) :: String.t()
  def membership_topic(user_id) when is_integer(user_id), do: "membership:user:#{user_id}"

  @doc """
  PubSub topic for sign-out-everywhere broadcasts targeting a specific user.
  When triggered, all connected LiveViews for that user redirect to /auth/login.
  """
  @spec signout_topic(integer()) :: String.t()
  def signout_topic(user_id) when is_integer(user_id), do: "signout:user:#{user_id}"

  @doc """
  Broadcast a sign-out-everywhere event to all connected LiveViews for the
  given user. Used from the org settings "Sign out everywhere" button and can
  also be called from a future security incident response flow.
  """
  @spec sign_out_everywhere(integer()) :: :ok
  def sign_out_everywhere(user_id) when is_integer(user_id) do
    Phoenix.PubSub.broadcast(ControlKeel.PubSub, signout_topic(user_id), :sign_out_everywhere)
    :ok
  end

  defp broadcast_membership_change(%Membership{user_id: user_id} = m)
       when is_integer(user_id) do
    Phoenix.PubSub.broadcast(
      ControlKeel.PubSub,
      membership_topic(user_id),
      {:membership_changed, m}
    )
  end

  defp broadcast_membership_change(_), do: :ok

  # Convenience tap on the Repo.update/1 result tuple. Broadcast on success,
  # pass errors through unchanged.
  defp broadcast_on_ok({:ok, %Membership{} = m} = result) do
    broadcast_membership_change(m)
    result
  end

  defp broadcast_on_ok(other), do: other

  @spec get_membership(integer()) :: Membership.t() | nil
  def get_membership(id), do: Repo.get(Membership, id)

  @doc """
  List memberships for an org, excluding revoked rows by default.

  Revoked memberships are hidden unless explicitly requested:
    * pass `status: "revoked"` to see only revoked rows, or
    * pass `include_revoked: true` to see every row regardless of status.

  Any other explicit `status:` value (`"active"`, `"pending"`) is honored as
  an exact match and bypasses the default revocation filter.
  """
  @spec list_memberships_for_org(integer(), keyword()) :: [Membership.t()]
  def list_memberships_for_org(org_id, opts \\ []) do
    Membership
    |> where([m], m.org_id == ^org_id)
    |> filter_status(Keyword.get(opts, :status))
    |> maybe_exclude_revoked(opts)
    |> order_by([m], asc: m.id)
    |> Repo.all()
  end

  @spec count_memberships_for_org(integer()) :: non_neg_integer()
  def count_memberships_for_org(org_id) do
    Membership
    |> where([m], m.org_id == ^org_id and m.status == "active")
    |> Repo.aggregate(:count, :id)
  end

  @spec list_memberships_for_user(integer(), keyword()) :: [Membership.t()]
  def list_memberships_for_user(user_id, opts \\ []) do
    Membership
    |> where([m], m.user_id == ^user_id)
    |> filter_status(Keyword.get(opts, :status))
    |> order_by([m], asc: m.id)
    |> Repo.all()
  end

  @doc "Return the active membership for a user/org pair, or nil."
  @spec get_active_membership(integer(), integer()) :: Membership.t() | nil
  def get_active_membership(user_id, org_id) do
    Repo.get_by(Membership, user_id: user_id, org_id: org_id, status: "active")
  end

  @doc "True when the role is at least the required role in the org ladder."
  @spec role_at_least?(String.t() | nil, String.t() | nil) :: boolean()
  def role_at_least?(role, required) do
    Map.get(@role_rank, role || "", -1) >= Map.get(@role_rank, required || "viewer", 0)
  end

  # ──────────────── Workspace linkage ──────

  @doc """
  Link a workspace to an org. Pass `org_id: nil` to detach.

  Returns `{:error, :not_found}` when the workspace doesn't exist.
  """
  @spec assign_workspace_to_org(integer(), integer() | nil) ::
          {:ok, Workspace.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def assign_workspace_to_org(workspace_id, org_id) do
    case Repo.get(Workspace, workspace_id) do
      nil ->
        {:error, :not_found}

      workspace ->
        workspace
        |> Ecto.Changeset.change(%{org_id: org_id})
        |> Repo.update()
    end
  end

  @doc "List workspaces belonging to an org."
  @spec list_workspaces_for_org(integer()) :: [Workspace.t()]
  def list_workspaces_for_org(org_id) when is_integer(org_id) do
    Workspace
    |> where([w], w.org_id == ^org_id)
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  @doc "List unaffiliated workspaces (no org assigned)."
  @spec list_unaffiliated_workspaces() :: [Workspace.t()]
  def list_unaffiliated_workspaces do
    Workspace
    |> where([w], is_nil(w.org_id))
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  @doc """
  Shared web-tier session-access gate (issue #141, R2).

  Unlike the cookie-scoped check it replaces, the decision is keyed on the
  runtime mode and the signed-in user — never on an ambient org id (which
  production never writes, so it fail-opened every cloud read path):

    * local mode → `true` (single-user deployment, no user model);
    * cloud/self_hosted → the session's workspace must authorize `user`
      via `authorize_cloud_execution/2` with at least viewer membership in
      an active org. A missing user **denies**.

  Callers pass `socket.assigns[:current_user]` / `conn.assigns[:current_user]`.
  """
  @spec session_accessible?(%{workspace_id: integer() | nil} | nil, map() | nil) :: boolean()
  def session_accessible?(session, user) do
    cond do
      ControlKeel.Runtime.Mode.current() == :local -> true
      is_nil(user) -> false
      true -> session_authorized?(session, user)
    end
  end

  defp session_authorized?(%{workspace_id: workspace_id}, %{id: user_id})
       when is_integer(workspace_id) and is_integer(user_id) do
    case authorize_cloud_execution(workspace_id, user_id: user_id, required_role: "viewer") do
      {:ok, :authorized} -> true
      _ -> false
    end
  end

  defp session_authorized?(_session, _user), do: false

  @doc """
  First active membership's org id for a user, or `nil`.

  Used as the default-org hint where the browser session never recorded one
  (production never writes `current_org_id` — issue #141). Access decisions
  must not rely on this; the shared gates above resolve authority from
  `(user, resource)` instead.
  """
  @spec default_org_for_user(integer()) :: integer() | nil
  def default_org_for_user(user_id) when is_integer(user_id) do
    case list_memberships_for_user(user_id, status: "active") do
      [%Membership{org_id: org_id} | _] -> org_id
      _ -> nil
    end
  end

  @doc "True when the user holds at least one active org membership."
  @spec any_active_membership?(integer()) :: boolean()
  def any_active_membership?(user_id) when is_integer(user_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.status == "active")
    |> limit(1)
    |> Repo.one()
    |> is_struct(Membership)
  end

  @doc """
  List workspaces visible to a user through their active memberships.

  Returns workspaces of every org where the user has an `active` membership.
  Unaffiliated workspaces (org_id nil) are not returned — those are treated as
  individual-mode and addressed separately via the local-first surfaces.
  """
  @spec list_workspaces_for_user(integer()) :: [Workspace.t()]
  def list_workspaces_for_user(user_id) when is_integer(user_id) do
    Workspace
    |> join(:inner, [w], m in Membership,
      on: m.org_id == w.org_id and m.user_id == ^user_id and m.status == "active"
    )
    |> distinct(true)
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  # ──────────────── Org budgets ────────────

  @doc """
  Read the org's configured budget cap in cents.

  Stored in `Org.settings["budget_cents"]` so no schema migration is required.
  Returns `nil` when unset (no cap).
  """
  @spec org_budget_cents(integer() | Org.t()) :: non_neg_integer() | nil
  def org_budget_cents(%Org{settings: settings}), do: extract_budget_cents(settings)

  def org_budget_cents(org_id) when is_integer(org_id) do
    case Repo.get(Org, org_id) do
      %Org{} = org -> org_budget_cents(org)
      _ -> nil
    end
  end

  @doc """
  Set or clear the org budget cap. Pass `nil` or `0` to clear.

  Only persists the budget field; other settings keys are preserved.
  """
  @spec set_org_budget_cents(integer(), non_neg_integer() | nil) ::
          {:ok, Org.t()} | {:error, :not_found | Ecto.Changeset.t() | :invalid}
  def set_org_budget_cents(org_id, cents) when is_integer(cents) and cents >= 0 do
    do_set_org_budget(org_id, cents)
  end

  def set_org_budget_cents(org_id, nil), do: do_set_org_budget(org_id, nil)
  def set_org_budget_cents(_, _), do: {:error, :invalid}

  defp do_set_org_budget(org_id, cents) do
    case Repo.get(Org, org_id) do
      nil ->
        {:error, :not_found}

      %Org{} = org ->
        settings =
          org.settings
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> put_or_drop_budget(cents)

        org
        |> Org.changeset(%{settings: settings})
        |> Repo.update()
    end
  end

  defp put_or_drop_budget(settings, nil), do: Map.delete(settings, @org_budget_setting_key)
  defp put_or_drop_budget(settings, 0), do: Map.delete(settings, @org_budget_setting_key)
  defp put_or_drop_budget(settings, cents), do: Map.put(settings, @org_budget_setting_key, cents)

  defp extract_budget_cents(nil), do: nil
  defp extract_budget_cents(%{} = settings) when settings == %{}, do: nil

  defp extract_budget_cents(%{} = settings) do
    case Map.get(settings, @org_budget_setting_key) || Map.get(settings, :budget_cents) do
      n when is_integer(n) and n > 0 -> n
      _ -> nil
    end
  end

  defp extract_budget_cents(_), do: nil

  @doc """
  Sum of `spent_cents` across all sessions in workspaces belonging to the org.
  Returns `0` when the org has no workspaces or no sessions yet.
  """
  @spec org_spend_cents(integer()) :: non_neg_integer()
  def org_spend_cents(org_id) when is_integer(org_id) do
    query =
      from s in Session,
        join: w in Workspace,
        on: w.id == s.workspace_id,
        where: w.org_id == ^org_id,
        select: coalesce(sum(s.spent_cents), 0)

    Repo.one(query) || 0
  end

  @doc """
  Per-workspace spend within an org, sorted by spend descending.

  Returns `[%{workspace_id, workspace_name, workspace_slug, spent_cents}]`.
  """
  @spec org_workspace_breakdown(integer()) :: [map()]
  def org_workspace_breakdown(org_id) when is_integer(org_id) do
    spend_subquery =
      from s in Session,
        group_by: s.workspace_id,
        select: %{workspace_id: s.workspace_id, spent_cents: coalesce(sum(s.spent_cents), 0)}

    query =
      from w in Workspace,
        left_join: spend in subquery(spend_subquery),
        on: spend.workspace_id == w.id,
        where: w.org_id == ^org_id,
        order_by: [desc: coalesce(spend.spent_cents, 0), asc: w.name],
        select: %{
          workspace_id: w.id,
          workspace_name: w.name,
          workspace_slug: w.slug,
          spent_cents: coalesce(spend.spent_cents, 0)
        }

    Repo.all(query)
  end

  @doc """
  Check if a workspace's owning org is over its budget cap.

  Returns `{:over_cap, status}` when the workspace belongs to an org with a
  budget cap and the rolled-up spend exceeds it. Returns `:ok` for solo
  workspaces (no org) and for affiliated workspaces under their cap.
  """
  @spec workspace_org_cap_status(integer()) :: :ok | {:over_cap, map()}
  def workspace_org_cap_status(workspace_id) when is_integer(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{org_id: org_id} when is_integer(org_id) ->
        status = org_budget_status(org_id)
        if status.over_cap?, do: {:over_cap, status}, else: :ok

      _ ->
        :ok
    end
  end

  @doc """
  Compact budget posture for an org.
  """
  @spec org_budget_status(integer()) :: %{
          org_id: integer(),
          budget_cents: non_neg_integer() | nil,
          spent_cents: non_neg_integer(),
          remaining_cents: non_neg_integer() | nil,
          workspace_count: non_neg_integer(),
          over_cap?: boolean()
        }
  def org_budget_status(org_id) when is_integer(org_id) do
    budget = org_budget_cents(org_id)
    spent = org_spend_cents(org_id)
    workspaces = list_workspaces_for_org(org_id)

    remaining =
      case budget do
        nil -> nil
        n -> max(n - spent, 0)
      end

    %{
      org_id: org_id,
      budget_cents: budget,
      spent_cents: spent,
      remaining_cents: remaining,
      workspace_count: length(workspaces),
      over_cap?: not is_nil(budget) and spent > budget
    }
  end

  # ──────────────── Org identity providers ─

  # ──────────────── Team review flow ───────

  @doc """
  Assign a review to a user.

  The assignee must be an active member of the workspace's org. If the review's
  workspace has no org (solo workspace), assignment is rejected — solo
  workspaces use the existing single-user approve flow.

  Pass `required_role:` (e.g. "admin") to require that the eventual decider
  hold at least that role. The assignee themselves does not need that role;
  only the user who calls `decide_review/4` is gated.
  """
  @spec assign_review(integer(), integer(), keyword()) ::
          {:ok, Review.t()}
          | {:error,
             :review_not_found
             | :workspace_unaffiliated
             | :assignee_not_member
             | Ecto.Changeset.t()}
  def assign_review(review_id, assignee_user_id, opts \\ []) do
    actor_id = Keyword.get(opts, :actor_user_id)
    required_role = Keyword.get(opts, :required_role)
    note = Keyword.get(opts, :note)

    with {:ok, review} <- fetch_review(review_id),
         {:ok, org_id} <- review_org_id(review),
         :ok <- ensure_active_member(assignee_user_id, org_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      previous_assigned = review.assigned_user_id

      with {:ok, updated} <-
             review
             |> Review.changeset(%{
               assigned_user_id: assignee_user_id,
               assigned_by_user_id: actor_id,
               assigned_at: now,
               required_role: required_role
             })
             |> Repo.update() do
        event_type = if previous_assigned, do: "reassigned", else: "assigned"

        _ =
          record_review_event(review_id, %{
            event_type: event_type,
            actor_user_id: actor_id,
            target_user_id: assignee_user_id,
            required_role: required_role,
            actor_role: nil,
            note: note,
            recorded_at: now
          })

        {:ok, updated}
      end
    end
  end

  @doc """
  Record a decision on a review.

  Decision must be `:approved` or `:denied`. Authorisation rules:

    1. Decider must be an active member of the workspace's org.
    2. If the review has an `assigned_user_id`, the decider must match it OR
       hold `admin`/`owner` role (override authority).
    3. If the review has a `required_role`, the decider's actual role must be
       at least as high in the role ladder.

  All checks are recorded as an audit event whether or not the decision is
  accepted.
  """
  @spec decide_review(integer(), integer(), :approved | :denied, keyword()) ::
          {:ok, Review.t()}
          | {:error,
             :review_not_found
             | :workspace_unaffiliated
             | :not_a_member
             | :not_assigned
             | :insufficient_role
             | :already_decided
             | Ecto.Changeset.t()}
  def decide_review(review_id, decider_user_id, decision, opts \\ [])
      when decision in [:approved, :denied] do
    note = Keyword.get(opts, :feedback_notes)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, review} <- fetch_review(review_id),
         :ok <- ensure_not_decided(review),
         {:ok, org_id} <- review_org_id(review),
         {:ok, role} <- fetch_active_role(decider_user_id, org_id),
         :ok <- ensure_assignee_or_override(review, decider_user_id, role),
         :ok <- ensure_required_role(review.required_role, role) do
      decision_str = Atom.to_string(decision)

      with {:ok, updated} <-
             review
             |> Review.changeset(%{
               status: decision_str,
               decided_by_user_id: decider_user_id,
               reviewed_by: "user:#{decider_user_id}",
               responded_at: now,
               feedback_notes: note
             })
             |> Repo.update() do
        _ =
          record_review_event(review_id, %{
            event_type: decision_str,
            actor_user_id: decider_user_id,
            target_user_id: review.assigned_user_id,
            required_role: review.required_role,
            actor_role: role,
            actor_source: "user",
            actor_identifier: Integer.to_string(decider_user_id),
            note: note,
            recorded_at: now
          })

        {:ok, updated}
      end
    else
      {:error, reason} = err when is_atom(reason) ->
        _ =
          record_review_event(review_id, %{
            event_type: "denied",
            actor_user_id: decider_user_id,
            required_role: nil,
            actor_role: nil,
            actor_source: "user",
            actor_identifier: Integer.to_string(decider_user_id),
            note: "rejected by policy: #{reason}",
            recorded_at: now
          })

        err
    end
  end

  @doc "List audit events for a review, oldest first."
  @spec review_audit_events(integer()) :: [ReviewAuditEvent.t()]
  def review_audit_events(review_id) do
    ReviewAuditEvent
    |> where([e], e.review_id == ^review_id)
    |> order_by([e], asc: e.recorded_at, asc: e.id)
    |> Repo.all()
  end

  @doc "Record an immutable audit event for a live review decision path."
  @spec record_review_decision_event(Review.t(), map()) ::
          {:ok, ReviewAuditEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_review_decision_event(%Review{} = review, attrs) when is_map(attrs) do
    now = Map.get(attrs, :recorded_at) || DateTime.utc_now() |> DateTime.truncate(:second)
    event_type = Map.fetch!(attrs, :event_type)
    actor_user_id = Map.get(attrs, :actor_user_id)

    actor_source =
      Map.get(attrs, :actor_source) || actor_source(actor_user_id, review.reviewed_by)

    record_review_event(review.id, %{
      event_type: event_type,
      actor_user_id: actor_user_id,
      target_user_id: review.assigned_user_id,
      required_role: review.required_role,
      actor_role: Map.get(attrs, :actor_role),
      actor_source: actor_source,
      actor_identifier:
        Map.get(attrs, :actor_identifier) || actor_identifier(actor_user_id, actor_source),
      note: Map.get(attrs, :note),
      recorded_at: now
    })
  end

  defp fetch_review(id) do
    case Repo.get(Review, id) do
      nil -> {:error, :review_not_found}
      review -> {:ok, review}
    end
  end

  defp ensure_not_decided(%Review{status: "pending"}), do: :ok
  defp ensure_not_decided(_), do: {:error, :already_decided}

  defp review_org_id(%Review{session_id: session_id}) do
    with %Session{workspace_id: workspace_id} <- Repo.get(Session, session_id),
         %Workspace{org_id: org_id} when not is_nil(org_id) <-
           Repo.get(Workspace, workspace_id) do
      {:ok, org_id}
    else
      _ -> {:error, :workspace_unaffiliated}
    end
  end

  defp ensure_active_member(user_id, org_id) do
    case Repo.get_by(Membership, user_id: user_id, org_id: org_id, status: "active") do
      %Membership{} -> :ok
      _ -> {:error, :assignee_not_member}
    end
  end

  defp fetch_active_role(user_id, org_id) do
    case Repo.get_by(Membership, user_id: user_id, org_id: org_id, status: "active") do
      %Membership{role: role} -> {:ok, role}
      _ -> {:error, :not_a_member}
    end
  end

  defp ensure_assignee_or_override(%Review{assigned_user_id: nil}, _decider_id, _role), do: :ok

  defp ensure_assignee_or_override(%Review{assigned_user_id: assigned}, decider, _role)
       when assigned == decider,
       do: :ok

  defp ensure_assignee_or_override(_review, _decider, role) when role in ["owner", "admin"],
    do: :ok

  defp ensure_assignee_or_override(_, _, _), do: {:error, :not_assigned}

  defp ensure_required_role(nil, _actor_role), do: :ok

  defp ensure_required_role(required, actor) do
    required_rank = Map.get(@role_rank, required, 0)
    actor_rank = Map.get(@role_rank, actor, 0)
    if actor_rank >= required_rank, do: :ok, else: {:error, :insufficient_role}
  end

  defp record_review_event(review_id, attrs) do
    %ReviewAuditEvent{}
    |> ReviewAuditEvent.changeset(Map.put(attrs, :review_id, review_id))
    |> Repo.insert()
  end

  defp actor_source(_actor_user_id, reviewed_by)
       when is_binary(reviewed_by) and reviewed_by != "" do
    reviewed_by
  end

  defp actor_source(actor_user_id, _reviewed_by) when is_integer(actor_user_id), do: "user"
  defp actor_source(_actor_user_id, _reviewed_by), do: "unknown"

  defp actor_identifier(actor_user_id, _actor_source) when is_integer(actor_user_id) do
    Integer.to_string(actor_user_id)
  end

  defp actor_identifier(_actor_user_id, actor_source), do: actor_source

  # ──────────────── Helpers ────────────────

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [x], x.status == ^status)

  # Revoked rows are hidden by default. Skip the filter when an explicit
  # `status:` is given (exact match wins) or the caller opts in via
  # `include_revoked: true`.
  defp maybe_exclude_revoked(query, opts) do
    if Keyword.get(opts, :status) || Keyword.get(opts, :include_revoked, false) do
      query
    else
      where(query, [m], m.status != "revoked")
    end
  end

  # ---------------------------------------------------------------------------
  # Workspace tool catalog policies
  # ---------------------------------------------------------------------------

  @doc """
  Returns the tool policy for `workspace_id`, or a default `:inherit` policy
  if none has been configured.
  """
  @spec get_workspace_tool_policy(integer()) :: WorkspaceToolPolicy.t()
  def get_workspace_tool_policy(workspace_id) when is_integer(workspace_id) do
    Repo.get_by(WorkspaceToolPolicy, workspace_id: workspace_id) ||
      %WorkspaceToolPolicy{workspace_id: workspace_id, mode: "inherit", tools: "[]"}
  end

  @doc """
  Upserts the tool policy for `workspace_id`.

  `mode` must be one of `"inherit"`, `"allowlist"`, or `"denylist"`.
  `tools` is a list of tool name strings.
  """
  @spec set_workspace_tool_policy(integer(), String.t(), [String.t()]) ::
          {:ok, WorkspaceToolPolicy.t()} | {:error, Ecto.Changeset.t()}
  def set_workspace_tool_policy(workspace_id, mode, tools)
      when is_integer(workspace_id) and is_binary(mode) and is_list(tools) do
    existing = Repo.get_by(WorkspaceToolPolicy, workspace_id: workspace_id)

    attrs = %{workspace_id: workspace_id, mode: mode, tools: tools_for_mode(mode, tools)}

    changeset =
      case existing do
        nil -> WorkspaceToolPolicy.changeset(%WorkspaceToolPolicy{}, attrs)
        record -> WorkspaceToolPolicy.changeset(record, attrs)
      end

    Repo.insert_or_update(changeset)
  end

  # Under `inherit` the tools list is inert — never store stale selections.
  defp tools_for_mode("inherit", _tools), do: []
  defp tools_for_mode(_mode, tools), do: tools

  @doc """
  Checks `tool_name` against the workspace's tool policy. Returns `:ok` to
  allow, `{:error, {:policy, reason}}` to deny.
  """
  @spec check_workspace_tool_policy(integer() | nil, String.t()) ::
          :ok | {:error, {:policy, atom()}}
  def check_workspace_tool_policy(nil, _tool_name), do: :ok

  def check_workspace_tool_policy(workspace_id, tool_name)
      when is_integer(workspace_id) and is_binary(tool_name) do
    policy = get_workspace_tool_policy(workspace_id)
    tools = WorkspaceToolPolicy.decode_tools(policy)

    case policy.mode do
      "inherit" ->
        :ok

      "allowlist" ->
        if tool_name in tools,
          do: :ok,
          else: {:error, {:policy, :tool_not_in_workspace_allowlist}}

      "denylist" ->
        if tool_name in tools, do: {:error, {:policy, :tool_in_workspace_denylist}}, else: :ok

      _ ->
        :ok
    end
  end

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp token_hash(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  # ──────────────── Cloud execution authorization ──────

  @doc """
  Authorize a cloud execution request for a workspace.

  When the workspace belongs to an org, the caller must present a user_id with
  an active membership at or above `required_role` (default `"member"`). Solo
  workspaces (no org) are always authorized — the local-first trust anchor
  applies.

  Returns `{:ok, :authorized}` or `{:error, reason}`.
  """
  @spec authorize_cloud_execution(integer(), keyword()) ::
          {:ok, :authorized} | {:error, :not_found | :unauthorized | :org_suspended}
  def authorize_cloud_execution(workspace_id, opts \\ []) when is_integer(workspace_id) do
    required_role = Keyword.get(opts, :required_role, "member")
    user_id = Keyword.get(opts, :user_id)

    case Repo.get(Workspace, workspace_id) do
      nil ->
        {:error, :not_found}

      %Workspace{org_id: nil} ->
        {:ok, :authorized}

      %Workspace{org_id: org_id} ->
        org = Repo.get(Org, org_id)

        cond do
          is_nil(org) or org.status != "active" ->
            {:error, :org_suspended}

          is_nil(user_id) ->
            {:error, :unauthorized}

          true ->
            case get_active_membership(user_id, org_id) do
              %Membership{role: role} when is_binary(role) ->
                if role_at_least?(role, required_role) do
                  {:ok, :authorized}
                else
                  {:error, :unauthorized}
                end

              _ ->
                {:error, :unauthorized}
            end
        end
    end
  end
end
