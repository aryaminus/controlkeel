defmodule ControlKeelWeb.ObservabilityBenchmarkHistoryLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session =
      Mission.list_recent_sessions_for_user(socket.assigns[:current_user], 1) |> List.first()

    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    history = Observability.observability_benchmark_history(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark History")
     |> assign(:history, history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-benchmark-history-page" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Benchmark history
          </h1>
          <p class="text-sm text-muted-foreground">
            Read-only readiness and run evidence for generated observability benchmark scenarios.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span
            id="observability-benchmark-history-readiness"
            class={health_pill_class(@history.readiness.status)}
          >
            {@history.readiness.status}
          </span>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs benchmarks history" />
      </div>

      <section
        id="observability-benchmark-history-summary"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <div class="space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Readiness</p>
          <p class="text-base font-semibold text-foreground/90">{@history.readiness.reason}</p>
        </div>
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
          <div class="rounded-xl border bg-muted/40 p-4 space-y-1">
            <p class="text-xs text-muted-foreground">Saved evals</p>
            <p class="text-xl font-semibold text-foreground/90">
              {@history.coverage.saved_eval_candidates}
            </p>
          </div>
          <div class="rounded-xl border bg-muted/40 p-4 space-y-1">
            <p class="text-xs text-muted-foreground">Drafts</p>
            <p class="text-xl font-semibold text-foreground/90">
              {@history.coverage.benchmark_drafts}
            </p>
          </div>
          <div class="rounded-xl border bg-muted/40 p-4 space-y-1">
            <p class="text-xs text-muted-foreground">Materialized</p>
            <p class="text-xl font-semibold text-foreground/90">
              {@history.coverage.materialized_scenarios}
            </p>
          </div>
          <div class="rounded-xl border bg-muted/40 p-4 space-y-1">
            <p class="text-xs text-muted-foreground">Covered</p>
            <p class="text-xl font-semibold text-foreground/90">
              {@history.coverage.covered_scenarios}
            </p>
          </div>
        </div>
      </section>

      <%= if @history.recommendations != [] do %>
        <section
          id="observability-benchmark-history-recommendations"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
        >
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @history.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section
        id="observability-benchmark-history-runs"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <.section_title>Recent generated-suite runs</.section_title>
        <%= if @history.runs == [] do %>
          <p class="text-sm text-muted-foreground">No observability benchmark runs yet.</p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for run <- @history.runs do %>
              <div
                id={"observability-benchmark-history-run-#{run.id}"}
                class="space-y-1 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {run.suite}
                    </p>
                    <p class="text-sm font-medium text-foreground">
                      Run #{run.id}: {run.status}
                    </p>
                  </div>
                  <span class={status_pill_class(run.status)}>{run.status}</span>
                </div>
                <p class="text-xs text-muted-foreground">
                  catch {run.catch_rate}% · rule-hit {run.expected_rule_hit_rate}%
                </p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp status_pill_class("failed"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp status_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground ring-border"
end
