defmodule ControlKeelWeb.OrgCatchAllLive do
  @moduledoc """
  Catch-all for unmatched URLs inside an org scope.

  Mounted as the last route in the `:organization` live_session at
  `/:org_slug/*rest`. Resolves the deepest valid URL scope before rendering
  the "Can't find the page" panel. Invalid or inaccessible scopes do not
  disclose whether the requested resource exists.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeelWeb.OrgAccess
  alias ControlKeelWeb.ScopeError
  alias ControlKeelWeb.SessionScope
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(%{"org_slug" => slug, "rest" => rest}, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, _membership} ->
        socket =
          socket
          |> assign(:nav_org, org)
          |> assign(:breadcrumbs, [%{label: org.name, to: "/#{org.slug}"}])

        {:ok, resolve_deeper_scope(socket, slug, rest)}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  @impl true
  def render(assigns), do: ~H""

  defp resolve_deeper_scope(socket, slug, ["workspaces", ws_slug | rest] = path) do
    params = %{"org_slug" => slug, "ws_slug" => ws_slug}

    case WorkspaceScope.assign_scope(socket, params, nil) do
      {:ok, socket} ->
        resolve_session_scope(socket, slug, ws_slug, rest, path)

      {:error, socket} ->
        assign_error_title(socket)
    end
  end

  defp resolve_deeper_scope(socket, slug, rest),
    do: assign_url_error(socket, slug, rest)

  defp resolve_session_scope(socket, slug, ws_slug, ["sessions", id | _], path) do
    case SessionScope.fetch_session(id) do
      session when not is_nil(session) ->
        if Accounts.session_accessible?(session, socket.assigns[:current_user]) and
             SessionScope.check_scope(session, slug, ws_slug) == :ok do
          workspace = session.workspace
          org = workspace.org

          socket
          |> assign(:nav_org, org)
          |> assign(:nav_workspace, workspace)
          |> assign(:nav_session, %{id: session.id, title: session.title})
          |> assign(:breadcrumbs, [
            %{label: org.name, to: "/#{org.slug}"},
            %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
            %{label: session.title, to: nil}
          ])
          |> assign_url_error(slug, path)
        else
          assign_url_error(socket, slug, path)
        end

      nil ->
        assign_url_error(socket, slug, path)
    end
  end

  defp resolve_session_scope(socket, slug, _ws_slug, _rest, path),
    do: assign_url_error(socket, slug, path)

  defp assign_url_error(socket, slug, path) do
    error = ScopeError.url(slug, path)

    socket
    |> assign(:page_title, error.title)
    |> assign(:scope_error, error)
  end

  defp assign_error_title(socket) do
    error = socket.assigns.scope_error
    assign(socket, :page_title, error.title)
  end
end
