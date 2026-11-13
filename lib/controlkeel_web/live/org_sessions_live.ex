defmodule ControlKeelWeb.OrgSessionsLive do
  @moduledoc """
  Organization sessions index at `/:org_slug/sessions`.

  Every session across the organization's workspaces, newest first, with
  its owning workspace. Sessions are workspace-scoped tenants, so each
  row links into the standard nested route
  (`/:org_slug/workspaces/:ws_slug/sessions/:id`).

  Any active member (viewer+) may view — the same floor as the org
  overview. Access resolves per-URL via
  `ControlKeelWeb.OrgAccess.resolve/3`; an inaccessible org renders the
  shared in-place not-found panel.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.OrgAccess

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        mount_ok(socket, org, membership)

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  defp mount_ok(socket, org, membership) do
    {:ok,
     socket
     |> assign(:page_title, "Sessions — #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:current_membership, membership)
     |> assign(:sessions, Mission.list_sessions_for_org(org.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = maybe_refresh_org(socket, params["org_slug"])
    {:noreply, socket}
  end

  defp maybe_refresh_org(%{assigns: %{org: %{slug: slug}}} = socket, slug), do: socket

  defp maybe_refresh_org(socket, slug) when is_binary(slug) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        {:ok, socket} = mount_ok(socket, org, membership)
        assign(socket, :scope_error, nil)

      {:error, error} ->
        assign(socket, :scope_error, error)
    end
  end

  defp maybe_refresh_org(socket, _slug), do: socket

  # An unresolved org scope renders the shared not-found panel from the org
  # layout (see `ControlKeelWeb.OrgAccess`); this page body stays empty. The
  # assign is always present (defaulted to nil by the layout hook), so the
  # clause must match only a real error map.
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
          Sessions
        </h1>
        <p class="text-sm text-muted-foreground">
          Every session across {@org.name}'s workspaces, newest first.
        </p>
      </div>

      <div class="overflow-hidden rounded-2xl border bg-card shadow-card">
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
            <tr>
              <th class="px-5 py-3 font-semibold">Session</th>
              <th class="px-5 py-3 font-semibold">Workspace</th>
              <th class="px-5 py-3 font-semibold">Status</th>
              <th class="px-5 py-3 font-semibold">Created</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= if @sessions == [] do %>
              <tr>
                <td colspan="4" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No sessions yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Start a session from any workspace to see it here.
                  </p>
                </td>
              </tr>
            <% else %>
              <%= for s <- @sessions do %>
                <tr class="transition hover:bg-muted/50">
                  <td class="px-5 py-3">
                    <.link
                      navigate={~p"/#{@org.slug}/workspaces/#{s.workspace.slug}/sessions/#{s.id}"}
                      class="font-medium text-foreground hover:text-primary"
                    >
                      {s.title || "Session ##{s.id}"}
                    </.link>
                  </td>
                  <td class="px-5 py-3 text-muted-foreground">{s.workspace.name}</td>
                  <td class="px-5 py-3">
                    <span class={[
                      "inline-flex rounded-full px-2.5 py-0.5 text-xs font-semibold capitalize ring-1",
                      s.status == "active" && "bg-success/10 text-success ring-success/20",
                      s.status != "active" && "bg-muted text-muted-foreground ring-border"
                    ]}>
                      {s.status}
                    </span>
                  </td>
                  <td class="px-5 py-3 text-muted-foreground">
                    {Calendar.strftime(s.inserted_at, "%b %d, %Y")}
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </section>
    """
  end
end
