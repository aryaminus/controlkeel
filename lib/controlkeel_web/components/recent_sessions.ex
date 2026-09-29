defmodule ControlKeelWeb.RecentSessions do
  use Phoenix.Component

  import ControlKeelWeb.ObservabilityHelpers
  import ControlKeelWeb.Typography

  use Phoenix.VerifiedRoutes,
    endpoint: ControlKeelWeb.Endpoint,
    router: ControlKeelWeb.Router,
    statics: ControlKeelWeb.static_paths()

  attr :runs, :list, required: true

  def session_observability_section(assigns) do
    ~H"""
    <section id="observability-overview-run-list" class="space-y-4">
      <.section_title>Recent session runs</.section_title>

      <%= if @runs == [] do %>
        <p class="text-sm text-muted-foreground">No sessions available yet.</p>
      <% else %>
        <div class="bg-card border rounded-2xl shadow-card overflow-x-auto">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
              <tr>
                <th class="px-5 py-3 font-semibold">Session</th>
                <th class="px-5 py-3 font-semibold">Health</th>
                <th class="px-5 py-3 font-semibold">Findings</th>
                <th class="px-5 py-3 font-semibold">Proofs</th>
                <th class="px-5 py-3 font-semibold">Budget</th>
                <th class="px-5 py-3 font-semibold">Memory</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= for run <- @runs do %>
                <tr class="transition hover:bg-muted/30">
                  <td class="px-5 py-4">
                    <.link
                      navigate={
                        if run[:org_slug] && run[:workspace_slug],
                          do:
                            ~p"/#{run.org_slug}/workspaces/#{run.workspace_slug}/sessions/#{run.id}/observability",
                          else: ~p"/observability/sessions/#{run.id}"
                      }
                      class="font-medium text-foreground underline-offset-4 transition hover:text-primary hover:underline"
                    >
                      {run.title}
                    </.link>
                  </td>
                  <td class="px-5 py-4 whitespace-nowrap">
                    <span class={health_pill_class(run.health, :sm)}>{run.health}</span>
                  </td>
                  <td class="px-5 py-4 whitespace-nowrap text-foreground">
                    {run.active_findings} active
                    <span :if={run.blocked_findings > 0}>
                      · {run.blocked_findings} blocked
                    </span>
                  </td>
                  <td class="px-5 py-4 whitespace-nowrap text-foreground">
                    <%= if (Map.get(run, :proof_bundles) || 0) > 0 do %>
                      {run.proof_bundles} bundles
                    <% else %>
                      <span class="font-normal text-muted-foreground">No proofs yet</span>
                    <% end %>
                  </td>
                  <td class="px-5 py-4 whitespace-nowrap text-foreground">
                    {format_currency(run.budget_spent_cents)} / {format_currency(
                      run.budget_limit_cents
                    )}
                  </td>
                  <td class="px-5 py-4 whitespace-nowrap text-foreground">
                    {run.memory_records} records
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end
end
