defmodule ControlKeelWeb.MissionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> assign(
       :page_action,
       %{label: "New Session", to: ~p"/sessions/start", icon: "hero-plus"}
     )
     |> assign(
       :recent_sessions,
       Mission.list_all_sessions_for_user(socket.assigns[:current_user])
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full">
      <div class="bg-card border rounded-2xl shadow-card overflow-clip">
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="px-5 py-3 font-semibold">Session</th>
              <th class="px-5 py-3 font-semibold">Risk</th>
              <th class="px-5 py-3 font-semibold">Workload</th>
              <th class="px-5 py-3 font-semibold">Findings</th>
              <th class="px-5 py-3 font-semibold">Budget</th>
              <th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= if @recent_sessions == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No sessions yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Start a session to populate live governance telemetry.
                  </p>
                </td>
              </tr>
            <% else %>
              <%= for session <- @recent_sessions do %>
                <tr class="transition hover:bg-muted/30">
                  <td class="max-w-sm px-5 py-4">
                    <p class="font-medium text-foreground">{session.title}</p>
                    <p class="mt-1 line-clamp-1 text-xs text-muted-foreground">
                      {session.objective}
                    </p>
                    <p class="mt-2 text-xs text-muted-foreground">
                      {session.workspace && session.workspace.name}
                    </p>
                  </td>
                  <td class="px-5 py-4">
                    <span class={[
                      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                      session.risk_tier in ["critical", "high"] &&
                        "bg-destructive/10 text-destructive ring-destructive/20",
                      session.risk_tier in ["medium", "moderate"] &&
                        "bg-warning/10 text-warning ring-warning/20",
                      session.risk_tier in ["low"] &&
                        "bg-success/10 text-success ring-success/20",
                      session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                        "bg-muted text-muted-foreground ring-border"
                    ]}>
                      {session.risk_tier}
                    </span>
                  </td>
                  <td class="px-5 py-4">
                    <div class="flex items-center gap-2 text-muted-foreground">
                      <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                      {Enum.count(session.tasks)} tasks
                    </div>
                  </td>
                  <td class="px-5 py-4">
                    <div class="flex items-center gap-2 text-muted-foreground">
                      <.icon name="hero-exclamation-circle" class="size-4 text-muted-foreground" />
                      {Enum.count(session.findings)}
                    </div>
                  </td>
                  <td class="px-5 py-4 text-muted-foreground">
                    ${session.budget_cents |> Kernel./(100) |> trunc()}
                  </td>
                  <td class="px-4 text-right whitespace-nowrap w-px">
                    <.link
                      navigate={session_path(session)}
                      class="inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs font-semibold text-muted-foreground transition hover:border-primary/40 hover:bg-primary/10 hover:text-foreground"
                    >
                      Inspect <.icon name="hero-arrow-right" class="size-3" />
                    </.link>
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

  # Direct org-scoped link. Unbound rows (no org — see the nesting invariant
  # in LegacyController) keep the legacy path so the local-default fallback
  # or 404 chain handles them instead of crashing the index.
  defp session_path(%{id: id, workspace: %{org: %{slug: org_slug}, slug: ws_slug}}),
    do: "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}"

  defp session_path(%{id: id}), do: "/sessions/#{id}"
end
