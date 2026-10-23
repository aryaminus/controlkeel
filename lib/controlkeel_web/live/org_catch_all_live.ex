defmodule ControlKeelWeb.OrgCatchAllLive do
  @moduledoc """
  Catch-all for unmatched URLs inside an org scope.

  Mounted as the last route in the `:organization` live_session at
  `/:org_slug/*rest`. If the org resolves, renders the org sidebar with
  a "Can't find the page" panel in the content area. If the org itself
  is invalid, falls through to the standard full-page org-not-found panel.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeelWeb.OrgAccess
  alias ControlKeelWeb.ScopeError

  @impl true
  def mount(%{"org_slug" => slug, "rest" => rest}, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, _membership} ->
        error = ScopeError.url(slug, rest)

        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)
         |> assign(:nav_org, org)
         |> assign(:breadcrumbs, [
           %{label: org.name, to: "/#{org.slug}"}
         ])}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  @impl true
  def render(assigns), do: ~H""
end
