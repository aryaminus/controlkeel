defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.RecentSessions
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Observability") do
      {:ok, socket} ->
        {:ok, socket |> assign(:page_title, "Observability") |> load_page(params)}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    WorkspaceScope.on_params(socket, params, &load_page/2)
  end

  defp load_page(socket, _params) do
    overview =
      Observability.workspace_overview(limit: 6, workspace_id: socket.assigns.workspace.id)

    assign(socket, :overview, overview)
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <section id="observability-overview-page" class="w-full space-y-5">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
          Observability
        </h1>
        <p class="text-sm text-muted-foreground">
          Session runs, problems, costs, and trace export at a glance.
        </p>
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <article
          id="observability-overview-runs"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Runs</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@overview.runs.count} recent
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.health.red_runs} red · {@overview.health.yellow_runs} yellow · {@overview.health.green_runs} green
          </p>
        </article>

        <article
          id="observability-overview-problems"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Findings</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@overview.problems.count} groups
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.problems.total_findings} active finding(s)
          </p>
        </article>

        <article
          id="observability-overview-costs"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Costs</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_currency(@overview.costs.spent_cents)} / {format_currency(
              @overview.costs.budget_cents
            )}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.costs.invocations} invocation(s), {format_currency(
              @overview.costs.estimated_invocation_cents
            )} estimated
          </p>
          <.link
            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/observability/costs"}
            class="mt-3 inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
          >
            Review costs <.icon name="hero-arrow-up-right" class="size-3" />
          </.link>
        </article>

        <article
          id="observability-overview-telemetry"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Trace export</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@overview.telemetry.import_mode}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.telemetry.export_schema_version} · {@overview.telemetry.integrity}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.telemetry.persisted_imports} persisted import(s)
          </p>
          <.link
            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/observability/imports"}
            class="mt-3 inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
          >
            Review imports <.icon name="hero-arrow-up-right" class="size-3" />
          </.link>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Recommended next actions</.section_title>
        <%= if @overview.recommendations == [] do %>
          <p class="text-sm text-muted-foreground">No recommendations available.</p>
        <% else %>
          <ul class="space-y-2 text-sm text-muted-foreground list-disc ml-5">
            <%= for recommendation <- @overview.recommendations do %>
              <li class="leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        <% end %>
        <.link
          navigate={
            ~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/observability/recommendations"
          }
          class="inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
        >
          Open recommendations <.icon name="hero-arrow-up-right" class="size-3" />
        </.link>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <div class="flex items-start justify-between gap-3">
          <div class="space-y-1">
            <.section_title>Top findings</.section_title>
            <p class="text-xs text-muted-foreground">
              Recurring patterns across sessions — open a session to inspect its individual findings.
            </p>
          </div>
          <span class="shrink-0 rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
            {@overview.problems.count} group(s)
          </span>
        </div>
        <%= if @overview.problems.top == [] do %>
          <p class="text-sm text-muted-foreground">No active problems detected.</p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for problem <- @overview.problems.top do %>
              <div class="py-3 first:pt-0 last:pb-0">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-foreground">{problem.title}</p>
                    <p class="mt-0.5 font-mono text-xs text-muted-foreground">
                      {problem.rule_id}
                    </p>
                  </div>
                  <p class="shrink-0 text-xs text-muted-foreground">
                    {problem.health} · {problem.count} finding(s) · {problem.affected_session_count} session(s)
                  </p>
                </div>
                <%= for example <- problem.examples |> List.first() |> List.wrap() do %>
                  <.link
                    navigate={
                      ~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/sessions/#{example.session_id}/findings"
                    }
                    class="mt-1 inline-flex items-center gap-2 text-xs font-medium text-primary transition hover:text-primary"
                  >
                    Inspect findings in this session
                    <.icon name="hero-arrow-up-right" class="size-3" />
                  </.link>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <RecentSessions.session_observability_section
        runs={@overview.runs.recent}
        org_slug={@workspace.org.slug}
        ws_slug={@workspace.slug}
      />
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
