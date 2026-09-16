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
      |> assign_new(:page_action, fn -> nil end)
      |> assign_new(:breadcrumbs, fn -> nil end)
      |> assign_new(:sibling_workspaces, fn -> [] end)
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
  defp maybe_assign_sibling_workspaces(
         %{assigns: %{nav_workspace: %{slug: _}, nav_org: %{id: org_id}}} = socket
       ) do
    siblings =
      org_id
      |> Mission.list_workspaces_for_org()
      |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})

    assign(socket, :sibling_workspaces, siblings)
  end

  defp maybe_assign_sibling_workspaces(socket), do: socket
end
