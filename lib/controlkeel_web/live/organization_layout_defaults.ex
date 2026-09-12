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

  alias ControlKeel.Accounts

  def on_mount(_arg, params, _session, socket) do
    socket =
      socket
      |> assign_url_org(params)
      |> assign(:current_path, nil)
      |> assign(:current_query, nil)
      |> assign_new(:nav_org, fn -> nil end)
      |> assign_new(:nav_workspace, fn -> nil end)
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

  # URL is the source of truth for org context on `/:org_slug/...` routes.
  # Runs after `LiveAuth` (see router order), so `current_user` is already
  # loaded. Overrides the legacy `nil` session-derived assigns so workspace
  # LiveViews matching on `%{current_org_id: org_id}` keep working untouched.
  defp assign_url_org(socket, %{"org_slug" => slug}) when is_binary(slug) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        socket

      org ->
        membership =
          case socket.assigns[:current_user] do
            %{id: user_id} -> Accounts.get_active_membership(user_id, org.id)
            _ -> nil
          end

        socket
        |> assign(:current_org_id, org.id)
        |> assign(:current_membership, membership)
    end
  end

  defp assign_url_org(socket, _params), do: socket
end
