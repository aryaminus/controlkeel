defmodule ControlKeelWeb.OrgAccess do
  @moduledoc """
  Org-level resolution and authorization in one step.

  An org-level page (`/:org_slug`, `/:org_slug/settings`) needs two answers
  before it can render: does this slug point at a real org, and may this
  visitor use it? The second question is meaningless until the first is yes, so
  `resolve/3` answers them together, in order:

    * `{:ok, org, membership}` — the org exists and the visitor is allowed
    * `{:error, error}` — the org does not exist, or the visitor may not use it

  The error carries a `:kind` (`:not_found`, `:forbidden`, `:needs_admin`) so a
  caller can present the cases differently when it matters, plus the
  pre-composed `:title`/`:message` the shared panel renders.

  `:not_found` and `:forbidden` deliberately share the same public copy: an
  outsider must not be able to tell an existing org from a missing one by the
  response. `:needs_admin` is different — the visitor is a member and already
  knows the org exists, so it says access is insufficient.

  Decision inputs:

    * **url slug** — existence lookup (`Accounts.get_org_by_slug/1`)
    * **user** — the signed-in user, or `nil`
    * **required role** — `"viewer"` for viewing, `"admin"` for settings
      (default `"viewer"`). This is resolved per URL and is **not** the
      session's pinned `current_membership`.

  Local mode has no membership table and is unrestricted.

  ## Rendering the failure

  A scoped LiveView assigns the error to `:scope_error` and adds an early
  render clause matching only a real error
  (`def render(%{scope_error: error}) when not is_nil(error)`). The assign is
  always present because `ControlKeelWeb.OrganizationLayoutDefaults` defaults
  it to `nil`; a bare `%{scope_error: _}` pattern would shadow the real render
  on every org page.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Runtime.Mode
  alias ControlKeelWeb.ScopeError

  @typedoc """
  Why the URL cannot be used.

    * `:not_found` — the slug resolves to no org
    * `:forbidden` — the org exists but the visitor has no active membership
    * `:needs_admin` — the visitor is a member below the required role
  """
  @type kind :: ScopeError.kind()

  @typedoc """
  Everything the scope panel needs to explain the miss.

  `:title`/`:message` are pre-composed so the panel stays a dumb renderer;
  `:org_slug` echoes back the offending URL segment.
  """
  @type error :: ScopeError.t()

  @type result :: {:ok, Org.t(), Accounts.Membership.t() | nil} | {:error, error()}

  @doc """
  Resolve the org for a URL slug and gate the visitor at `required_role`.

  Existence is checked before authorization. `membership` is `nil` in local
  mode, which has no membership table.
  """
  @spec resolve(String.t() | nil, map() | nil, String.t()) :: result()
  def resolve(slug, user, required_role \\ "viewer") do
    case fetch(slug) do
      nil ->
        {:error, not_found(slug)}

      %Org{} = org ->
        case check(org, user, required_role) do
          {:ok, membership} -> {:ok, org, membership}
          {:error, :forbidden} -> {:error, forbidden(slug)}
          {:error, :needs_admin} -> {:error, needs_admin(slug)}
        end
    end
  end

  # --- Existence ---------------------------------------------------------

  defp fetch(slug) when is_binary(slug), do: Accounts.get_org_by_slug(slug)
  defp fetch(_), do: nil

  # --- Authorization -----------------------------------------------------

  defp check(%Org{} = org, user, required_role) do
    cond do
      Mode.current() == :local -> {:ok, nil}
      is_nil(user) -> {:error, :forbidden}
      true -> check_membership(org, user, required_role)
    end
  end

  defp check_membership(%Org{id: org_id}, %{id: user_id}, required_role)
       when is_integer(org_id) and is_integer(user_id) do
    case Accounts.get_active_membership(user_id, org_id) do
      nil ->
        {:error, :forbidden}

      %Accounts.Membership{} = membership ->
        if Accounts.role_at_least?(membership.role, required_role),
          do: {:ok, membership},
          else: {:error, :needs_admin}
    end
  end

  defp check_membership(_org, _user, _required_role), do: {:error, :forbidden}

  # --- Error payloads ----------------------------------------------------

  defp not_found(slug), do: ScopeError.org(slug, :not_found)

  # Same public copy as `not_found/1`; only `:kind` differs. This keeps the
  # page from being usable to enumerate org slugs.
  defp forbidden(slug), do: ScopeError.org(slug, :forbidden)

  defp needs_admin(slug), do: ScopeError.org(slug, :needs_admin)
end
