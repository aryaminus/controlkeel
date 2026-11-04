defmodule ControlKeelWeb.WorkspaceSessionsLive do
  @moduledoc """
  Workspace session index at `/:org_slug/workspace/:ws_slug/sessions`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Sessions") do
      {:ok, socket} ->
        workspace = socket.assigns.workspace

        {:ok,
         socket
         |> assign(:page_title, "Sessions — #{workspace.name}")
         |> assign(:sessions, Mission.list_all_sessions(workspace.id))}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
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
          All sessions in {@workspace.name}.
        </p>
      </div>

      <%= if @sessions == [] do %>
        <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
          <.icon name="hero-play-circle" class="mx-auto size-10 text-muted-foreground" />
          <p class="mt-4 text-base font-medium text-foreground">No sessions yet.</p>
          <p class="mt-1 text-sm text-muted-foreground">
            Sessions launched under this workspace will appear here.
          </p>
        </section>
      <% else %>
        <div class="overflow-hidden rounded-2xl border bg-card shadow-card">
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="border-b bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th class="px-5 py-3 font-medium">Session</th>
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
                          ~p"/#{@workspace.org.slug}/workspace/#{@workspace.slug}/sessions/#{session.id}"
                        }
                        class="font-medium text-foreground hover:text-primary hover:underline"
                      >
                        {session.title}
                      </.link>
                      <p class="mt-1 max-w-xl truncate text-xs text-muted-foreground">
                        {session.objective}
                      </p>
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
end
