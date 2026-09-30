defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.RecentSessions
  alias ControlKeelWeb.WorkspaceAccess

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]
      # Shared aggregates computed once: loop_status reuses the overview
      # via the :overview opt instead of recomputing workspace_overview.
      overview = Observability.workspace_overview([limit: 6] ++ opts)
      loop = Observability.loop_status(Keyword.put(opts, :overview, overview))
      diagnostics = Observability.loop_diagnostics(opts)
      imports = Observability.imports(opts)
      recent_session = Mission.list_recent_sessions(1, workspace.id) |> List.first()

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
       |> assign(:opts, opts)
       |> assign(:session_id, recent_session && recent_session.id)
       |> assign(:overview, overview)
       |> assign(:loop, loop)
       |> assign(:diagnostics, diagnostics)
       |> assign(:imports, imports)
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
    with %Workspace{} = workspace <- socket.assigns[:workspace],
         :ok <- WorkspaceAccess.check(workspace, socket.assigns[:current_user], "admin") do
      opts =
        socket.assigns.opts
        |> maybe_put_session(socket.assigns.session_id)
        |> Keyword.put(:persist, true)

      snapshot = Observability.perf_snapshot(opts)

      {:noreply,
       socket
       |> assign(:snapshot, snapshot)
       |> put_flash(:info, perf_flash_message(snapshot))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Admin or owner role required.")}
    end
  end

  @impl true
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

      <CommandPill.command_pill command="controlkeel obs" />

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
          <p class="text-sm font-medium text-muted-foreground">Problems</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@overview.problems.count} groups
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@overview.problems.total_findings} active finding(s)
          </p>
          <.link
            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/problems"}
            class="mt-3 inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
          >
            Review groups <.icon name="hero-arrow-up-right" class="size-3" />
          </.link>
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
            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/costs"}
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
          <a
            href="#imports"
            class="mt-3 inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
          >
            Review imports <.icon name="hero-arrow-up-right" class="size-3" />
          </a>
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
          navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/recommendations"}
          class="inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
        >
          Open recommendations <.icon name="hero-arrow-up-right" class="size-3" />
        </.link>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Top problems</.section_title>
        <%= if @overview.problems.top == [] do %>
          <p class="text-sm text-muted-foreground">No active problems detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for problem <- @overview.problems.top do %>
              <div class="flex items-start justify-between gap-3 rounded-lg px-3 py-2 bg-muted/30">
                <p class="text-sm font-medium text-foreground">{problem.rule_id}</p>
                <p class="shrink-0 text-xs text-muted-foreground">
                  {problem.health} · {problem.count} finding(s) · {problem.affected_session_count} session(s)
                </p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <RecentSessions.session_observability_section runs={@overview.runs.recent} />

      <section id="imports" class="w-full space-y-5 pt-2">
        <div class="flex items-start justify-between gap-4 flex-wrap">
          <div class="space-y-2">
            <h2 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              Imported snapshots
            </h2>
            <p class="text-sm text-muted-foreground">
              Local persisted observability envelopes, listed as summary-only evidence snapshots.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
            <span id="observability-imports-count" class={neutral_pill_class()}>
              {@imports.count} persisted
            </span>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <CommandPill.command_pill command="controlkeel obs imports" />
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <article
            id="observability-imports-integrity"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <p class="text-sm font-medium text-muted-foreground">Integrity</p>
            <p class="mt-2 text-lg font-semibold text-foreground/90">
              {format_frequency(@imports.by_integrity)}
            </p>
          </article>
          <article
            id="observability-imports-health"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <p class="text-sm font-medium text-muted-foreground">Health</p>
            <p class="mt-2 text-lg font-semibold text-foreground/90">
              {format_frequency(@imports.by_health)}
            </p>
          </article>
        </div>

        <%= if @imports.recommendations != [] do %>
          <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
            <.section_title>Recommendations</.section_title>
            <%= for recommendation <- @imports.recommendations do %>
              <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
            <% end %>
          </section>
        <% end %>

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Recent imports</.section_title>
          <%= if @imports.recent == [] do %>
            <p class="text-sm text-muted-foreground">
              No persisted observability imports yet.
            </p>
          <% else %>
            <div class="divide-y divide-border">
              <%= for imported <- @imports.recent do %>
                <div
                  id={"observability-import-#{imported.id}"}
                  class="space-y-3 py-4 first:pt-0 last:pb-0"
                >
                  <p class="text-sm font-medium text-foreground">
                    {imported.original_session_title || "Unknown session"}
                  </p>
                  <dl class="grid grid-cols-2 gap-3 text-xs md:grid-cols-4">
                    <div>
                      <dt class="text-muted-foreground">Imported</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {imported.imported_at || "unknown time"}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Exported</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {imported.exported_at || "unknown time"}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Session</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        #{imported.original_session_id || "unknown"}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Health</dt>
                      <dd class="mt-0.5 font-medium text-foreground">{imported.health}</dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Problem groups</dt>
                      <dd class="mt-0.5 font-medium text-foreground">{imported.problem_groups}</dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Findings</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {imported.total_problem_findings}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Integrity</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {imported.integrity_status}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Mutation</dt>
                      <dd class="mt-0.5 font-medium text-foreground">{imported.mutation}</dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Schema</dt>
                      <dd class="mt-0.5 font-medium text-foreground">{imported.schema_version}</dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Source</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {source_label(imported.source)}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-muted-foreground">Redaction</dt>
                      <dd class="mt-0.5 font-medium text-foreground">
                        {imported.redaction_policy || "unknown"}
                      </dd>
                    </div>
                    <div class="col-span-2 md:col-span-4">
                      <dt class="text-muted-foreground">Fingerprint</dt>
                      <dd class="mt-0.5 truncate font-mono text-[10px] text-foreground">
                        {imported.payload_fingerprint || "unknown"}
                      </dd>
                    </div>
                  </dl>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
      </section>

      <section id="learning-loop" class="w-full space-y-5 pt-2">
        <div id="observability-loop" class="flex items-start justify-between gap-4 flex-wrap">
          <div class="space-y-2">
            <h2 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              Learning loop
            </h2>
            <p class="text-sm text-muted-foreground">
              Read-only, local-first status for turning repeated CK and agent use into reviewed evals, benchmark evidence, and human-gated improvement candidates.
            </p>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <span class={health_pill_class(@loop.health)}>{@loop.health}</span>
            <span class="rounded-full bg-primary/10 px-3 py-1.5 text-sm font-semibold text-primary ring-1 ring-primary/20">
              {@loop.learning_loop.mode}
            </span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs loop" />

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Safety boundary</.section_title>
          <p class="text-sm font-medium text-foreground">
            Read-only: {@loop.read_only} · Mutation: {@loop.mutation}
          </p>
          <p class="text-xs text-muted-foreground">
            Automatic benchmark execution: {@loop.learning_loop.automatic_benchmark_execution} · Automatic promotion: {@loop.learning_loop.automatic_promotion}
          </p>
          <p class="text-xs text-muted-foreground">
            Generated benchmarks are {@loop.learning_loop.generated_benchmarks}.
          </p>
        </section>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Problems</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@loop.active_problems.count} group(s)
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {@loop.active_problems.total_findings} active finding(s)
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

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Blockers</.section_title>
          <%= if @loop.blockers == [] do %>
            <p class="text-sm text-muted-foreground">No learning-loop blockers detected.</p>
          <% else %>
            <div class="space-y-2">
              <%= for blocker <- @loop.blockers do %>
                <div class="flex items-start justify-between gap-3 rounded-lg px-3 py-2 bg-destructive/10">
                  <p class="text-sm font-medium text-foreground">{blocker.id}</p>
                  <p class="shrink-0 text-xs text-muted-foreground">{blocker.reason}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Next actions</.section_title>
          <%= if @loop.next_actions == [] do %>
            <p class="text-sm text-muted-foreground">No next actions.</p>
          <% else %>
            <div class="space-y-2">
              <%= for action <- @loop.next_actions do %>
                <div class="rounded-lg px-3 py-2 bg-muted/30 space-y-1">
                  <p class="text-sm font-medium text-foreground">
                    [{action.priority}] {action.title}
                  </p>
                  <p class="text-xs text-muted-foreground">{action.suggested_action}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>

        <%= if @loop.recommendations != [] do %>
          <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
            <.section_title>Recommendations</.section_title>
            <ul class="space-y-2 text-sm leading-relaxed text-muted-foreground list-disc ml-5">
              <%= for recommendation <- @loop.recommendations do %>
                <li>{recommendation}</li>
              <% end %>
            </ul>
          </section>
        <% end %>

        <section id="observability-loop-diagnostics" class="space-y-4">
          <div class="flex items-start justify-between gap-3 flex-wrap">
            <div class="space-y-1">
              <.section_title>Loop diagnostics</.section_title>
              <p class="text-xs text-muted-foreground">
                Repeated identical tool-event and invocation runs detected in the sampled window.
              </p>
            </div>
            <span class={neutral_pill_class()}>
              {@diagnostics.totals.event_runs} event run(s) · {@diagnostics.totals.invocation_runs} invocation run(s)
            </span>
          </div>

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
                Measures observability read-path timing; capturing persists a durable memory record.
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

          <%= if @snapshot do %>
            <p class="text-xs text-muted-foreground">
              Generated at {format_dt(@snapshot.generated_at)}
            </p>

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
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

            <div id="observability-perf-items" class="divide-y divide-border">
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
          <% else %>
            <p class="text-sm text-muted-foreground">
              No performance snapshot captured yet. Capture one to persist a durable perf memory record.
            </p>
          <% end %>
        </section>
      </section>
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp perf_flash_message(%{summary: summary}) do
    "Performance snapshot captured and persisted: #{summary.item_count} item(s), #{summary.total_wall_ms} ms total."
  end

  defp maybe_put_session(opts, nil), do: opts
  defp maybe_put_session(opts, session_id), do: Keyword.put(opts, :session_id, session_id)

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(_), do: "—"

  defp format_ms(value) when is_number(value), do: "#{value} ms"
  defp format_ms(_), do: "—"

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_), do: "—"

  defp source_label(source) when is_map(source) do
    [source["product"], source["surface"], source["mode"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
    |> case do
      "" -> "unknown"
      label -> label
    end
  end

  defp source_label(_source), do: "unknown"
end
