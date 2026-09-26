defmodule ControlKeelWeb.ObservabilityBenchmarkLive do
  @moduledoc """
  Workspace benchmark page at `/:org_slug/workspaces/:ws_slug/benchmark`.

  One stacked page for the workspace's benchmark loop: draft review, approved
  test inventory with the run command, and run history. All data resolves from
  the URL workspace — no recent-session heuristic.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.WorkspaceAccess

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]

      {:ok,
       socket
       |> assign(:page_title, "Benchmark — #{workspace.name}")
       |> assign(:opts, opts)
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/#{workspace.org.slug}/workspaces/#{workspace.slug}"
           },
           %{label: "Benchmark", to: nil}
         ]
       )
       |> assign_benchmark_page()}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  # Single-pass refresh: draft mutations can materialize scenarios and shift
  # history and regression coverage, so every event re-derives all assigns
  # together instead of refreshing :drafts alone.
  defp assign_benchmark_page(socket) do
    opts = socket.assigns.opts
    page = Observability.observability_benchmark_page(opts)

    socket
    |> assign(:drafts, page.drafts)
    |> assign(:scenarios, page.scenarios)
    |> assign(:run_preview, page.run_preview)
    |> assign(:history, page.history)
    |> assign(:regressions, Observability.regressions(opts))
  end

  # Shared section header for the three stacked sections: title + subtitle
  # left, caller-supplied actions (count pills, buttons) right. Keeps every
  # section on one <h2> level under the page <h1>.
  defp benchmark_section_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-4 flex-wrap">
      <div class="space-y-2">
        <.section_title>{@title}</.section_title>
        <p class="text-sm text-muted-foreground">{@subtitle}</p>
      </div>
      <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Shared recommendations card: identical chrome, only the DOM id and items
  # differ. Renders nothing when empty.
  defp benchmark_recommendations(assigns) do
    ~H"""
    <section
      :if={@recommendations != []}
      id={@id}
      class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
    >
      <.section_title>Recommendations</.section_title>
      <%= for recommendation <- @recommendations do %>
        <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
      <% end %>
    </section>
    """
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
         |> assign_benchmark_page()
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
         |> assign_benchmark_page()
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
         |> assign_benchmark_page()
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
     |> assign_benchmark_page()
     |> put_flash(:info, generate_drafts_message(result))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-benchmark-page" class="w-full space-y-6">
      <.page_title
        title="Benchmark"
        subtitle="Draft, review, and run history for locally generated observability benchmarks."
      />
      <section id="benchmarks-drafts" class="w-full space-y-5 scroll-mt-6">
        <.benchmark_section_header
          title="Benchmark drafts"
          subtitle="Human-gated local benchmark draft scenarios generated from saved eval candidates."
        >
          <.button
            id="observability-benchmark-drafts-generate"
            type="button"
            variant="outline"
            phx-click="generate-drafts"
          >
            Generate drafts
          </.button>
        </.benchmark_section_header>

          <div class="flex flex-wrap items-center gap-3">
            <CommandPill.command_pill command="controlkeel obs benchmarks drafts" />
          </div>

        <.benchmark_recommendations
            id="observability-benchmark-drafts-recommendations"
            recommendations={@drafts.recommendations}
          />

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

      <section id="benchmarks-scenarios" class="w-full space-y-5 scroll-mt-6">
        <.benchmark_section_header
          title="Materialized benchmark scenarios"
          subtitle="Local Benchmark.Scenario records generated from approved observability drafts."
        >
          <span id="observability-benchmark-scenarios-count" class={neutral_pill_class()}>
            {@scenarios.count} scenario(s)
          </span>
        </.benchmark_section_header>

          <div class="flex flex-wrap items-center gap-3">
            <CommandPill.command_pill command="controlkeel obs benchmarks scenarios" />
          </div>

          <.benchmark_recommendations
            id="observability-benchmark-scenarios-summary"
            recommendations={@scenarios.recommendations}
          />

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

      <section id="benchmarks-history" class="w-full space-y-5 scroll-mt-6">
        <.benchmark_section_header
          title="Benchmark history"
          subtitle="Read-only readiness and run evidence for generated observability benchmark scenarios."
        >
          <span
            id="observability-benchmark-history-readiness"
            class={health_pill_class(@history.readiness.status)}
          >
            {@history.readiness.status}
          </span>
        </.benchmark_section_header>

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

          <.benchmark_recommendations
            id="observability-benchmark-history-recommendations"
            recommendations={@history.recommendations}
          />

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

      <section id="benchmarks-regressions" class="w-full space-y-5 scroll-mt-6">
        <.benchmark_section_header
          title="Regression tracking"
          subtitle="Read-only benchmark run posture connected to saved eval candidates and benchmark drafts."
        >
          <span class={health_pill_class(@regressions.health.status)}>
            {@regressions.health.status}
          </span>
        </.benchmark_section_header>

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

        <.benchmark_recommendations
          id="observability-regressions-recommendations"
          recommendations={@regressions.recommendations}
        />

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
    </section>
    """
  end

  defp status_pill_class("approved"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp status_pill_class(status) when status in ["rejected", "failed"],
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

  defp format_frequency(map) do
    map
    |> Enum.sort_by(fn {key, _count} -> key end)
    |> Enum.map_join(", ", fn {key, count} -> "#{key}: #{count}" end)
  end

  defp format_rate(nil), do: "0.0%"
  defp format_rate(rate), do: "#{Float.round(rate * 100, 1)}%"

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  # Read + draft-review surface: org-bound workspace + active membership at
  # any role, resolved from (user, resource) via the shared gate. Matches the
  # previous global page, which sat behind member auth without an admin gate.
  defp check_workspace_access(workspace, assigns) do
    case WorkspaceAccess.check(workspace, assigns[:current_user]) do
      :ok -> :ok
      {:error, :unbound} -> {:error, "Workspace is not bound to an org."}
      {:error, :forbidden} -> {:error, "Workspace belongs to a different organization."}
      {:error, :needs_admin} -> {:error, "Admin or owner role required."}
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
