defmodule ControlKeelWeb.OrgScope do
  @moduledoc """
  In-place not-found handling for the org-level pages (`/:org_slug` and
  `/:org_slug/settings`).

  These pages used to bounce an unknown `org_slug` to the global
  `/organizations` list with a flash. That list is being sunset (global pages
  are orphans on the way out), so org-level page resolution now records a
  structured error on the socket instead of redirecting:

    * the requested URL is preserved, so the visitor can see and fix it
    * no server redirect means no interaction with the `/:org_slug` catch-all
      or the client-side last-path restore on `/` — the two redirect loops the
      global fallback used to invite
    * the message renders in the body via
      `ControlKeelWeb.OrganizationLayouts.organization_scope_not_found/1`,
      which `organization.html.heex` renders in place of the org chrome (an
      unknown org slug has no sidebar to render)

  A LiveView assigns the result of one of the builders below to
  `:org_scope_error` and adds an early clause that matches only a real error
  (`def render(%{org_scope_error: error}) when not is_nil(error)`). The assign
  is always present because `ControlKeelWeb.OrganizationLayoutDefaults`
  defaults it to `nil`, so a bare `%{org_scope_error: _}` pattern would shadow
  the real render on every org page.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org

  @typedoc """
  Everything the not-found panel needs to explain the miss.

  `:title`/`:message` are pre-composed so the panel stays a dumb renderer;
  `:org_slug` echoes back the offending URL segment, which is the value the
  visitor needs to see to fix the address.
  """
  @type error :: %{
          required(:title) => String.t(),
          required(:message) => String.t(),
          required(:org_slug) => String.t() | nil
        }

  @doc """
  Resolves the org for a URL slug. Returns `nil` when it does not exist.

  This is the single lookup org-level LiveViews use before mounting, so
  "unknown org" and "org exists but is not accessible" stay separate
  concerns (existence here, authorization via `ControlKeelWeb.OrgAccess`).
  """
  @spec fetch(String.t() | nil) :: Org.t() | nil
  def fetch(slug) when is_binary(slug), do: Accounts.get_org_by_slug(slug)
  def fetch(_), do: nil

  @doc """
  Error for an `org_slug` that resolves to no org.
  """
  @spec org_not_found(String.t() | nil) :: error()
  def org_not_found(slug) do
    %{
      title: "Organization not found",
      message: "No organization exists at this address. It may have been renamed or deleted.",
      org_slug: slug
    }
  end

  @doc """
  Error for an org the signed-in visitor cannot view.

  Reserved for authorization failures on an org that *does* exist, so the
  copy can talk about access rather than existence.
  """
  @spec org_forbidden(String.t() | nil, String.t()) :: error()
  def org_forbidden(slug, message) do
    %{title: "Organization unavailable", message: message, org_slug: slug}
  end
end
