defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  @refresh_interval_ms 2_000

  @impl true
  def mount(
        %{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug} = params,
        _session,
        socket
      ) do
    current_user = socket.assigns[:current_user]

    case SessionScope.fetch_session(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(session) ->
        cond do
          not ControlKeel.Accounts.session_accessible?(session, current_user) ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()
            project_root = socket.endpoint.config(:project_root) || File.cwd!()

            {:ok,
             socket
             |> assign(:page_title, session.title)
             |> assign(:project_root, project_root)
             |> assign(:launched, Map.get(params, "launched") == "1")
             |> safe_assign_session(session)}
        end
    end
  end

  defp assign_session_nav(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    crumbs =
      if org && workspace do
        [
          %{label: org.name, to: "/#{org.slug}"},
          %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
          %{label: session.title, to: nil}
        ]
      else
        []
      end

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:breadcrumbs, crumbs)
  end

  @impl true
  def handle_info(:refresh, socket) do
    opts = [tasks_limit: 0, invocations_limit: 0, reviews_limit: 0]

    case Mission.get_session_context(socket.assigns.session.id, opts) do
      nil ->
        {:noreply, SessionScope.session_not_found(socket)}

      session ->
        case SessionScope.reauthorize(socket, session) do
          {:ok, session} ->
            if connected?(socket), do: schedule_refresh()
            {:noreply, tick_assign(socket, session)}

          {:error, :not_found} ->
            {:noreply, SessionScope.session_not_found(socket)}
        end
    end
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <%= if @launched do %>
        <div class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-start gap-3">
            <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-success/10 text-success">
              <.icon name="hero-check-circle" class="size-4" />
            </span>
            <div class="min-w-0 space-y-2">
              <p class="text-base font-semibold text-foreground">
                You're set — ControlKeel is governing this session
              </p>
              <p class="text-sm leading-6 text-muted-foreground">
                Attach your preferred client to start intercepting agent actions. OpenCode is the fastest MCP-plus-instructions path:
                <code class="rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-foreground">
                  controlkeel attach opencode
                </code>
              </p>
              <p class="text-sm leading-6 text-muted-foreground">
                Or validate content directly via the
                <.link
                  navigate={~p"/policies"}
                  class="font-medium text-primary underline-offset-4 transition hover:underline"
                >
                  Policy Studio
                </.link>
                or REST API at <code class="rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-foreground">POST /api/v1/validate</code>.
              </p>
            </div>
          </div>
        </div>
      <% end %>
      <.page_title title={@session.title} subtitle={@session.objective} />

      <div class="grid grid-cols-1 gap-4 rounded-2xl border bg-card p-5 shadow-card sm:grid-cols-2 lg:grid-cols-5 lg:gap-0">
        <article class="p-5 lg:border-r lg:border-border">
          <p class="text-sm font-medium text-muted-foreground">Primary agent</p>
          <p class="mt-2 truncate text-xl font-semibold text-foreground/90">{@agent_label}</p>
        </article>

        <article class="p-5 lg:border-r lg:border-border">
          <p class="text-sm font-medium text-muted-foreground">Needs review</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@active_findings} finding{if @active_findings != 1, do: "s"}
          </p>
          <p class="mt-3 text-xs text-muted-foreground">Open or blocked</p>
        </article>

        <article class="p-5 lg:border-r lg:border-border">
          <p class="text-sm font-medium text-muted-foreground">Compliance score</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@compliance_score}%</p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class={["h-full rounded-full", compliance_bar_class(@compliance_score)]}
              style={"width: #{@compliance_score}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Findings approved or rejected</p>
        </article>

        <% budget_pct = budget_percent(@session.spent_cents, @session.budget_cents) %>

        <article class="p-5 lg:border-r lg:border-border">
          <p class="text-sm font-medium text-muted-foreground">Budget spent</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_currency(@session.spent_cents)} / {format_currency(@session.budget_cents)}
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              :if={budget_pct}
              class={["h-full rounded-full", budget_bar_class(budget_pct)]}
              style={"width: #{budget_pct}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Session budget utilization</p>
        </article>

        <article class="p-5">
          <p class="text-sm font-medium text-muted-foreground">Proof bundles</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{map_size(@latest_proofs)}</p>
          <p class="mt-3 text-xs text-muted-foreground">Latest bundle per task</p>
        </article>
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <section class="rounded-2xl border bg-card p-5 shadow-card lg:col-span-2">
          <div class="flex items-center justify-between gap-3">
            <.section_title>Session metrics</.section_title>
            <span class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs text-muted-foreground">
              <span class="size-1.5 animate-pulse rounded-full bg-success" /> Live
            </span>
          </div>
          <div class="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <div class="rounded-xl bg-muted/[0.03] p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-sm font-medium text-muted-foreground">Funnel stage</p>
                <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-info/10 text-info">
                  <.icon name="hero-signal" class="size-4" />
                </span>
              </div>
              <p class="mt-2 text-lg font-semibold text-foreground/90">
                {Analytics.stage_label(@session_metrics.funnel_stage)}
              </p>
              <p class="mt-3 text-xs text-muted-foreground">Latest analytics snapshot</p>
            </div>

            <div class="rounded-xl bg-muted/[0.03] p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-sm font-medium text-muted-foreground">First finding</p>
                <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                  <.icon name="hero-clock" class="size-4" />
                </span>
              </div>
              <p class="mt-2 text-lg font-semibold text-foreground/90">
                {format_duration(@session_metrics.time_to_first_finding_seconds)}
              </p>
              <p class="mt-3 text-xs text-muted-foreground">Time from session start</p>
            </div>

            <div class="rounded-xl bg-muted/[0.03] p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-sm font-medium text-muted-foreground">Total findings</p>
                <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                </span>
              </div>
              <p class="mt-2 text-lg font-semibold text-foreground/90">
                {@session_metrics.total_findings}
              </p>
              <p class="mt-3 text-xs text-muted-foreground">Raised during the session</p>
            </div>

            <% blocked_pct =
              blocked_ratio_percent(
                @session_metrics.blocked_findings_total,
                @session_metrics.total_findings
              ) %>

            <div class="rounded-xl bg-muted/[0.03] p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-sm font-medium text-muted-foreground">Blocked findings</p>
                <span class={[
                  "flex h-8 w-8 shrink-0 items-center justify-center rounded-full",
                  @session_metrics.blocked_findings_total > 0 && "bg-destructive/10 text-destructive",
                  @session_metrics.blocked_findings_total == 0 && "bg-success/10 text-success"
                ]}>
                  <.icon name="hero-shield-exclamation" class="size-4" />
                </span>
              </div>
              <p class={[
                "mt-2 text-lg font-semibold",
                @session_metrics.blocked_findings_total > 0 && "text-destructive",
                @session_metrics.blocked_findings_total == 0 && "text-foreground/90"
              ]}>
                {@session_metrics.blocked_findings_total}
              </p>
              <div class="mt-3 h-2 overflow-hidden rounded-full bg-muted">
                <div
                  :if={blocked_pct}
                  class="h-full rounded-full bg-destructive"
                  style={"width: #{blocked_pct}%"}
                />
              </div>
              <p class="mt-3 text-xs text-muted-foreground">
                {if is_nil(blocked_pct),
                  do: "No findings yet",
                  else: "#{blocked_pct}% of all findings"}
              </p>
            </div>
          </div>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Session context</.section_title>

          <ul class="mt-4 space-y-3">
            <%= for {label, value, icon_name} <- session_context_items(@session, @nav_org, @nav_workspace) do %>
              <li class="flex items-center gap-3 w-full">
                <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                  <.icon name={icon_name} class="size-4" />
                </span>
                <p class="w-28 shrink-0 text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  {label}
                </p>
                <p class="min-w-0 flex-1 truncate text-right text-sm font-medium text-foreground">
                  {value || "Not specified"}
                </p>
              </li>
            <% end %>
          </ul>
        </section>
      </div>

      <details class="group rounded-2xl border bg-card p-5 shadow-card">
        <summary class="flex cursor-pointer select-none list-none items-center gap-2">
          <.section_title>Execution brief</.section_title>
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-open:rotate-90"
          />
        </summary>
        <dl class="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Domain pack
            </dt>
            <dd class="mt-1 text-sm font-medium text-foreground">
              {format_domain_pack(brief_value(@brief, "domain_pack"))}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Occupation
            </dt>
            <dd class="mt-1 text-sm font-medium text-foreground">
              {brief_value(@brief, "occupation")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Recommended stack
            </dt>
            <dd class="mt-1 text-sm font-medium text-foreground">
              {brief_value(@brief, "recommended_stack")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Compiler
            </dt>
            <dd class="mt-1 text-sm font-medium text-foreground">
              {brief_value(@compiler, "provider")} / {brief_value(@compiler, "model")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Next step
            </dt>
            <dd class="mt-1 text-sm leading-6 text-muted-foreground">
              {brief_value(@brief, "next_step")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Acceptance criteria
            </dt>
            <dd class="mt-1.5">
              <ul class="ml-5 list-disc space-y-1 text-sm leading-6 text-muted-foreground">
                <%= for item <- brief_list(@brief, "acceptance_criteria") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </dd>
          </div>
        </dl>
      </details>

      <% risk_tier = boundary_value(@boundary_summary, "risk_tier") %>

      <details class="group rounded-2xl border bg-card p-5 shadow-card">
        <summary class="flex cursor-pointer select-none list-none items-center gap-2">
          <.section_title>Production boundary</.section_title>
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-open:rotate-90"
          />
        </summary>
        <dl class="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Risk tier
            </dt>
            <dd class="mt-1">
              <span
                :if={risk_tier_class(risk_tier)}
                class={[
                  "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                  risk_tier_class(risk_tier)
                ]}
              >
                {risk_tier}
              </span>
              <span
                :if={is_nil(risk_tier_class(risk_tier))}
                class="text-sm font-medium text-foreground"
              >
                {risk_tier}
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Budget note
            </dt>
            <dd class="mt-1 text-sm leading-6 text-muted-foreground">
              {boundary_value(@boundary_summary, "budget_note")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Launch window
            </dt>
            <dd class="mt-1 text-sm font-medium text-foreground">
              {boundary_value(@boundary_summary, "launch_window")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Data summary
            </dt>
            <dd class="mt-1 text-sm leading-6 text-muted-foreground">
              {boundary_value(@boundary_summary, "data_summary")}
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Constraints
            </dt>
            <dd class="mt-1.5">
              <ul class="ml-5 list-disc space-y-1 text-sm leading-6 text-muted-foreground">
                <%= for item <- boundary_list(@boundary_summary, "constraints") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </dd>
          </div>
          <div>
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Compliance
            </dt>
            <dd class="mt-1.5">
              <ul class="flex flex-wrap gap-1.5">
                <%= for item <- boundary_list(@boundary_summary, "compliance") do %>
                  <li class="inline-flex items-center rounded-full bg-info/10 px-2.5 py-1 text-xs font-medium text-info ring-1 ring-info/20">
                    {item}
                  </li>
                <% end %>
              </ul>
            </dd>
          </div>
          <div class="sm:col-span-2">
            <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Open questions
            </dt>
            <dd class="mt-1.5">
              <ul class="ml-5 list-disc space-y-1 text-sm leading-6 text-muted-foreground">
                <%= for item <- boundary_list(@boundary_summary, "open_questions") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </dd>
          </div>
        </dl>
      </details>

      <details class="group rounded-2xl border bg-card p-5 shadow-card">
        <summary class="flex cursor-pointer select-none list-none items-center gap-2">
          <.section_title>Workspace context</.section_title>
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="mt-4 flex flex-wrap gap-2">
          <span class={[
            "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1",
            workspace_status_class(@current_workspace_context)
          ]}>
            {workspace_status_label(@current_workspace_context)}
          </span>
          <span class="inline-flex items-center rounded-full border px-3 py-1 font-mono text-xs text-muted-foreground">
            {get_in(@current_workspace_context, ["git", "branch"]) || "no-branch"}
          </span>
          <span class="inline-flex items-center rounded-full border px-3 py-1 font-mono text-xs text-muted-foreground">
            {String.slice(
              get_in(@current_workspace_context, ["git", "head_sha"]) || "unknown",
              0,
              7
            )}
          </span>
          <span class="inline-flex items-center rounded-full border px-3 py-1 text-xs text-muted-foreground">
            {length(@current_workspace_context["instruction_files"] || [])} instructions
          </span>
          <span class="inline-flex items-center rounded-full border px-3 py-1 text-xs text-muted-foreground">
            {length(@current_workspace_context["key_files"] || [])} key files
          </span>
        </div>
        <p class="mt-3 text-sm leading-6 text-muted-foreground">
          {@current_workspace_context["summary_text"]}
        </p>
        <details class="group/raw mt-4">
          <summary class="inline-flex cursor-pointer select-none items-center gap-1.5 text-sm font-medium text-muted-foreground transition hover:text-primary">
            View raw workspace JSON
            <.icon
              name="hero-chevron-down"
              class="size-3.5 transition-transform group-open/raw:rotate-180"
            />
          </summary>
          <pre class="mt-4 max-h-96 overflow-auto rounded-xl bg-muted/[0.03] p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap break-all text-muted-foreground">{Jason.encode!(@current_workspace_context, pretty: true)}</pre>
        </details>
      </details>
    </section>
    """
  end

  defp safe_assign_session(socket, session) do
    socket
    |> assign_session(session)
    # Filesystem + git inspection (several subprocesses): compute once at mount,
    # not on every 2s tick. Remount to pick up branch/sha changes.
    |> assign(:current_workspace_context, Mission.workspace_context(session))
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(session.workspace.id))
  rescue
    e ->
      require Logger
      Logger.warning("MissionControlLive assign_session rescued: #{inspect(e)}")

      # Degraded but renderable: every assign the template reads gets a default
      # so a partial failure can't turn into a certain KeyError on render.
      findings = if is_list(session.findings), do: session.findings, else: []

      socket
      |> assign(:session, session)
      |> assign(:workspace, session.workspace)
      |> assign_session_nav(session)
      |> assign(:page_title, session.title)
      |> assign(:sibling_sessions, [])
      |> assign(:agent_label, "Not specified")
      |> assign(
        :active_findings,
        Enum.count(findings, &(&1.status in ["open", "blocked"]))
      )
      |> assign(:compliance_score, compliance_score(findings))
      |> assign(:session_metrics, default_session_metrics(session.id))
      |> assign(:brief, %{})
      |> assign(:compiler, %{})
      |> assign(:boundary_summary, Intent.boundary_summary(%{}))
      |> assign(:latest_proofs, %{})
      |> assign(:current_workspace_context, %{"available" => false})
  end

  defp tick_assign(socket, session) do
    assign_session(socket, session)
  rescue
    e ->
      require Logger
      Logger.warning("MissionControlLive tick assign rescued: #{inspect(e)}")
      socket
  end

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    socket
    |> assign_session_nav(session)
    |> assign(
      session: session,
      workspace: session.workspace,
      session_metrics:
        Analytics.session_metrics(session.id) || default_session_metrics(session.id),
      brief: brief,
      boundary_summary: Intent.boundary_summary(brief),
      compiler: compiler,
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      compliance_score: compliance_score(session.findings),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent"))
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp workspace_status_label(%{"available" => true}), do: "available"
  defp workspace_status_label(_context), do: "unavailable"

  defp format_currency(cents), do: cents |> Kernel./(100) |> Float.round(2)

  defp brief_value(map, key), do: Map.get(map, key, "Not specified")
  defp brief_list(map, key), do: List.wrap(Map.get(map, key, []))
  defp boundary_value(map, key), do: Map.get(map, key) || "Not specified"

  defp boundary_list(map, key) do
    case Map.get(map, key, []) do
      [] -> ["Not specified"]
      items -> items
    end
  end

  defp format_domain_pack("Not specified"), do: "Not specified"
  defp format_domain_pack(nil), do: "Not specified"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp compliance_score([]), do: 100

  defp compliance_score(findings) do
    total = length(findings)
    resolved = Enum.count(findings, &(&1.status in ["approved", "rejected"]))
    round(resolved / total * 100)
  end

  defp compliance_bar_class(score) when score >= 80, do: "bg-success"
  defp compliance_bar_class(score) when score >= 50, do: "bg-warning"
  defp compliance_bar_class(_score), do: "bg-destructive"

  defp budget_percent(spent, budget) when is_number(budget) and budget > 0,
    do: min(round(spent / budget * 100), 100)

  defp budget_percent(_spent, _budget), do: nil

  defp blocked_ratio_percent(blocked, total) when is_number(total) and total > 0,
    do: min(round(blocked / total * 100), 100)

  defp blocked_ratio_percent(_blocked, _total), do: nil

  defp budget_bar_class(pct) when pct >= 100, do: "bg-destructive"
  defp budget_bar_class(pct) when pct >= 80, do: "bg-warning"
  defp budget_bar_class(_pct), do: "bg-primary"

  defp risk_tier_class(tier) when tier in ["low"],
    do: "bg-success/10 text-success ring-success/20"

  defp risk_tier_class(tier) when tier in ["medium", "moderate"],
    do: "bg-warning/10 text-warning ring-warning/20"

  defp risk_tier_class(tier) when tier in ["high", "critical"],
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp risk_tier_class(_tier), do: nil

  defp workspace_status_class(%{"available" => true}),
    do: "bg-success/10 text-success ring-success/20"

  defp workspace_status_class(_context), do: "bg-muted text-muted-foreground ring-border"

  defp session_context_items(session, org, workspace) do
    [
      {"Organization", org && org.name, "hero-building-office-2"},
      {"Workspace", workspace && workspace.name, "hero-squares-2x2"},
      {"Session", session.title, "hero-bolt"},
      {"Created", format_created_date(session.inserted_at), "hero-clock"}
    ]
  end

  defp format_created_date(nil), do: nil
  defp format_created_date(""), do: nil
  defp format_created_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_created_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_created_date(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")

  defp format_created_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%Y-%m-%d")

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} ->
            Calendar.strftime(ndt, "%Y-%m-%d")

          _ ->
            case Date.from_iso8601(String.slice(value, 0, 10)) do
              {:ok, d} -> Calendar.strftime(d, "%Y-%m-%d")
              _ -> String.slice(value, 0, 10)
            end
        end
    end
  end

  defp format_created_date(value), do: to_string(value)

  defp default_session_metrics(session_id) do
    %{
      session_id: session_id,
      funnel_stage: "unknown",
      time_to_first_finding_seconds: nil,
      total_findings: 0,
      blocked_findings_total: 0
    }
  end
end
