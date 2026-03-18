defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Mission
  alias ControlKeel.Proxy
  alias ControlKeelWeb.FindingComponents

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Mission not found.")
         |> push_navigate(to: ~p"/")}

      session ->
        if connected?(socket), do: schedule_refresh()

        {:ok,
         socket
         |> assign(:page_title, session.title)
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
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Mission control</p>
          <h1 class="ck-section-title">{@session.title}</h1>
          <p class="ck-lead ck-lead-tight">{@session.objective}</p>
        </div>
        <div class="ck-badge-stack">
          <span class={["ck-pill", "ck-pill-#{@session.risk_tier}"]}>{@session.risk_tier} risk</span>
          <span class="ck-pill ck-pill-neutral">{@workspace.compliance_profile}</span>
        </div>
      </div>

      <div class="ck-stat-grid">
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Primary agent</p>
          <strong>{@agent_label}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Active findings</p>
          <strong>{@active_findings}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Active tasks</p>
          <strong>{@active_tasks}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Budget</p>
          <strong>
            {format_currency(@session.spent_cents)} / {format_currency(@session.budget_cents)}
          </strong>
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
              <p class="ck-note">{brief_value(@brief, "domain_pack")}</p>
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
          <p class="ck-mini-label">Current task context</p>
          <%= if @current_task do %>
            <div class="ck-task-topline">
              <span class={["ck-task-state", "ck-task-state-#{@current_task.status}"]}></span>
              <strong>{@current_task.title}</strong>
            </div>
            <p class="ck-note">{@current_task.validation_gate}</p>
          <% else %>
            <p class="ck-note">No active task context is available yet.</p>
          <% end %>

          <p class="ck-mini-label" style="margin-top: 1.5rem;">Path graph</p>
          <ol class="ck-task-list">
            <%= for task <- @session.tasks do %>
              <li class="ck-task-item">
                <div>
                  <div class="ck-task-topline">
                    <span class={["ck-task-state", "ck-task-state-#{task.status}"]}></span>
                    <strong>{task.title}</strong>
                  </div>
                  <p class="ck-note">{task.validation_gate}</p>
                </div>
                <span class="ck-pill ck-pill-neutral">{task.status}</span>
              </li>
            <% end %>
          </ol>
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
        <div class="ck-finding-list">
          <%= for finding <- @session.findings do %>
            <article class="ck-finding-item">
              <div class="ck-finding-head">
                <h3>{finding.title}</h3>
                <span class={["ck-pill", "ck-pill-#{finding.severity}"]}>{finding.severity}</span>
              </div>
              <p class="ck-note">{finding.plain_message}</p>
              <div class="ck-metric-row">
                <span>{finding.category}</span>
                <span>{finding.rule_id}</span>
                <span>{finding.status}</span>
              </div>
              <div class="ck-action-row">
                <button type="button" class="ck-link" phx-click="view_fix" phx-value-id={finding.id}>
                  View fix
                </button>
                <.link
                  navigate={~p"/findings?#{%{"session_id" => @session.id, "q" => finding.rule_id}}"}
                  class="ck-link"
                >
                  Open in browser
                </.link>
              </div>
            </article>
          <% end %>
        </div>
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

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} -> Enum.find(session.findings, &(&1.id == id))
        _ -> nil
      end

    assign(socket,
      session: session,
      workspace: session.workspace,
      session_metrics:
        Analytics.session_metrics(session.id) || default_session_metrics(session.id),
      brief: brief,
      compiler: compiler,
      current_task: current_task(session.tasks),
      selected_finding: selected_finding,
      selected_fix: maybe_regenerate_fix(selected_finding),
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent")),
      proxy_urls: %{
        openai_responses: Proxy.url(session, :openai, "/v1/responses"),
        openai_chat: Proxy.url(session, :openai, "/v1/chat/completions"),
        openai_realtime: Proxy.realtime_url(session, :openai, "/v1/realtime"),
        anthropic_messages: Proxy.url(session, :anthropic, "/v1/messages")
      }
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) || Enum.find(tasks, &(&1.status == "queued"))
  end

  defp format_currency(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"
  defp brief_value(map, key), do: Map.get(map, key, "Not specified")
  defp brief_list(map, key), do: List.wrap(Map.get(map, key, []))
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
