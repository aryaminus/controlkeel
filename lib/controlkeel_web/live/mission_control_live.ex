defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Proxy
  alias ControlKeelWeb.FindingComponents

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Mission not found.")
         |> push_navigate(to: ~p"/")}

      session ->
        if connected?(socket), do: schedule_refresh()

        project_root = socket.endpoint.config(:project_root) || File.cwd!()

        {:ok,
         socket
         |> assign(:page_title, session.title)
         |> assign(:project_root, project_root)
         |> assign(:launched, Map.get(params, "launched") == "1")
         |> assign(:selected_finding, nil)
         |> assign(:selected_fix, nil)
         |> assign_session(session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
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
         {:ok, _updated} <- Mission.approve_finding(finding) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply, socket |> put_flash(:info, "Finding approved.") |> assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.reject_finding(finding) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply, socket |> put_flash(:info, "Finding rejected.") |> assign_session(session)}
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
      {:noreply, socket |> put_flash(:info, "Proof bundle generated.") |> assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not generate proof bundle.")}
    end
  end

  @impl true
  def handle_event("pause_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.pause_task(task_id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply, socket |> put_flash(:info, "Task paused.") |> assign_session(session)}
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
      {:noreply, socket |> put_flash(:info, "Task resumed.") |> assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not resume task.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <%= if @launched do %>
          <div
            class="ck-card"
            style="border-left: 4px solid #22c55e; background: #f0fdf4; margin-bottom: 1.5rem;"
          >
            <div style="display: flex; align-items: flex-start; gap: 1rem;">
              <span style="font-size: 1.5rem; line-height: 1;">✓</span>
              <div>
                <strong style="display: block; margin-bottom: 0.25rem;">
                  You're set — ControlKeel is governing this session
                </strong>
                <p class="ck-note" style="margin: 0 0 0.75rem;">
                  Attach your preferred client to start intercepting agent actions. OpenCode is the fastest MCP-plus-instructions path:
                  <code style="font-family: monospace; background: #dcfce7; padding: 0.1rem 0.3rem; border-radius: 3px;">
                    controlkeel attach opencode
                  </code>
                </p>
                <p class="ck-note" style="margin: 0;">
                  Or validate content directly via the
                  <a href="/policies" style="text-decoration: underline;">Policy Studio</a>
                  or REST API at <code style="font-family: monospace; background: #dcfce7; padding: 0.1rem 0.3rem; border-radius: 3px;">POST /api/v1/validate</code>.
                </p>
              </div>
            </div>
          </div>
        <% end %>
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Mission control</p>
            <h1 class="ck-section-title">{@session.title}</h1>
            <p class="ck-lead ck-lead-tight">{@session.objective}</p>
          </div>
          <div class="ck-badge-stack">
            <span class={["ck-pill", "ck-pill-#{@session.risk_tier}"]}>
              {@session.risk_tier} risk
            </span>
            <span class="ck-pill ck-pill-neutral">{@workspace.compliance_profile}</span>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Primary agent</p>
            <strong>{@agent_label}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Needs review</p>
            <strong>{@active_findings} finding{if @active_findings != 1, do: "s"}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Compliance score</p>
            <div style="display: flex; align-items: center; gap: 0.75rem;">
              <svg
                viewBox="0 0 36 36"
                width="48"
                height="48"
                style="flex-shrink: 0; transform: rotate(-90deg);"
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
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Budget spent</p>
            <strong>
              {format_currency(@session.spent_cents)} / {format_currency(@session.budget_cents)}
            </strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Proof bundles</p>
            <strong>{map_size(@latest_proofs)}</strong>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Session metrics</p>
          <div class="ck-stat-grid">
            <div class="ck-stat-card">
              <p class="ck-mini-label">Current funnel stage</p>
              <strong>{Analytics.stage_label(@session_metrics.funnel_stage)}</strong>
            </div>
            <div class="ck-stat-card">
              <p class="ck-mini-label">First finding time</p>
              <strong>{format_duration(@session_metrics.time_to_first_finding_seconds)}</strong>
            </div>
            <div class="ck-stat-card">
              <p class="ck-mini-label">Total findings</p>
              <strong>{@session_metrics.total_findings}</strong>
            </div>
            <div class="ck-stat-card">
              <p class="ck-mini-label">Blocked findings</p>
              <strong>{@session_metrics.blocked_findings_total}</strong>
            </div>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Execution brief</p>
            <div class="ck-brief-grid">
              <div>
                <h3>Domain pack</h3>
                <p class="ck-note">{format_domain_pack(brief_value(@brief, "domain_pack"))}</p>
              </div>
              <div>
                <h3>Occupation</h3>
                <p class="ck-note">{brief_value(@brief, "occupation")}</p>
              </div>
              <div>
                <h3>Recommended stack</h3>
                <p class="ck-note">{brief_value(@brief, "recommended_stack")}</p>
              </div>
              <div>
                <h3>Next step</h3>
                <p class="ck-note">{brief_value(@brief, "next_step")}</p>
              </div>
              <div>
                <h3>Acceptance criteria</h3>
                <ul class="ck-mini-list">
                  <%= for item <- brief_list(@brief, "acceptance_criteria") do %>
                    <li>{item}</li>
                  <% end %>
                </ul>
              </div>
              <div>
                <h3>Open questions</h3>
                <ul class="ck-mini-list">
                  <%= for item <- brief_list(@brief, "open_questions") do %>
                    <li>{item}</li>
                  <% end %>
                </ul>
              </div>
              <div>
                <h3>Compliance</h3>
                <ul class="ck-tag-list">
                  <%= for item <- brief_list(@brief, "compliance") do %>
                    <li><span class="ck-tag">{item}</span></li>
                  <% end %>
                </ul>
              </div>
              <div>
                <h3>Compiler</h3>
                <p class="ck-note">
                  {brief_value(@compiler, "provider")} / {brief_value(@compiler, "model")}
                </p>
              </div>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Production boundary</p>
            <div class="ck-brief-grid">
              <div>
                <h3>Risk tier</h3>
                <p class="ck-note">{boundary_value(@boundary_summary, "risk_tier")}</p>
              </div>
              <div>
                <h3>Budget note</h3>
                <p class="ck-note">{boundary_value(@boundary_summary, "budget_note")}</p>
              </div>
              <div>
                <h3>Launch window</h3>
                <p class="ck-note">{boundary_value(@boundary_summary, "launch_window")}</p>
              </div>
              <div>
                <h3>Next step</h3>
                <p class="ck-note">{boundary_value(@boundary_summary, "next_step")}</p>
              </div>
              <div>
                <h3>Data summary</h3>
                <p class="ck-note">{boundary_value(@boundary_summary, "data_summary")}</p>
              </div>
              <div>
                <h3>Constraints</h3>
                <ul class="ck-mini-list">
                  <%= for item <- boundary_list(@boundary_summary, "constraints") do %>
                    <li>{item}</li>
                  <% end %>
                </ul>
              </div>
              <div>
                <h3>Compliance</h3>
                <ul class="ck-tag-list">
                  <%= for item <- boundary_list(@boundary_summary, "compliance") do %>
                    <li><span class="ck-tag">{item}</span></li>
                  <% end %>
                </ul>
              </div>
              <div>
                <h3>Open questions</h3>
                <ul class="ck-mini-list">
                  <%= for item <- boundary_list(@boundary_summary, "open_questions") do %>
                    <li>{item}</li>
                  <% end %>
                </ul>
              </div>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Current task context</p>
            <%= if @current_task do %>
              <div class="ck-task-topline">
                <span class={["ck-task-state", "ck-task-state-#{@current_task.status}"]}></span>
                <strong>{@current_task.title}</strong>
                <span class={task_status_pill_class(@current_task.status)}>
                  {task_status_label(@current_task)}
                </span>
              </div>
              <p class="ck-note">{@current_task.validation_gate}</p>
              <div class="ck-action-row" style="margin-top: 0.75rem;">
                <button
                  id={"current-task-generate-proof-#{@current_task.id}"}
                  type="button"
                  class="ck-link"
                  phx-click="generate_proof"
                  phx-value-id={@current_task.id}
                >
                  Generate proof
                </button>
                <button
                  :if={@current_task.status in ["queued", "in_progress", "blocked"]}
                  id={"current-task-pause-#{@current_task.id}"}
                  type="button"
                  class="ck-link"
                  phx-click="pause_task"
                  phx-value-id={@current_task.id}
                >
                  Pause
                </button>
                <button
                  :if={@current_task.status == "paused"}
                  id={"current-task-resume-#{@current_task.id}"}
                  type="button"
                  class="ck-link"
                  phx-click="resume_task"
                  phx-value-id={@current_task.id}
                >
                  Resume
                </button>
                <.link
                  :if={Map.get(@latest_proofs, @current_task.id)}
                  navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, @current_task.id).id}"}
                  class="ck-link"
                >
                  View proof
                </.link>
              </div>
              <%= if @current_proof_summary do %>
                <div class="ck-inline-stats" style="margin-top: 0.75rem;">
                  <span>v{@current_proof_summary["version"]}</span>
                  <span>risk {@current_proof_summary["risk_score"]}</span>
                  <span>{task_verification_label(@current_task, @current_proof_summary)}</span>
                  <span>
                    {if @current_proof_summary["deploy_ready"],
                      do: "deploy ready",
                      else: "review required"}
                  </span>
                </div>
              <% else %>
                <p :if={done_unverified?(@current_task)} class="ck-note" style="margin-top: 0.75rem;">
                  Execution finished, but CK has not verified this task yet. Add checks or regenerate proof.
                </p>
              <% end %>
            <% else %>
              <p class="ck-note">No active task context is available yet.</p>
            <% end %>

            <p class="ck-mini-label" style="margin-top: 1.5rem;">Task dependencies</p>
            <%= if @task_graph.edges == [] do %>
              <p class="ck-note" id="mission-task-deps-empty">
                No dependency edges are recorded yet. When tasks include architecture, feature, and release tracks, edges appear here. The checklist below stays ordered by position.
              </p>
            <% else %>
              <ul class="ck-mini-list" id="mission-task-edges" style="margin-bottom: 1rem;">
                <%= for edge <- @task_graph.edges do %>
                  <li>
                    {Map.get(@task_title_by_id, edge.from_task_id, "Task #{edge.from_task_id}")}
                    <span class="ck-note"> → </span>
                    {Map.get(@task_title_by_id, edge.to_task_id, "Task #{edge.to_task_id}")}
                    <span
                      class="ck-pill ck-pill-neutral"
                      style="font-size: 0.65rem; margin-left: 0.35rem;"
                    >
                      {edge.dependency_type}
                    </span>
                  </li>
                <% end %>
              </ul>
              <p class="ck-mini-label">Ready (dependencies satisfied)</p>
              <p class="ck-note" id="mission-task-ready">
                <%= if @task_graph.ready_task_ids == [] do %>
                  No tasks are ready to advance right now.
                <% else %>
                  {Enum.map_join(@task_graph.ready_task_ids, ", ", fn id ->
                    Map.get(@task_title_by_id, id, "Task #{id}")
                  end)}
                <% end %>
              </p>
            <% end %>

            <p class="ck-mini-label" style="margin-top: 1.5rem;">Task checklist</p>
            <ol class="ck-task-list" id="mission-task-checklist">
              <%= for task <- @session.tasks do %>
                <li class="ck-task-item">
                  <div>
                    <div class="ck-task-topline">
                      <span class={["ck-task-state", "ck-task-state-#{task.status}"]}></span>
                      <strong>{task.title}</strong>
                      <span class={task_status_pill_class(task.status)}>
                        {task_status_label(task)}
                      </span>
                    </div>
                    <p class="ck-note">{task.validation_gate}</p>
                    <%= if task.rollback_boundary do %>
                      <p
                        class="ck-note"
                        style="color: var(--ck-color-muted); font-size: 0.75rem; margin-top: 0.15rem;"
                      >
                        Rollback: {task.rollback_boundary}
                      </p>
                    <% end %>
                    <%= if task.status == "in_progress" and @active_findings > 0 do %>
                      <p
                        class="ck-note"
                        style="color: var(--ck-color-warn, #d97706); margin-top: 0.25rem;"
                      >
                        {@active_findings} unresolved finding{if @active_findings != 1, do: "s"} — review before marking done
                      </p>
                    <% end %>
                  </div>
                  <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 0.25rem;">
                    <span class={task_status_pill_class(task.status)}>{task_status_label(task)}</span>
                    <%= if task.confidence_score do %>
                      <span class="ck-pill ck-pill-neutral" style="font-size: 0.7rem;">
                        {trunc(task.confidence_score * 100)}% confidence
                      </span>
                    <% end %>
                    <span
                      :if={Map.get(@latest_proofs, task.id)}
                      class="ck-note"
                      style="font-size: 0.75rem;"
                    >
                      {task_verification_label(task, Map.get(@latest_proofs, task.id))}
                    </span>
                    <span
                      :if={done_unverified?(task) and is_nil(Map.get(@latest_proofs, task.id))}
                      class="ck-note"
                      style="font-size: 0.75rem;"
                    >
                      needs verification evidence
                    </span>
                    <%= if Map.get(@latest_proofs, task.id) do %>
                      <.link
                        navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, task.id).id}"}
                        class="ck-link"
                      >
                        View proof
                      </.link>
                    <% end %>
                    <button
                      id={"task-generate-proof-#{task.id}"}
                      type="button"
                      class="ck-link"
                      phx-click="generate_proof"
                      phx-value-id={task.id}
                    >
                      Generate proof
                    </button>
                    <button
                      :if={task.status in ["queued", "in_progress", "blocked"]}
                      id={"task-pause-#{task.id}"}
                      type="button"
                      class="ck-link"
                      phx-click="pause_task"
                      phx-value-id={task.id}
                    >
                      Pause
                    </button>
                    <button
                      :if={task.status == "paused"}
                      id={"task-resume-#{task.id}"}
                      type="button"
                      class="ck-link"
                      phx-click="resume_task"
                      phx-value-id={task.id}
                    >
                      Resume
                    </button>
                  </div>
                </li>
              <% end %>
            </ol>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Workspace context</p>
            <div class="ck-inline-stats">
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
            <p class="ck-note" style="margin-top: 1rem;">
              {@current_workspace_context["summary_text"]}
            </p>
            <div class="ck-inline-stats" style="margin-top: 0.75rem;">
              <span>
                {length(@current_workspace_context["instruction_files"] || [])} instructions
              </span>
              <span>{length(@current_workspace_context["key_files"] || [])} key files</span>
            </div>
            <details style="margin-top: 1rem;">
              <summary class="ck-link">View raw workspace JSON</summary>
              <pre class="ck-code-block" style="margin-top: 1rem;">{Jason.encode!(@current_workspace_context, pretty: true)}</pre>
            </details>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Relevant memory</p>
            <%= if @current_memory_hits == [] do %>
              <p class="ck-note">No matching memory has been captured for this task yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for hit <- @current_memory_hits do %>
                  <li>
                    <strong>{hit.title}</strong>
                    <p class="ck-note">{hit.summary}</p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Recent transcript</p>
            <div class="ck-inline-stats">
              <span>{@current_transcript_summary["total_events"] || 0} events</span>
              <span>{length(@current_recent_events)} recent</span>
            </div>
            <%= if @current_recent_events == [] do %>
              <p class="ck-note" style="margin-top: 1rem;">No transcript events recorded yet.</p>
            <% else %>
              <ul class="ck-mini-list" style="margin-top: 1rem;">
                <%= for event <- @current_recent_events do %>
                  <li>
                    <strong>{event["summary"]}</strong>
                    <p class="ck-note">
                      {event["event_type"]} • {event["actor"]} • {event_timestamp(
                        event["inserted_at"]
                      )}
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
            <details style="margin-top: 1rem;">
              <summary class="ck-link">View transcript summary JSON</summary>
              <pre class="ck-code-block" style="margin-top: 1rem;">{Jason.encode!(@current_transcript_summary, pretty: true)}</pre>
            </details>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Resume packet</p>
            <%= if @current_resume_packet do %>
              <div class="ck-inline-stats">
                <span>{length(@current_resume_packet["unresolved_findings"])} unresolved</span>
                <span>{length(@current_resume_packet["latest_invocations"])} recent runs</span>
                <span>{length(@current_resume_packet["memory_hits"])} memory hits</span>
              </div>
              <pre class="ck-code-block" style="margin-top: 1rem;">{Jason.encode!(@current_resume_packet, pretty: true)}</pre>
            <% else %>
              <p class="ck-note">Pause a task to capture a durable resume packet.</p>
            <% end %>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Proxy endpoints</p>
          <div class="ck-brief-grid">
            <div>
              <h3>OpenAI responses</h3>
              <p class="ck-note">{@proxy_urls.openai_responses}</p>
            </div>
            <div>
              <h3>OpenAI chat</h3>
              <p class="ck-note">{@proxy_urls.openai_chat}</p>
            </div>
            <div>
              <h3>OpenAI completions</h3>
              <p class="ck-note">{@proxy_urls.openai_completions}</p>
            </div>
            <div>
              <h3>OpenAI embeddings</h3>
              <p class="ck-note">{@proxy_urls.openai_embeddings}</p>
            </div>
            <div>
              <h3>OpenAI models</h3>
              <p class="ck-note">{@proxy_urls.openai_models}</p>
            </div>
            <div>
              <h3>OpenAI realtime</h3>
              <p class="ck-note">{@proxy_urls.openai_realtime}</p>
            </div>
            <div>
              <h3>Anthropic messages</h3>
              <p class="ck-note">{@proxy_urls.anthropic_messages}</p>
            </div>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Findings feed</p>
          <%= if @session.findings == [] do %>
            <p class="ck-note">No findings yet. ControlKeel is monitoring every agent action.</p>
          <% else %>
            <div class="ck-finding-list">
              <%= for finding <- @session.findings do %>
                <article class="ck-finding-item">
                  <div class="ck-finding-head">
                    <h3>{finding.title}</h3>
                    <div style="display: flex; gap: 0.5rem; align-items: center;">
                      <span class={["ck-pill", "ck-pill-#{finding.severity}"]}>
                        {finding.severity}
                      </span>
                      <span class="ck-pill ck-pill-neutral">{finding.status}</span>
                    </div>
                  </div>
                  <p class="ck-note">{finding.plain_message}</p>
                  <p class="ck-note" style="font-size: 0.8rem; color: var(--ck-color-muted, #64748b);">
                    {Mission.finding_human_gate_hint(finding)}
                  </p>
                  <div class="ck-metric-row">
                    <span>{finding.category}</span>
                    <span>{finding.rule_id}</span>
                  </div>
                  <div class="ck-action-row">
                    <button
                      type="button"
                      class="ck-link"
                      phx-click="view_fix"
                      phx-value-id={finding.id}
                    >
                      View fix
                    </button>
                    <%= if finding.status in ["open", "blocked"] do %>
                      <button
                        type="button"
                        class="ck-link"
                        phx-click="approve_finding"
                        phx-value-id={finding.id}
                      >
                        Approve
                      </button>
                      <button
                        type="button"
                        class="ck-link"
                        phx-click="reject_finding"
                        phx-value-id={finding.id}
                      >
                        Reject
                      </button>
                    <% end %>
                    <.link
                      navigate={
                        ~p"/findings?#{%{"session_id" => @session.id, "q" => finding.rule_id}}"
                      }
                      class="ck-link"
                    >
                      Open in browser
                    </.link>
                  </div>
                </article>
              <% end %>
            </div>
          <% end %>
        </div>

        <FindingComponents.autofix_panel
          :if={@selected_finding && @selected_fix}
          finding={@selected_finding}
          fix={@selected_fix}
          copy_event="copy_fix_prompt"
          close_event="close_fix"
        />
      </section>
    </Layouts.app>
    """
  end

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    project_root =
      socket.assigns[:project_root] || socket.endpoint.config(:project_root) || File.cwd!()

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} -> Enum.find(session.findings, &(&1.id == id))
        _ -> nil
      end

    task_graph = Mission.session_task_graph(session.id)
    task_title_by_id = Map.new(task_graph.tasks, &{&1.id, &1.title})

    assign(socket,
      session: session,
      workspace: session.workspace,
      session_metrics:
        Analytics.session_metrics(session.id) || default_session_metrics(session.id),
      brief: brief,
      boundary_summary: Intent.boundary_summary(brief, project_root: project_root),
      compiler: compiler,
      current_task: current_task(session.tasks),
      selected_finding: selected_finding,
      selected_fix: maybe_regenerate_fix(selected_finding),
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      compliance_score: compliance_score(session.findings),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      current_proof_summary: current_task(session.tasks) |> Mission.proof_summary_for_task(),
      current_memory_hits: current_memory_hits(session),
      current_workspace_context: Mission.workspace_context(session),
      current_recent_events: Mission.list_session_events(session.id),
      current_transcript_summary: Mission.transcript_summary(session.id),
      current_resume_packet: current_resume_packet(session),
      task_graph: task_graph,
      task_title_by_id: task_title_by_id,
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent")),
      proxy_urls: Proxy.endpoint_urls(session)
    )
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

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  defp workspace_status_label(%{"available" => true}), do: "available"
  defp workspace_status_label(_context), do: "unavailable"

  defp task_status_label(%{status: "verified"}), do: "verified"
  defp task_status_label(%{status: "done"}), do: "done, unverified"

  defp task_status_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp task_status_label(_task), do: "unknown"

  defp task_status_pill_class("verified"), do: "ck-pill ck-pill-low"
  defp task_status_pill_class("done"), do: "ck-pill ck-pill-warning"
  defp task_status_pill_class(_status), do: "ck-pill ck-pill-neutral"

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

  defp format_currency(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"
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
