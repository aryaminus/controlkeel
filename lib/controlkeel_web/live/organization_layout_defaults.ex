defmodule ControlKeelWeb.OrganizationLayoutDefaults do
  @moduledoc """
  Provides assigns consumed by the organization framework layout.

  Organization LiveViews assign `nav_org` after mounting (and `nav_workspace`
  on workspace pages, which switches the sidebar to workspace nav). This hook
  supplies the shared URL, breadcrumb, and navigation assigns independently
  from the dashboard layout defaults.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  def on_mount(_arg, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> assign(:current_query, nil)
      |> assign_new(:nav_org, fn -> nil end)
      |> assign_new(:nav_workspace, fn -> nil end)
      |> assign_new(:nav_session, fn -> nil end)
      |> assign_new(:breadcrumbs, fn -> nil end)
      |> assign_new(:sibling_workspaces, fn -> [] end)
      |> assign_new(:sibling_sessions, fn -> [] end)
      |> assign_new(:sibling_workspaces_org_id, fn -> nil end)
      |> assign_new(:nav_org_admin?, fn -> false end)
      |> assign_new(:nav_org_admin_org_id, fn -> nil end)
      |> attach_hook(:__organization_current_path__, :handle_params, fn _params, uri, socket ->
        parsed = URI.parse(uri)

        {:cont,
         socket
         |> assign(:current_path, parsed.path)
         |> assign(:current_query, parsed.query)
         |> maybe_assign_sibling_workspaces()
         |> maybe_assign_nav_org_admin()}
      end)

    {:cont, socket}
  end

  # Workspace pages get the org's workspace list for the breadcrumb switcher.
  # Org-level pages keep the default (`[]`) so no switcher renders.
  # Memoized per org: `handle_params` fires on every patch within the same
  # LiveView, but the org-scoped list can't change without a remount
  # (cross-view navigation remounts and resets the assigns).
  defp maybe_assign_sibling_workspaces(
         %{assigns: %{sibling_workspaces_org_id: org_id, nav_org: %{id: org_id}}} = socket
       )
       when is_integer(org_id),
       do: socket

  defp maybe_assign_sibling_workspaces(
         %{assigns: %{nav_workspace: %{slug: _}, nav_org: %{id: org_id}}} = socket
       )
       when is_integer(org_id) do
    socket
    |> assign(:sibling_workspaces, Mission.list_workspaces_for_org_recent_first(org_id))
    |> assign(:sibling_workspaces_org_id, org_id)
  end

  defp maybe_assign_sibling_workspaces(socket), do: socket

  # Admin/owner status of the viewer in nav_org (issue #183): gates whether
  # the layout-level "New Session" header action carries org/workspace slug
  # params. Memoized per org exactly like sibling workspaces above; local
  # mode (no user) stays false, matching the bare-link behavior.
  defp maybe_assign_nav_org_admin(
         %{assigns: %{nav_org_admin_org_id: org_id, nav_org: %{id: org_id}}} = socket
       )
       when is_integer(org_id),
       do: socket

  defp maybe_assign_nav_org_admin(%{assigns: %{nav_org: %{id: org_id}}} = socket)
       when is_integer(org_id) do
    admin? =
      case socket.assigns[:current_user] do
        %{id: user_id} when is_integer(user_id) ->
          membership = Accounts.get_active_membership(user_id, org_id)
          Accounts.role_at_least?(membership && membership.role, "admin")

        _ ->
          false
      end

    socket
    |> assign(:nav_org_admin?, admin?)
    |> assign(:nav_org_admin_org_id, org_id)
  end

  defp maybe_assign_nav_org_admin(socket),
    do: socket |> assign(:nav_org_admin?, false) |> assign(:nav_org_admin_org_id, nil)
end
