defmodule ControlKeelWeb.OrganizationLayoutDefaults do
  @moduledoc """
  Provides assigns consumed by the organization framework layout.

  Organization LiveViews assign `nav_org` after mounting. This hook supplies
  the shared URL, header-action, and breadcrumb assigns independently from the
  dashboard layout defaults.
  """

  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(_arg, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> assign(:current_query, nil)
      |> assign_new(:nav_org, fn -> nil end)
      |> assign_new(:page_action, fn -> nil end)
      |> assign_new(:breadcrumbs, fn -> nil end)
      |> attach_hook(:__organization_current_path__, :handle_params, fn _params, uri, socket ->
        parsed = URI.parse(uri)

        {:cont,
         socket
         |> assign(:current_path, parsed.path)
         |> assign(:current_query, parsed.query)}
      end)

    {:cont, socket}
  end
end
