defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Proxy
  alias ControlKeelWeb.ShipReadiness

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if ControlKeel.Accounts.session_accessible?(session, org_id) do
          if connected?(socket), do: schedule_refresh()
          project_root = socket.endpoint.config(:project_root) || File.cwd!()

          {:ok,
           socket
           |> assign(:page_title, session.title)
           |> assign(:project_root, project_root)
           |> assign(:launched, Map.get(params, "launched") == "1")
           |> safe_assign_session(session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
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

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply, socket |> assign_session(session)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-[1180px] w-full px-4 pt-8 pb-16">
      <%= if @launched do %>
        <div class="p-6 rounded-3xl border bg-[var(--ck-success)] text-muted-foreground border-l-4 border-l-[var(--ck-success)] mb-6">
          <div class="flex items-start gap-4">
            <span class="text-2xl leading-none">✓</span>
            <div>
              <strong class="block mb-1">
                You're set — ControlKeel is governing this session
              </strong>
              <p class="text-sm text-muted-foreground mb-3">
                Attach your preferred client to start intercepting agent actions. OpenCode is the fastest MCP-plus-instructions path:
                <code class="font-mono bg-[var(--ck-success)] px-1.5 py-0.5 rounded text-sm">
                  controlkeel attach opencode
                </code>
              </p>
              <p class="text-sm text-muted-foreground">
                Or validate content directly via the
                <a href="/policies" class="underline hover:text-[var(--ck-success)]">Policy Studio</a>
                or REST API at <code class="font-mono bg-[var(--ck-success)] px-1.5 py-0.5 rounded text-sm">POST /api/v1/validate</code>.
              </p>
            </div>
          </div>
        </div>
      <% end %>
      <div class="space-y-1 min-w-0 mb-12">
        <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
          {@session.title}
        </h2>
        <p class="text-muted-foreground">
          {@session.objective}
        </p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mt-5">
        <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Primary agent
          </p>
          <strong>{@agent_label}</strong>
        </div>
        <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Needs review
          </p>
          <strong>{@active_findings} finding{if @active_findings != 1, do: "s"}</strong>
        </div>
        <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Compliance score
          </p>
          <div class="flex items-center gap-3">
            <svg
              viewBox="0 0 36 36"
              width="48"
              height="48"
              class="shrink-0 -rotate-90"
            >
              <circle cx="18" cy="18" r="15.9" fill="none" stroke="#e5e7eb" stroke-width="3.8" />
              <circle
                cx="18"
                cy="18"
                r="15.9"
                fill="none"
                stroke={donut_color(@compliance_score)}
                stroke-width="3.8"
                stroke-dasharray={"#{@compliance_score} #{100 - @compliance_score}"}
                stroke-linecap="round"
              />
            </svg>
            <strong>{@compliance_score}%</strong>
          </div>
        </div>
        <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Budget spent
          </p>
          <strong>
            {format_currency(@session.spent_cents)} / {format_currency(@session.budget_cents)}
          </strong>
        </div>
        <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Proof bundles
          </p>
          <strong>{map_size(@latest_proofs)}</strong>
        </div>
      </div>

      <div
        id="mission-observability-panel"
        class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6"
      >
        <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 mt-6 mb-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Session run observability
            </p>
            <h2 class="m-0 text-xl font-bold text-foreground">{@observability.health.label}</h2>
            <p class="text-sm text-muted-foreground mt-1.5">
              Compact local-first view of health, events, findings, gates, memory, proofs, and cost.
            </p>
          </div>
          <div class="flex flex-wrap gap-2 items-center">
            <span
              id="mission-observability-health"
              class={obs_health_pill_class(@observability.health.status)}
            >
              {@observability.health.status}
            </span>
            <.link
              id="mission-observability-open"
              navigate={~p"/observability/sessions/#{@session.id}"}
              class="text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary transition bg-transparent border-0 p-0 cursor-pointer"
            >
              Open run observability
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-5">
          <div
            id="mission-observability-budget"
            class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Budget health
            </p>
            <strong>{@observability.budget["decision"] || "unknown"}</strong>
            <p class="text-xs text-muted-foreground mt-1">
              {format_currency(@observability.budget["spent_cents"] || 0)} / {format_currency(
                @observability.budget["session_budget_cents"] || 0
              )} used
            </p>
          </div>
          <div
            id="mission-observability-findings"
            class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Findings
            </p>
            <strong>{@observability.findings.active} active</strong>
            <p class="text-xs text-muted-foreground mt-1">
              {@observability.findings.critical} critical · {@observability.findings.high} high · {@observability.findings.blocked} blocked
            </p>
          </div>
          <div
            id="mission-observability-gates"
            class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Gates
            </p>
            <strong>{@observability.gates.pending_reviews} pending</strong>
            <p class="text-xs text-muted-foreground mt-1">
              {@observability.gates.total_reviews} total review gates
            </p>
            <.link
              navigate={~p"/sessions/#{@session.id}/reviews"}
              class="inline-flex items-center gap-1 mt-2 text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary transition cursor-pointer"
            >
              View all <.icon name="hero-arrow-right" class="size-3" />
            </.link>
          </div>
          <div
            id="mission-observability-timeline"
            class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Timeline
            </p>
            <strong>{@observability.timeline.count} events</strong>
            <p class="text-xs text-muted-foreground mt-1">
              {@observability.memory.records} memory · {@observability.proofs.count} proofs · {@observability.hosts_models_tools.invocations} calls
            </p>
          </div>
        </div>

        <div class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Recommendations
          </p>
          <ul id="mission-observability-recommendations" class="space-y-2 list-none p-0 m-0">
            <%= for recommendation <- Enum.take(@observability.recommendations, 3) do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
          Session metrics
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-5">
          <div class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Current funnel stage
            </p>
            <strong>{Analytics.stage_label(@session_metrics.funnel_stage)}</strong>
          </div>
          <div class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              First finding time
            </p>
            <strong>{format_duration(@session_metrics.time_to_first_finding_seconds)}</strong>
          </div>
          <div class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Total findings
            </p>
            <strong>{@session_metrics.total_findings}</strong>
          </div>
          <div class="p-5 rounded-3xl border bg-muted/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Blocked findings
            </p>
            <strong>{@session_metrics.blocked_findings_total}</strong>
          </div>
        </div>
      </div>

      <ShipReadiness.ship_readiness
        verdict={@ship_verdict}
        improvement_loop={@improvement_loop}
        outcome_metrics={@ship_outcome_metrics}
        autonomy_profile={@autonomy_profile}
        outcome_profile={@outcome_profile}
        agent_outcomes={@ship_agent_outcomes}
      />

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Execution brief
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Domain pack</h3>
              <p class="text-sm text-muted-foreground">
                {format_domain_pack(brief_value(@brief, "domain_pack"))}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Occupation</h3>
              <p class="text-sm text-muted-foreground">{brief_value(@brief, "occupation")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Recommended stack</h3>
              <p class="text-sm text-muted-foreground">{brief_value(@brief, "recommended_stack")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Next step</h3>
              <p class="text-sm text-muted-foreground">{brief_value(@brief, "next_step")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Acceptance criteria</h3>
              <ul class="space-y-1 text-sm text-muted-foreground list-none p-0 m-0">
                <%= for item <- brief_list(@brief, "acceptance_criteria") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Compiler</h3>
              <p class="text-sm text-muted-foreground">
                {brief_value(@compiler, "provider")} / {brief_value(@compiler, "model")}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Production boundary
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Risk tier</h3>
              <p class="text-sm text-muted-foreground">
                {boundary_value(@boundary_summary, "risk_tier")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Budget note</h3>
              <p class="text-sm text-muted-foreground">
                {boundary_value(@boundary_summary, "budget_note")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Launch window</h3>
              <p class="text-sm text-muted-foreground">
                {boundary_value(@boundary_summary, "launch_window")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Data summary</h3>
              <p class="text-sm text-muted-foreground">
                {boundary_value(@boundary_summary, "data_summary")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Constraints</h3>
              <ul class="space-y-1 text-sm text-muted-foreground list-none p-0 m-0">
                <%= for item <- boundary_list(@boundary_summary, "constraints") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Compliance</h3>
              <ul class="flex flex-wrap gap-1.5 mt-1">
                <%= for item <- boundary_list(@boundary_summary, "compliance") do %>
                  <li>
                    <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                      {item}
                    </span>
                  </li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-muted-foreground mb-1">Open questions</h3>
              <ul class="space-y-1 text-sm text-muted-foreground list-none p-0 m-0">
                <%= for item <- boundary_list(@boundary_summary, "open_questions") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Workspace context
          </p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>{workspace_status_label(@current_workspace_context)}</span>
            <span>{get_in(@current_workspace_context, ["git", "branch"]) || "no-branch"}</span>
            <span>
              {String.slice(
                get_in(@current_workspace_context, ["git", "head_sha"]) || "unknown",
                0,
                7
              )}
            </span>
          </div>
          <p class="text-sm text-muted-foreground mt-3">
            {@current_workspace_context["summary_text"]}
          </p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>
              {length(@current_workspace_context["instruction_files"] || [])} instructions
            </span>
            <span>{length(@current_workspace_context["key_files"] || [])} key files</span>
          </div>
          <details class="mt-4">
            <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary cursor-pointer select-none">
              View raw workspace JSON
            </summary>
            <pre class="p-4 max-h-96 overflow-auto border rounded-2xl bg-muted/[0.03] text-sm text-[#f2e6c9] font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@current_workspace_context, pretty: true)}</pre>
          </details>
        </div>

        <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
            Relevant memory
          </p>
          <%= if @current_memory_hits == [] do %>
            <p class="text-sm text-muted-foreground mt-3">
              No matching memory has been captured for this task yet.
            </p>
          <% else %>
            <ul class="space-y-3 list-none p-0 m-0 mt-3">
              <%= for hit <- @current_memory_hits do %>
                <li>
                  <strong>{hit.title}</strong>
                  <p class="text-sm text-muted-foreground">{hit.summary}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
          Resume packet
        </p>
        <%= if @current_resume_packet do %>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>{length(@current_resume_packet["unresolved_findings"])} unresolved</span>
            <span>{length(@current_resume_packet["latest_invocations"])} recent runs</span>
            <span>{length(@current_resume_packet["memory_hits"])} memory hits</span>
          </div>
          <details class="mt-4">
            <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary cursor-pointer select-none">
              View resume packet JSON
            </summary>
            <pre class="p-4 max-h-96 overflow-auto border rounded-2xl bg-muted/[0.03] text-sm text-[#f2e6c9] font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@current_resume_packet, pretty: true)}</pre>
          </details>
        <% else %>
          <p class="text-sm text-muted-foreground mt-3">
            Pause a task to capture a durable resume packet.
          </p>
        <% end %>

        <p class="mt-6 pt-6 border-t text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
          Proxy endpoints
        </p>
        <div class="grid grid-cols-2 gap-3 mt-3">
          <a
            href={@proxy_urls.openai_responses}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI responses
          </a>
          <a
            href={@proxy_urls.openai_chat}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI chat
          </a>
          <a
            href={@proxy_urls.openai_completions}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI completions
          </a>
          <a
            href={@proxy_urls.openai_embeddings}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI embeddings
          </a>
          <a
            href={@proxy_urls.openai_models}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI models
          </a>
          <a
            href={@proxy_urls.openai_realtime}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            OpenAI realtime
          </a>
          <a
            href={@proxy_urls.anthropic_messages}
            class="block rounded-xl border bg-muted/[0.03] px-4 py-3 text-sm font-semibold text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            Anthropic messages
          </a>
        </div>
      </div>
    </section>
    """
  end

  defp safe_assign_session(socket, session) do
    assign_session(socket, session)
  rescue
    e ->
      require Logger
      Logger.warning("MissionControlLive assign_session rescued: #{inspect(e)}")

      socket
      |> assign(:session, session)
      |> assign(:workspace, session.workspace)
      |> assign(:page_title, session.title)
      |> assign(
        :active_findings,
        Enum.count(session.findings || [], &(&1.status in ["open", "blocked"]))
      )
      |> assign(
        :active_tasks,
        Enum.count(session.tasks || [], &(&1.status in ["queued", "in_progress"]))
      )
  end

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    {autonomy_profile, outcome_profile, improvement_loop, ship_outcome_metrics,
     ship_agent_outcomes} =
      safe_ship_profile(session)

    assign(socket,
      session: session,
      workspace: session.workspace,
      session_metrics:
        Analytics.session_metrics(session.id) || default_session_metrics(session.id),
      brief: brief,
      boundary_summary: Intent.boundary_summary(brief),
      compiler: compiler,
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      compliance_score: compliance_score(session.findings),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      observability: Observability.session_run(session),
      current_memory_hits: current_memory_hits(session),
      current_workspace_context: Mission.workspace_context(session),
      current_resume_packet: current_resume_packet(session),
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent")),
      proxy_urls: Proxy.endpoint_urls(session),
      autonomy_profile: autonomy_profile,
      outcome_profile: outcome_profile,
      improvement_loop: improvement_loop,
      ship_outcome_metrics: ship_outcome_metrics,
      ship_agent_outcomes: ship_agent_outcomes,
      ship_verdict: ship_verdict(improvement_loop, ship_outcome_metrics)
    )
  end

  # Ship-readiness profile is isolated so a raise in the autonomy/outcome
  # computations can never take down the rest of assign_session.
  defp safe_ship_profile(session) do
    {outcome_metrics, agent_outcomes} = Analytics.session_outcome_data(session.id)

    {
      AutonomyLoop.session_autonomy_profile(session),
      AutonomyLoop.session_outcome_profile(session),
      AutonomyLoop.session_improvement_loop(session),
      outcome_metrics,
      agent_outcomes
    }
  rescue
    e ->
      require Logger

      Logger.warning("MissionControlLive ship profile rescued: #{inspect(e)}")

      default_metrics = %{
        proof_backed_task_coverage_percent: nil,
        deploy_ready_task_rate_percent: nil,
        cost_per_deploy_ready_task_cents: nil,
        risky_intervention_rate_percent: nil,
        resume_success_rate_percent: nil,
        average_time_to_first_deploy_ready_proof_seconds: nil
      }

      improvement = %{
        "bottleneck_summary" => %{"primary" => "none", "recommendation" => nil, "signals" => %{}},
        "recommended_next_step" => nil
      }

      {
        %{"label" => "—", "human_role" => nil, "operator_posture" => nil},
        %{"label" => "—", "status" => nil, "target" => nil},
        improvement,
        default_metrics,
        []
      }
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "paused")) ||
      Enum.find(tasks, &(&1.status == "blocked")) ||
      Enum.find(tasks, &(&1.status == "queued"))
  end

  defp current_memory_hits(session) do
    case current_task(session.tasks) do
      nil ->
        []

      task ->
        session
        |> ControlKeel.Memory.retrieve_for_task(task, findings: session.findings, top_k: 5)
        |> Map.get(:entries, [])
    end
  end

  defp current_resume_packet(session) do
    case current_task(session.tasks) do
      nil ->
        nil

      task ->
        case Mission.resume_packet(task.id) do
          {:ok, packet} -> packet
          _error -> nil
        end
    end
  end

  # Ship-readiness verdict, derived from the session's improvement loop signals.
  defp ship_verdict(improvement_loop, _outcome_metrics) do
    bottleneck = get_in(improvement_loop || %{}, ["bottleneck_summary", "primary"]) || "none"
    signals = get_in(improvement_loop || %{}, ["bottleneck_summary", "signals"]) || %{}
    blocked = signals["blocked_findings"] || 0
    deploy_ready = signals["deploy_ready"] == true

    {label, tone} =
      cond do
        blocked > 0 or bottleneck == "unresolved_findings" ->
          {"Blocked", "blocked"}

        bottleneck == "review_wait" ->
          {"Needs review", "review"}

        bottleneck == "missing_deploy_ready_proof" ->
          {"Needs proof evidence", "proof"}

        bottleneck == "budget_pressure" ->
          {"Budget-constrained", "budget"}

        bottleneck == "none" and deploy_ready and blocked == 0 ->
          {"Ready to ship", "ready"}

        true ->
          {"In progress", "progress"}
      end

    %{label: label, tone: tone}
  end

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp workspace_status_label(%{"available" => true}), do: "available"
  defp workspace_status_label(_context), do: "unavailable"

  defp obs_health_pill_class("red"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp obs_health_pill_class("yellow"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp obs_health_pill_class(_status),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

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

  defp donut_color(score) when score >= 80, do: "#22c55e"
  defp donut_color(score) when score >= 50, do: "#f59e0b"
  defp donut_color(_score), do: "#ef4444"

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
