defmodule ControlKeelWeb.OrganizationSessionsLive do
  @moduledoc """
  Organization session index at `/:org_slug/sessions`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.OrgAccess

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        {:ok,
         socket
         |> assign(:page_title, "Sessions — #{org.name}")
         |> assign(:org, org)
         |> assign(:nav_org, org)
         |> assign(:current_membership, membership)
         |> assign(:sessions, load_sessions(org.id))}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  @impl true
  def handle_params(%{"org_slug" => slug}, _uri, socket) do
    socket =
      case socket.assigns[:org] do
        %{slug: ^slug} ->
          socket

        _ ->
          case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
            {:ok, org, membership} ->
              {:ok, socket} =
                {:ok,
                 socket
                 |> assign(:org, org)
                 |> assign(:nav_org, org)
                 |> assign(:current_membership, membership)
                 |> assign(:sessions, load_sessions(org.id))}

              assign(socket, :scope_error, nil)

            {:error, error} ->
              assign(socket, :scope_error, error)
          end
      end

    {:noreply, socket}
  end

  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <div>
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
          Sessions
        </h1>
        <p class="mt-2 text-sm text-muted-foreground">
          Sessions across every workspace in {@org.name}.
        </p>
      </div>

      <%= if @sessions == [] do %>
        <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
          <.icon name="hero-play-circle" class="mx-auto size-10 text-muted-foreground" />
          <p class="mt-4 text-base font-medium text-foreground">No sessions yet.</p>
          <p class="mt-1 text-sm text-muted-foreground">
            Sessions created in this organization’s workspaces will appear here.
          </p>
        </section>
      <% else %>
        <div class="overflow-hidden rounded-2xl border bg-card shadow-card">
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-b bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th class="px-5 py-3 font-medium">Session</th>
                  <th class="px-5 py-3 font-medium">Workspace</th>
                  <th class="px-5 py-3 font-medium">Status</th>
                  <th class="px-5 py-3 font-medium">Tasks</th>
                  <th class="px-5 py-3 font-medium">Findings</th>
                </tr>
              </thead>
              <tbody class="divide-y">
                <%= for session <- @sessions do %>
                  <tr class="transition hover:bg-muted/30">
                    <td class="px-5 py-4">
                      <.link
                        navigate={
                          ~p"/#{@org.slug}/workspace/#{session.workspace.slug}/sessions/#{session.id}"
                        }
                        class="font-medium text-foreground hover:text-primary hover:underline"
                      >
                        {session.title}
                      </.link>
                      <p class="mt-1 max-w-xl truncate text-xs text-muted-foreground">
                        {session.objective}
                      </p>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      {session.workspace.name}
                    </td>
                    <td class="px-5 py-4">
                      <span class="inline-flex rounded-full bg-muted px-2.5 py-1 text-xs font-semibold capitalize ring-1 ring-border">
                        {session.status}
                      </span>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      {length(session.tasks)}
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      {length(session.findings)}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </section>
    """
  end

  defp load_sessions(org_id) do
    workspaces = Mission.list_workspaces_for_org(org_id)
    workspace_ids = Enum.map(workspaces, & &1.id)

    Mission.list_all_sessions_in_workspaces(workspace_ids)
  end
end
