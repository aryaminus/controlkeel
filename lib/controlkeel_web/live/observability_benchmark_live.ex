defmodule ControlKeelWeb.ObservabilityBenchmarkLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    drafts = Observability.benchmark_drafts(opts)
    scenarios = Observability.observability_benchmark_scenarios(opts)
    run_preview = Observability.observability_benchmark_run_preview(opts)
    history = Observability.observability_benchmark_history(opts)

    {:ok,
     socket
     |> assign(:page_title, "Benchmark")
     |> assign(:opts, opts)
     |> assign(:drafts, drafts)
     |> assign(:scenarios, scenarios)
     |> assign(:run_preview, run_preview)
     |> assign(:history, history)}
  end

  # Currently approve/reject/archive are fully reversible, so devs and users can
  # test the actions back and forth.
  #
  # Consider making approve and reject irreversible decision states: an approved
  # draft could stop being rejectable, archivable, or approvable again, with the
  # same holding for rejected drafts. Archive would stay reversible (archived
  # drafts could be re-opened). If pursued, enforce the transition matrix in
  # Observability.update_benchmark_draft_status/3 and disable the buttons here
  # accordingly.
  @impl true
  def handle_event("approve-draft", %{"id" => id}, socket) do
    opts = Keyword.merge(socket.assigns.opts, reviewed_by: "web")

    case Observability.update_benchmark_draft_status(id, "approved", opts) do
      {:ok, _result} ->
        materialize = Observability.materialize_benchmark_drafts(socket.assigns.opts)

        {:noreply,
         socket
         |> assign(:drafts, Observability.benchmark_drafts(socket.assigns.opts))
         |> put_flash(:info, approve_materialize_message(materialize))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, flash_for_status_error(reason))}
    end
  end

  def handle_event("reject-draft", %{"id" => id}, socket) do
    opts = Keyword.merge(socket.assigns.opts, reviewed_by: "web")

    case Observability.update_benchmark_draft_status(id, "rejected", opts) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:drafts, Observability.benchmark_drafts(socket.assigns.opts))
         |> put_flash(:info, status_flash_message(result))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, flash_for_status_error(reason))}
    end
  end

  def handle_event("archive-draft", %{"id" => id}, socket) do
    opts = Keyword.merge(socket.assigns.opts, reviewed_by: "web")

    case Observability.update_benchmark_draft_status(id, "archived", opts) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:drafts, Observability.benchmark_drafts(socket.assigns.opts))
         |> put_flash(:info, status_flash_message(result))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, flash_for_status_error(reason))}
    end
  end

  def handle_event("generate-drafts", _params, socket) do
    result = Observability.generate_benchmark_drafts(socket.assigns.opts)

    {:noreply,
     socket
     |> assign(:drafts, Observability.benchmark_drafts(socket.assigns.opts))
     |> put_flash(:info, generate_drafts_message(result))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-benchmark-page" class="w-full space-y-6">
      <div id="benchmarks-drafts" class="scroll-mt-6">
        <section id="observability-benchmark-drafts-page" class="w-full space-y-5">
          <div class="flex items-start justify-between gap-4 flex-wrap">
            <div class="space-y-2">
              <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
                Benchmark drafts
              </h1>
              <p class="text-sm text-muted-foreground">
                Human-gated local benchmark draft scenarios generated from saved eval candidates.
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
              <span id="observability-benchmark-drafts-count" class={neutral_pill_class()}>
                {@drafts.count} draft(s)
              </span>
              <.button
                id="observability-benchmark-drafts-generate"
                type="button"
                variant="outline"
                phx-click="generate-drafts"
              >
                Generate drafts
              </.button>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <CommandPill.command_pill command="controlkeel obs benchmarks drafts" />
          </div>

          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <article
              id="observability-benchmark-drafts-status"
              class="rounded-2xl border bg-card p-5 shadow-card"
            >
              <p class="text-sm font-medium text-muted-foreground">Status</p>
              <p class="mt-2 text-lg font-semibold text-foreground/90">
                {format_frequency(@drafts.by_status)}
              </p>
            </article>
            <article
              id="observability-benchmark-drafts-suites"
              class="rounded-2xl border bg-card p-5 shadow-card"
            >
              <p class="text-sm font-medium text-muted-foreground">Suites</p>
              <p class="mt-2 text-lg font-semibold text-foreground/90">
                {format_frequency(@drafts.by_suite)}
              </p>
            </article>
          </div>

          <%= if @drafts.recommendations != [] do %>
            <section
              id="observability-benchmark-drafts-recommendations"
              class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
            >
              <.section_title>Recommendations</.section_title>
              <%= for recommendation <- @drafts.recommendations do %>
                <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
              <% end %>
            </section>
          <% end %>

          <section
            id="observability-benchmark-drafts-list"
            class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
          >
            <.section_title>Draft scenarios</.section_title>
            <%= if @drafts.drafts == [] do %>
              <p class="text-sm text-muted-foreground">No benchmark drafts yet.</p>
            <% else %>
              <div class="divide-y divide-border">
                <%= for draft <- @drafts.drafts do %>
                  <div
                    id={"observability-benchmark-draft-#{draft.id}"}
                    class="space-y-2 py-3 first:pt-0 last:pb-0"
                  >
                    <div class="flex items-center justify-between gap-4">
                      <div class="min-w-0 space-y-1">
                        <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                          {draft.suite_slug}
                        </p>
                        <p class="text-sm font-medium text-foreground">{draft.title}</p>
                      </div>
                      <span class={status_pill_class(draft.status)}>{draft.status}</span>
                    </div>
                    <p class="text-sm leading-relaxed text-foreground">{draft.scenario_prompt}</p>
                    <p class="text-xs text-muted-foreground">
                      Expected: {draft.expected_behavior}
                    </p>
                    <p class="text-xs text-muted-foreground">
                      Human gate required: {draft.human_gate_required}
                    </p>
                    <p class="text-xs text-muted-foreground">
                      Scenario: {materialized_scenario(draft)}
                    </p>
                    <div class="flex items-center gap-3 pt-1">
                      <.button
                        id={"observability-benchmark-draft-approve-#{draft.id}"}
                        type="button"
                        phx-click="approve-draft"
                        phx-value-id={draft.id}
                        disabled={draft.status == "approved"}
                      >
                        Approve
                      </.button>
                      <.button
                        id={"observability-benchmark-draft-reject-#{draft.id}"}
                        type="button"
                        variant="outline"
                        phx-click="reject-draft"
                        phx-value-id={draft.id}
                        disabled={draft.status == "rejected"}
                      >
                        Reject
                      </.button>
                      <%= if draft.status != "archived" do %>
                        <.button
                          id={"observability-benchmark-draft-archive-#{draft.id}"}
                          type="button"
                          variant="outline"
                          phx-click="archive-draft"
                          phx-value-id={draft.id}
                        >
                          Archive
                        </.button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>
        </section>
      </div>

      <div id="benchmarks-scenarios" class="scroll-mt-6">
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
      </div>

      <div id="benchmarks-history" class="scroll-mt-6">
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
      </div>
    </section>
    """
  end

  defp status_pill_class("approved"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp status_pill_class("rejected"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp status_pill_class("failed"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp status_pill_class("archived"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground/60 ring-border"

  defp status_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground ring-border"

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp approve_materialize_message(%{materialized: materialized, existing: existing}) do
    count_part = "Approved and materialized #{materialized} draft(s)"
    existing_part = if existing > 0, do: " · #{existing} already existed", else: ""
    count_part <> existing_part <> "."
  end

  defp status_flash_message(%{status: status, draft: draft}) do
    "#{String.capitalize(status)} draft \"#{draft.title}\"."
  end

  defp generate_drafts_message(%{source_count: 0}) do
    "No open saved eval candidates to generate draft scenarios from."
  end

  defp generate_drafts_message(%{stored: stored, existing: existing}) do
    count_part = "Generated #{stored} draft(s)"
    existing_part = if existing > 0, do: " · #{existing} already existed", else: ""
    count_part <> existing_part <> "."
  end

  defp materialized_scenario(draft) do
    case get_in(draft.metadata || %{}, ["materialized_scenario_id"]) do
      id when is_integer(id) -> "##{id}"
      _ -> "not materialized"
    end
  end

  defp flash_for_status_error(:forbidden),
    do: "You can only review drafts from the current workspace."

  defp flash_for_status_error(:not_found), do: "Benchmark draft was not found."
  defp flash_for_status_error(:invalid_id), do: "The provided draft id was invalid."
  defp flash_for_status_error(_reason), do: "Unable to update benchmark draft status."

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
