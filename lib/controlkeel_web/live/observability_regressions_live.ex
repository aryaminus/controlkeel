defmodule ControlKeelWeb.ObservabilityRegressionsLive do
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
    regressions = Observability.regressions(opts)

    {:ok,
     socket
     |> assign(:page_title, "Regression Tracking")
     |> assign(:regressions, regressions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-regressions" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Regression tracking
          </h1>
          <p class="text-sm text-muted-foreground">
            Read-only benchmark run posture connected to saved eval candidates and benchmark drafts.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span class={health_pill_class(@regressions.health.status)}>
            {@regressions.health.status}
          </span>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs regressions" />
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <section
          id="observability-regressions-runs"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-1"
        >
          <p class="text-sm font-medium text-muted-foreground">Benchmark runs</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {@regressions.benchmark_runs.count}
          </p>
          <p class="text-xs text-muted-foreground">Window: {@regressions.days} day(s)</p>
        </section>
        <section
          id="observability-regressions-catch-rate"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-1"
        >
          <p class="text-sm font-medium text-muted-foreground">Average catch rate</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {format_rate(@regressions.benchmark_runs.average_catch_rate)}
          </p>
          <p class="text-xs text-muted-foreground">
            {format_frequency(@regressions.benchmark_runs.by_status)}
          </p>
        </section>
        <section
          id="observability-regressions-draft-coverage"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-1"
        >
          <p class="text-sm font-medium text-muted-foreground">Draft coverage</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {@regressions.draft_coverage.benchmark_drafts} draft(s)
          </p>
          <p class="text-xs text-muted-foreground">
            {@regressions.draft_coverage.saved_eval_candidates} saved eval(s)
          </p>
        </section>
      </div>

      <%= if @regressions.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @regressions.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Recent benchmark runs</.section_title>
        <%= if @regressions.benchmark_runs.recent == [] do %>
          <p class="text-sm text-muted-foreground">
            No benchmark runs in the selected window.
          </p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for run <- @regressions.benchmark_runs.recent do %>
              <div
                id={"observability-regression-run-#{run.id}"}
                class="space-y-2 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {run.suite}
                    </p>
                    <p class="text-sm font-medium text-foreground">Run #{run.id}</p>
                  </div>
                  <span class={health_pill_class(run.status)}>{run.status}</span>
                </div>
                <p class="text-xs text-muted-foreground">
                  Catch rate {format_rate(run.catch_rate)} · {run.caught_count}/{run.total_scenarios} scenario(s) · {run.result_count} result(s)
                </p>
                <div class="flex items-center gap-4 text-xs">
                  <p class="text-muted-foreground">
                    {format_datetime(run.inserted_at, "unknown")}
                  </p>
                  <.link
                    navigate={~p"/benchmarks/runs/#{run.id}"}
                    class="text-sm font-medium text-primary transition hover:text-primary"
                  >
                    Open run →
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) do
    map
    |> Enum.sort_by(fn {key, _count} -> key end)
    |> Enum.map_join(", ", fn {key, count} -> "#{key}: #{count}" end)
  end

  defp format_rate(nil), do: "0.0%"
  defp format_rate(rate), do: "#{Float.round(rate * 100, 1)}%"

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_status),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"
end
