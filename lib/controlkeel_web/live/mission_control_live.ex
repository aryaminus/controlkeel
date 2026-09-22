defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Platform
  alias ControlKeelWeb.FindingComponents
  alias ControlKeelWeb.ShipReadiness

  @refresh_interval_ms 2_000

  @impl true
  def mount(
        %{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug} = params,
        _session,
        socket
      ) do
    current_user = socket.assigns[:current_user]

    case Mission.get_session_context(id) do
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

          check_session_scope(session, org_slug, ws_slug) != :ok ->
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
             |> assign(:selected_finding, nil)
             |> assign(:selected_fix, nil)
             |> safe_assign_session(session)}
        end
    end
  end

  # URL slug agreement only — must run after the session_accessible? gate,
  # which is what guarantees a loaded workspace/org (a nil session never
  # reaches here).
  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
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
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply, socket |> assign_session(session)}
    end
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <-
           Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error -> {:noreply, put_flash(socket, :error, "ControlKeel could not load that fix.")}
    end
  end

  @impl true
  def handle_event("copy_fix_prompt", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.selected_finding,
         %{"agent_prompt" => prompt} = fix <- socket.assigns.selected_fix,
         true <- is_binary(prompt) and prompt != "" do
      emit_autofix_event(:copied, finding, fix)

      {:noreply,
       socket
       |> push_event("copy-to-clipboard", %{text: prompt})
       |> put_flash(:info, "Fix prompt copied to the clipboard.")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_fix", _params, socket) do
    {:noreply, socket |> assign(:selected_finding, nil) |> assign(:selected_fix, nil)}
  end

  @impl true
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply,
           socket
           |> put_flash(:info, "Finding approved.")
           |> safe_assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", params, socket) do
    id = params["id"]

    reason =
      params["reason"]
      |> then(&if is_binary(&1) and String.trim(&1) != "", do: String.trim(&1), else: nil)

    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.reject_finding(finding, reason, actor_opts(socket)) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply,
           socket
           |> put_flash(:info, "Finding rejected.")
           |> safe_assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  @impl true
  def handle_event("generate_proof", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _proof} <- Mission.generate_proof_bundle(task_id),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Proof bundle generated.")
       |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not generate proof bundle.")}
    end
  end

  @impl true
  def handle_event("complete_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, task} <- Mission.complete_task(task_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task completed: #{task.title}.")
       |> refresh_session_after_mutation()}
    else
      {:error, :unresolved_findings, findings} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{length(findings)} unresolved finding(s) must be approved or resolved before marking this task done."
         )}

      {:error, :proof_not_ready, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, :invalid_id} ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not complete that task.")}

      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not complete that task.")}
    end
  end

  @impl true
  def handle_event("pause_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.pause_task(task_id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task paused.")
       |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not pause task.")}
    end
  end

  @impl true
  def handle_event("resume_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.resume_task(task_id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Task resumed.")
       |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not resume task.")}
    end
  end

  defp refresh_session_after_mutation(socket) do
    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        socket

      session ->
        socket |> safe_assign_session(session)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <%= if @launched do %>
        <div class="p-6 rounded-3xl border bg-[var(--ck-success)] text-muted-foreground border-l-4 border-l-[var(--ck-success)]">
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
      <.page_title
        title={@session.title}
        subtitle={@session.objective}
        class="min-w-0 max-w-3xl"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
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
          <div class="flex flex-wrap items-center justify-end gap-3">
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
              navigate={
                ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/reviews"
              }
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

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <.section_title>Audit log</.section_title>
            <p class="mt-1 text-sm text-muted-foreground">
              Export a record of this session's governed activity.
            </p>
            <p :if={@latest_audit_export} class="mt-2 text-xs text-muted-foreground">
              Last export ({@latest_audit_export.format}):
              <code class="font-mono break-all">{@latest_audit_export.checksum}</code>
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2" aria-label="Audit log exports">
            <.link
              :for={format <- ~w(json csv pdf)}
              id={"mission-audit-export-#{format}"}
              href={~p"/observability/sessions/#{@session.id}/audit-log/#{format}"}
              class="rounded-lg border border-border bg-transparent px-2.5 py-1.5 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground transition hover:bg-muted hover:text-foreground"
            >
              {String.upcase(format)}
            </.link>
          </div>
        </div>
      </section>

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

      <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
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

        <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
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

      <div class="p-6 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
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

      <FindingComponents.autofix_panel
        :if={@selected_finding && @selected_fix}
        finding={@selected_finding}
        fix={@selected_fix}
        copy_event="copy_fix_prompt"
        close_event="close_fix"
      />
    </section>
    """
  end

  defp safe_assign_session(socket, session) do
    socket
    |> assign_session(session)
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(session.workspace.id))
  rescue
    e ->
      require Logger
      Logger.warning("MissionControlLive assign_session rescued: #{inspect(e)}")

      socket
      |> assign(:session, session)
      |> assign(:workspace, session.workspace)
      |> assign_session_nav(session)
      |> assign(:page_title, session.title)
      |> assign(
        :active_findings,
        Enum.count(session.findings || [], &(&1.status in ["open", "blocked"]))
      )
      |> assign(
        :active_tasks,
        Enum.count(session.tasks || [], &(&1.status in ["queued", "in_progress"]))
      )
      |> assign(:latest_audit_export, nil)
      |> assign(:task_graph, %{tasks: session.tasks || [], edges: []})
  end

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} -> Enum.find(session.findings, &(&1.id == id))
        _ -> nil
      end

    task_graph = Mission.session_task_graph(session.id)
    task_title_by_id = Map.new(task_graph.tasks, &{&1.id, &1.title})

    {autonomy_profile, outcome_profile, improvement_loop, ship_outcome_metrics,
     ship_agent_outcomes} =
      safe_ship_profile(session)

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
      current_task: current_task(session.tasks),
      selected_finding: selected_finding,
      selected_fix: maybe_regenerate_fix(selected_finding),
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      compliance_score: compliance_score(session.findings),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      latest_audit_export: Platform.list_audit_exports(session.id, 1) |> List.first(),
      observability: Observability.session_run(session),
      current_proof_summary: current_task(session.tasks) |> Mission.proof_summary_for_task(),
      current_workspace_context: Mission.workspace_context(session),
      task_graph: task_graph,
      task_title_by_id: task_title_by_id,
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent")),
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

  defp task_status_label(%{status: "verified"}), do: "verified"
  defp task_status_label(%{status: "done"}), do: "done, unverified"

  defp task_status_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp task_status_label(_task), do: "unknown"

  defp task_status_pill_class("verified"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp task_status_pill_class("done"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp task_status_pill_class(_status),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp obs_health_pill_class("red"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp obs_health_pill_class("yellow"),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp obs_health_pill_class(_status),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp done_unverified?(%{status: "done"}), do: true
  defp done_unverified?(_task), do: false

  defp task_verification_label(_task, %{"verification_status" => "strong"}),
    do: "verification strong"

  defp task_verification_label(_task, %{"verification_status" => "moderate"}),
    do: "verification moderate"

  defp task_verification_label(_task, %{"verification_status" => "weak"}), do: "verification weak"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "strong"}}
       }),
       do: "verification strong"

  defp task_verification_label(
         _task,
         %{bundle: %{"verification_assessment" => %{"status" => "moderate"}}}
       ),
       do: "verification moderate"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "weak"}}
       }),
       do: "verification weak"

  defp task_verification_label(task, _proof_summary),
    do: if(done_unverified?(task), do: "unverified", else: "verification pending")

  defp task_decision_prompts(task) do
    task
    |> Mission.review_gate_status()
    |> Map.get("decision_prompts", [])
    |> Enum.take(2)
  end

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
  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp emit_autofix_event(action, finding, fix) do
    :telemetry.execute(
      [:controlkeel, :autofix, action],
      %{count: 1},
      %{
        finding_id: finding.id,
        session_id: finding.session_id,
        rule_id: finding.rule_id,
        supported: fix["supported"],
        fix_kind: fix["fix_kind"]
      }
    )
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

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> [actor_source: "web", actor_identifier: "web"]
      user -> [actor_source: "web", actor_user_id: user.id, actor_identifier: user.email]
    end
  end

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
