defmodule ControlKeelWeb.RecentSessions do
  use Phoenix.Component

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
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <%= for run <- @runs do %>
            <.link
              navigate={~p"/observability/sessions/#{run.id}"}
              class="group rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:bg-muted/30"
            >
              <div class="flex items-start justify-between gap-3">
                <p class="min-w-0 flex-1 truncate text-sm font-medium text-foreground">
                  <span class="group-hover:underline">{run.title}</span>
                </p>
                <span class={health_pill_class(run.health)}>{run.health}</span>
              </div>
              <dl class="mt-4 grid grid-cols-4 gap-3 border-t border-border pt-3 text-xs">
                <div>
                  <dt class="text-muted-foreground">Findings</dt>
                  <dd class="mt-0.5 font-medium text-foreground">
                    {run.active_findings} active
                    <span :if={run.blocked_findings > 0}>
                      · {run.blocked_findings} blocked
                    </span>
                  </dd>
                </div>
                <div>
                  <dt class="text-muted-foreground">Proofs</dt>
                  <dd class="mt-0.5 font-medium text-foreground">
                    <%= if (Map.get(run, :proof_bundles) || 0) > 0 do %>
                      {run.proof_bundles} bundles
                    <% else %>
                      <span class="font-normal text-muted-foreground">No proofs yet</span>
                    <% end %>
                  </dd>
                </div>
                <div>
                  <dt class="text-muted-foreground">Budget</dt>
                  <dd class="mt-0.5 font-medium text-foreground">
                    {format_currency(run.budget_spent_cents)} / {format_currency(
                      run.budget_limit_cents
                    )}
                  </dd>
                </div>
                <div>
                  <dt class="text-muted-foreground">Memory</dt>
                  <dd class="mt-0.5 font-medium text-foreground">{run.memory_records} records</dd>
                </div>
              </dl>
            </.link>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp health_pill_class("red") do
    "inline-flex items-center rounded-full px-2 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"
  end

  defp health_pill_class("yellow") do
    "inline-flex items-center rounded-full px-2 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"
  end

  defp health_pill_class(_) do
    "inline-flex items-center rounded-full px-2 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
