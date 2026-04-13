defmodule ControlKeelWeb.ShipLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:page_title, "Ship Metrics")
     |> assign_metrics()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()
    {:noreply, assign_metrics(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Proof console</p>
            <h1 class="ck-section-title">Track governed momentum and delivery evidence</h1>
            <p class="ck-lead ck-lead-tight">
              Mission Control, proofs, ship metrics, and benchmarks form one control loop. Use this dashboard as ControlKeel's stewardship surface for funnel speed, deploy-readiness, governance effectiveness, and benchmark evidence.
            </p>
          </div>
          <div class="ck-action-row">
            <a href={~p"/proofs"} class="ck-link">Open proof browser</a>
            <a href={~p"/benchmarks"} class="ck-link">Open benchmarks</a>
            <a href={~p"/"} class="ck-link">Back home</a>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Average first finding</p>
            <strong>{format_duration(@summary.average_time_to_first_finding_seconds)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Median first finding</p>
            <strong>{format_duration(@summary.median_time_to_first_finding_seconds)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Avg findings / session</p>
            <strong>{format_average(@summary.average_findings_per_session)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Recent sessions</p>
            <strong>{@summary.recent_session_count}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Explicit outcomes</p>
            <strong>{@improvement_summary["explicit_outcome_sessions"]}</strong>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Autonomy and outcomes</p>
            <div class="ck-finding-list">
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Autonomy mix</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {@improvement_summary["long_running_sessions"]} long-running
                  </span>
                </div>
                <p class="ck-note">
                  {format_mix(@improvement_summary["autonomy_mix"])}
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Goal shape</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {@improvement_summary["explicit_outcome_sessions"]} explicit
                  </span>
                </div>
                <p class="ck-note">
                  {format_mix(@improvement_summary["goal_type_mix"])}
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Recommended focus</h3>
                </div>
                <p class="ck-note">{@improvement_summary["recommended_focus"]}</p>
              </article>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Proof and deploy-readiness</p>
            <div class="ck-finding-list">
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Proof-backed completed tasks</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(@summary.outcome_metrics.proof_backed_task_coverage_percent)}
                  </span>
                </div>
                <p class="ck-note">
                  Done or verified tasks with at least one immutable proof bundle.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Deploy-ready task rate</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(@summary.outcome_metrics.deploy_ready_task_rate_percent)}
                  </span>
                </div>
                <p class="ck-note">Latest proof bundle says the completed task is ready to ship.</p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Cost / deploy-ready task</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_currency(@summary.outcome_metrics.cost_per_deploy_ready_task_cents)}
                  </span>
                </div>
                <p class="ck-note">
                  Average invocation spend attached to tasks that reached deploy-ready proof.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>First deploy-ready proof</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_duration(
                      @summary.outcome_metrics.average_time_to_first_deploy_ready_proof_seconds
                    )}
                  </span>
                </div>
                <p class="ck-note">
                  Average time from session start to the first deploy-ready proof bundle.
                </p>
              </article>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Funnel speed</p>
            <div class="ck-finding-list">
              <%= for step <- @summary.steps do %>
                <article class="ck-finding-item">
                  <div class="ck-finding-head">
                    <h3>{Analytics.stage_label(step.step)}</h3>
                    <span class="ck-pill ck-pill-neutral">{step.count} sessions</span>
                  </div>
                  <p class="ck-note">
                    Conversion: {format_percent(step.conversion_percent)}
                  </p>
                </article>
              <% end %>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Governance effectiveness</p>
            <div class="ck-finding-list">
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Risky intervention rate</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(@summary.outcome_metrics.risky_intervention_rate_percent)}
                  </span>
                </div>
                <p class="ck-note">
                  High and critical findings that ended blocked or escalated instead of silently passing.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Resume success</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(@summary.outcome_metrics.resume_success_rate_percent)}
                  </span>
                </div>
                <p class="ck-note">
                  Tasks resumed from a checkpoint that still ended in a governed completed state.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Proof console loop</h3>
                  <a href={~p"/proofs"} class="ck-link">Open proofs</a>
                </div>
                <p class="ck-note">
                  Mission Control, Proof Browser, Ship Dashboard, and Benchmarks stay tied together as one governed delivery loop.
                </p>
              </article>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Benchmark evidence</p>
            <div class="ck-finding-list">
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Persisted benchmark runs</h3>
                  <span class="ck-pill ck-pill-neutral">{@benchmark_summary.total_runs}</span>
                </div>
                <p class="ck-note">
                  {@benchmark_summary.total_suites} suites with governed catch-rate evidence.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Average catch rate</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(maybe_round_percent(@benchmark_summary.average_catch_rate))}
                  </span>
                </div>
                <p class="ck-note">
                  Comparative evidence from persisted benchmark runs, not a marketing estimate.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Average overhead</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {format_percent(maybe_round_percent(@benchmark_summary.average_overhead_percent))}
                  </span>
                </div>
                <p class="ck-note">
                  Overhead observed in governed benchmark runs.
                </p>
              </article>
              <article class="ck-finding-item">
                <div class="ck-finding-head">
                  <h3>Benchmarks</h3>
                  <a href={~p"/benchmarks"} class="ck-link">Open benchmarks</a>
                </div>
                <p class="ck-note">
                  Compare governed outcomes and catch-rate evidence against persisted benchmark runs.
                </p>
              </article>
            </div>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Recent governed sessions</p>
            <div class="ck-table-wrap">
              <.table id="ship-sessions" rows={@recent_sessions}>
                <:col :let={session} label="Mission">
                  <div>
                    <.link navigate={~p"/missions/#{session.session_id}"} class="ck-link">
                      {session.title}
                    </.link>
                    <p class="ck-note">{session.workspace_name || "No workspace context"}</p>
                  </div>
                </:col>
                <:col :let={session} label="Stage">
                  {Analytics.stage_label(session.funnel_stage)}
                </:col>
                <:col :let={session} label="Autonomy">
                  {session.autonomy_mode}
                </:col>
                <:col :let={session} label="Outcome">
                  {session.goal_type}
                </:col>
                <:col :let={session} label="First finding">
                  {format_duration(session.time_to_first_finding_seconds)}
                </:col>
                <:col :let={session} label="Findings">
                  <div>
                    <strong>{session.total_findings}</strong>
                    <p class="ck-note">{session.blocked_findings_total} blocked</p>
                  </div>
                </:col>
              </.table>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Task completion by agent</p>
            <div class="ck-table-wrap">
              <.table id="ship-agent-outcomes" rows={@summary.agent_outcomes}>
                <:col :let={row} label="Agent">
                  {row.agent}
                </:col>
                <:col :let={row} label="Completed">
                  <div>
                    <strong>{row.completed_tasks}</strong>
                    <p class="ck-note">{row.total_tasks} total tasks</p>
                  </div>
                </:col>
                <:col :let={row} label="Verified">
                  {Map.get(row, :verified_tasks, 0)}
                </:col>
                <:col :let={row} label="Completion rate">
                  {format_percent(row.completion_rate_percent)}
                </:col>
                <:col :let={row} label="Deploy-ready">
                  {row.deploy_ready_tasks}
                </:col>
              </.table>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp assign_metrics(socket) do
    detailed_sessions = Mission.list_recent_sessions(10)

    assign(socket,
      benchmark_summary: Benchmark.benchmark_summary(),
      summary: Analytics.funnel_summary(),
      improvement_summary: AutonomyLoop.workspace_improvement_summary(detailed_sessions),
      recent_sessions: recent_sessions_with_profiles(detailed_sessions)
    )
  end

  defp recent_sessions_with_profiles(detailed_sessions) do
    rows_by_session =
      Analytics.recent_ship_sessions()
      |> Map.new(fn row -> {row.session_id, row} end)

    detailed_sessions
    |> Enum.map(fn session ->
      row = Map.get(rows_by_session, session.id, %{})
      autonomy = AutonomyLoop.session_autonomy_profile(session)
      outcome = AutonomyLoop.session_outcome_profile(session)

      Map.merge(row, %{
        autonomy_mode: autonomy["label"],
        goal_type: outcome["label"]
      })
    end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp format_average(nil), do: "0.0"
  defp format_average(value) when is_integer(value), do: Integer.to_string(value)
  defp format_average(value), do: :erlang.float_to_binary(value, decimals: 1)

  defp format_percent(nil), do: "Not enough data"
  defp format_percent(value), do: "#{value}%"

  defp maybe_round_percent(nil), do: nil
  defp maybe_round_percent(value), do: Float.round(value, 1)

  defp format_currency(nil), do: "Not recorded"
  defp format_currency(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp format_mix(mix) when map_size(mix) == 0, do: "No governed sessions recorded yet."

  defp format_mix(mix) do
    mix
    |> Enum.sort_by(fn {label, count} -> {-count, label} end)
    |> Enum.map_join(", ", fn {label, count} -> "#{label}: #{count}" end)
  end
end
