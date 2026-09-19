defmodule ControlKeelWeb.OrganizationLayoutDefaults do
  @moduledoc """
  Provides assigns consumed by the organization framework layout.

  Organization LiveViews assign `nav_org` after mounting (and `nav_workspace`
  on workspace pages, which switches the sidebar to workspace nav). This hook
  supplies the shared URL, header-action, and breadcrumb assigns independently
  from the dashboard layout defaults.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias ControlKeel.Mission

  def on_mount(_arg, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> assign(:current_query, nil)
      |> assign_new(:nav_org, fn -> nil end)
      |> assign_new(:nav_workspace, fn -> nil end)
      |> assign_new(:nav_session, fn -> nil end)
      |> assign_new(:page_action, fn -> nil end)
      |> assign_new(:breadcrumbs, fn -> nil end)
      |> assign_new(:sibling_workspaces, fn -> [] end)
      |> assign_new(:sibling_sessions, fn -> [] end)
      |> assign_new(:sibling_workspaces_org_id, fn -> nil end)
      |> attach_hook(:__organization_current_path__, :handle_params, fn _params, uri, socket ->
        parsed = URI.parse(uri)

        {:cont,
         socket
         |> assign(:current_path, parsed.path)
         |> assign(:current_query, parsed.query)
         |> maybe_assign_sibling_workspaces()}
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
end
