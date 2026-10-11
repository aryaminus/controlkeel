defmodule ControlKeelWeb.ObservabilityBenchmarkScenariosLive do
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
    scenarios = Observability.observability_benchmark_scenarios(opts)
    run_preview = Observability.observability_benchmark_run_preview(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark Scenarios")
     |> assign(:scenarios, scenarios)
     |> assign(:run_preview, run_preview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-benchmark-scenarios-page" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Materialized benchmark scenarios
          </h1>
          <p class="text-sm text-muted-foreground">
            Local Benchmark.Scenario records generated from approved observability drafts.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-benchmark-scenarios-count" class={neutral_pill_class()}>
            {@scenarios.count} scenario(s)
          </span>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs benchmarks scenarios" />
      </div>

      <%= if @scenarios.recommendations != [] do %>
        <section
          id="observability-benchmark-scenarios-summary"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
        >
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @scenarios.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section
        id="observability-benchmark-run-guidance"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <.section_title>Human-gated execution</.section_title>
        <p class="text-sm leading-relaxed text-muted-foreground">
          Benchmark execution is CLI-only. Review generated scenarios first, then run an explicit command.
        </p>
        <code class="block rounded-lg border bg-muted px-3 py-2 text-xs text-muted-foreground overflow-x-auto">
          {@run_preview.command || "controlkeel obs benchmarks run --dry-run"}
        </code>
        <%= if @run_preview.recommendations != [] do %>
          <div class="space-y-2">
            <%= for recommendation <- @run_preview.recommendations do %>
              <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
            <% end %>
          </div>
        <% end %>
      </section>

      <section
        id="observability-benchmark-scenarios-list"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <.section_title>Scenarios</.section_title>
        <%= if @scenarios.scenarios == [] do %>
          <p class="text-sm text-muted-foreground">
            No materialized observability scenarios yet.
          </p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for scenario <- @scenarios.scenarios do %>
              <div
                id={"observability-benchmark-scenario-#{scenario.id}"}
                class="space-y-1 py-3 first:pt-0 last:pb-0"
              >
                <p class="text-sm font-medium text-foreground">{scenario.name}</p>
                <p class="text-xs text-muted-foreground">
                  {scenario.suite_slug} · {scenario.slug} · {scenario.split}
                </p>
                <p class="text-xs text-muted-foreground">
                  Expected rules: {Enum.join(scenario.expected_rules, ", ")}
                </p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end
end
