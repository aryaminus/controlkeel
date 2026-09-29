defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.RecentSessions
  alias ControlKeelWeb.WorkspaceAccess

  import ControlKeelWeb.ObservabilityHelpers

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]
      overview = Observability.workspace_overview([limit: 6] ++ opts)
      # Folded loop sections render blockers/diagnostics only — next_actions
      # is never shown, so skip the recommendations build (problems + costs
      # + project scan) on page load.
      loop = Observability.loop_status(opts ++ [overview: overview, skip_recommendations: true])
      diagnostics = Observability.loop_diagnostics(opts)

      {:ok,
       socket
       |> assign(:page_title, "Observability")
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
           %{label: "Observability", to: nil}
         ]
       )
       |> assign(:overview, overview)
       |> assign(:loop, loop)
       |> assign(:diagnostics, diagnostics)
       |> assign(:snapshot, nil)}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  defp check_workspace_access(workspace, assigns) do
    case WorkspaceAccess.check(workspace, assigns[:current_user]) do
      :ok -> :ok
      {:error, :unbound} -> {:error, "Workspace is not bound to an org."}
      {:error, :forbidden} -> {:error, "Workspace belongs to a different organization."}
      {:error, :needs_admin} -> {:error, "Viewer role or higher required."}
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  @impl true
  def handle_event("capture-perf-snapshot", _params, socket) do
    # Non-persisting readout: measures read-path timing for display only.
    # Never writes a memory record — durable snapshots live in the obs CLI.
    # Session scoping is resolved here (not on mount) so page load stays lean.
    workspace = socket.assigns.workspace
    session_id = recent_session_id(workspace.id)

    opts =
      [workspace_id: workspace.id]
      |> maybe_put_session(session_id)

    snapshot = Observability.perf_snapshot(opts)

    {:noreply,
     socket
     |> assign(:snapshot, snapshot)
     |> put_flash(:info, perf_flash_message(snapshot))}
  end

  @impl true
  def handle_event("close-perf-snapshot", _params, socket) do
    {:noreply, assign(socket, :snapshot, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-overview-page" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Observability
          </h1>
          <p class="text-sm text-muted-foreground">
            Session runs, problems, costs, trace export, and learning-loop status at a glance.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <span class={health_pill_class(@loop.health)}>{@loop.health}</span>
          <span class="rounded-full bg-primary/10 px-3 py-1.5 text-sm font-semibold text-primary ring-1 ring-primary/20">
            {@loop.learning_loop.mode}
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <article
          id="observability-overview-problems"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Problems</p>
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
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Evals</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.evals.derived} derived / {@loop.evals.saved} saved
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            Saved status: {format_frequency(@loop.evals.saved_by_status)}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Benchmarks</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.benchmarks.scenarios} scenario(s)
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@loop.benchmarks.drafts} draft(s), readiness {@loop.benchmarks.history_readiness.status}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Promotions</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.promotions.count} candidate(s)
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            Readiness: {format_frequency(@loop.promotions.by_readiness)}
          </p>
        </article>
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <section
          id="observability-loop-fold"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
        >
          <.section_title>Safety boundary</.section_title>
          <p class="text-sm font-medium text-foreground">
            Read-only: <span class="text-muted-foreground">{@loop.read_only}</span>
          </p>
          <p class="text-sm font-medium text-foreground">
            Mutation: <span class="text-muted-foreground">{@loop.mutation}</span>
          </p>

          <p class="text-sm font-medium text-foreground">
            Automatic benchmark execution:
            <span class="text-muted-foreground">
              {@loop.learning_loop.automatic_benchmark_execution}
            </span>
          </p>
          <p class="text-sm font-medium text-foreground">
            Automatic promotion:
            <span class="text-muted-foreground">{@loop.learning_loop.automatic_promotion}</span>
          </p>

          <p class="text-sm font-medium text-foreground">
            Generated benchmarks are <span class="text-foreground">{@loop.learning_loop.generated_benchmarks}</span>.
          </p>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Blockers</.section_title>
          <%= if @loop.blockers == [] do %>
            <div class="flex items-center gap-2.5 rounded-lg bg-success/10 px-3 py-2.5 ring-1 ring-success/20">
              <.icon name="hero-check-circle" class="size-4 shrink-0 text-success" />
              <p class="text-sm text-muted-foreground">Loop is flowing — nothing stuck.</p>
            </div>
          <% else %>
            <ul class="space-y-4">
              <%= for blocker <- @loop.blockers do %>
                <li class="flex items-start gap-2.5 rounded-lg bg-destructive/10 px-3 py-2.5 ring-1 ring-destructive/20">
                  <.icon
                    name="hero-exclamation-circle"
                    class="size-4 shrink-0 mt-0.5 text-destructive"
                  />
                  <div class="min-w-0 space-y-0.5">
                    <p class="text-sm font-medium text-foreground">
                      {humanize_blocker_id(blocker.id)}
                    </p>
                    <p class="text-xs leading-relaxed text-muted-foreground">
                      {blocker.reason}
                    </p>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>
      </div>

      <RecentSessions.session_observability_section runs={@overview.runs.recent} />

      <section id="observability-loop-diagnostics" class="space-y-4">
        <.section_title>Loop diagnostics</.section_title>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <section
            id="observability-loop-diagnostics-events"
            class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
          >
            <div class="flex items-center justify-between gap-2">
              <p class="text-sm font-medium text-muted-foreground">Repeated tool events</p>
              <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
                {@diagnostics.totals.event_runs} run(s)
              </span>
            </div>
            <%= if @diagnostics.repeated_tool_events == [] do %>
              <p class="text-sm text-muted-foreground">
                No repeated identical tool-event runs detected.
              </p>
            <% else %>
              <div class="divide-y divide-border">
                <%= for run <- @diagnostics.repeated_tool_events do %>
                  <div class="space-y-1.5 py-3 first:pt-0 last:pb-0">
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-medium text-foreground">{run.sample.event_type}</p>
                      <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-foreground">
                        {run.count}×
                      </span>
                    </div>
                    <p class="text-xs text-muted-foreground">
                      actor: {run.sample.actor || "—"} · session #{run.sample.session_id}
                    </p>
                    <p class="text-xs leading-relaxed text-foreground">{run.sample.summary}</p>
                    <p class="text-xs text-muted-foreground">
                      {format_dt(run.first_at)} → {format_dt(run.last_at)}
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>

          <section
            id="observability-loop-diagnostics-invocations"
            class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
          >
            <div class="flex items-center justify-between gap-2">
              <p class="text-sm font-medium text-muted-foreground">Repeated invocations</p>
              <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
                {@diagnostics.totals.invocation_runs} run(s)
              </span>
            </div>
            <%= if @diagnostics.repeated_invocations == [] do %>
              <p class="text-sm text-muted-foreground">
                No repeated identical invocation runs detected.
              </p>
            <% else %>
              <div class="divide-y divide-border">
                <%= for run <- @diagnostics.repeated_invocations do %>
                  <div class="space-y-1.5 py-3 first:pt-0 last:pb-0">
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-medium text-foreground">{run.sample.tool}</p>
                      <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-foreground">
                        {run.count}×
                      </span>
                    </div>
                    <p class="text-xs text-muted-foreground">
                      {run.sample.source} · {run.sample.provider} / {run.sample.model}
                    </p>
                    <p class="text-xs text-muted-foreground">session #{run.sample.session_id}</p>
                    <p class="text-xs text-muted-foreground">
                      {format_dt(run.first_at)} → {format_dt(run.last_at)}
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </section>
        </div>

        <%= if @diagnostics.recommendations != [] do %>
          <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
            <.section_title>Diagnostics recommendations</.section_title>
            <ul class="space-y-2 text-sm leading-relaxed text-muted-foreground list-disc ml-5">
              <%= for recommendation <- @diagnostics.recommendations do %>
                <li>{recommendation}</li>
              <% end %>
            </ul>
          </section>
        <% end %>
      </section>

      <section
        id="observability-perf-snapshot"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div class="space-y-1">
            <.section_title>Performance snapshot</.section_title>
            <p class="text-xs text-muted-foreground">
              Measures observability read-path timing for display only — nothing is persisted.
              Durable snapshots live in the obs CLI.
            </p>
          </div>
          <.button
            id="observability-perf-capture"
            type="button"
            variant="outline"
            phx-click="capture-perf-snapshot"
          >
            Capture performance snapshot
          </.button>
        </div>

        <p class="text-sm text-muted-foreground">
          No performance snapshot captured yet.
        </p>
      </section>

      <.modal
        :if={@snapshot}
        id="observability-perf-modal"
        title="Performance snapshot"
        on_close="close-perf-snapshot"
        width="max-w-3xl"
      >
        <p class="text-xs text-muted-foreground">
          Generated at {format_dt(@snapshot.generated_at)}
        </p>

        <div class="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
          <article class="rounded-2xl border bg-card p-4">
            <p class="text-sm font-medium text-muted-foreground">Items</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@snapshot.summary.item_count}
            </p>
          </article>
          <article class="rounded-2xl border bg-card p-4">
            <p class="text-sm font-medium text-muted-foreground">Total wall time</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {format_ms(@snapshot.summary.total_wall_ms)}
            </p>
          </article>
          <article class="rounded-2xl border bg-card p-4">
            <p class="text-sm font-medium text-muted-foreground">Ecto queries</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@snapshot.summary.total_ecto_queries}
            </p>
          </article>
          <article class="rounded-2xl border bg-card p-4">
            <p class="text-sm font-medium text-muted-foreground">Payload</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {format_bytes(@snapshot.summary.total_payload_bytes)}
            </p>
          </article>
        </div>

        <div id="observability-perf-items" class="mt-4 divide-y divide-border">
          <%= for item <- @snapshot.items do %>
            <div class="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
              <div class="min-w-0">
                <p class="text-sm font-medium text-foreground leading-snug">{item.label}</p>
              </div>
              <p class="shrink-0 text-xs text-muted-foreground">
                {format_ms(item.wall_ms)} · {item.ecto_query_count} query(s) · {format_bytes(
                  item.payload_bytes
                )}
              </p>
            </div>
          <% end %>
        </div>
      </.modal>
    </section>
    """
  end

  defp perf_flash_message(%{summary: summary}) do
    "Performance snapshot captured: #{summary.item_count} item(s), #{summary.total_wall_ms} ms total. Nothing persisted."
  end

  defp recent_session_id(workspace_id) do
    case Mission.list_recent_sessions(1, workspace_id) do
      [%{id: id} | _] -> id
      _ -> nil
    end
  end

  defp maybe_put_session(opts, nil), do: opts
  defp maybe_put_session(opts, session_id), do: Keyword.put(opts, :session_id, session_id)
end
