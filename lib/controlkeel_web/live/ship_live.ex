defmodule ControlKeelWeb.ShipLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics

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
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Ship dashboard</p>
          <h1 class="ck-section-title">Track install-to-first-finding momentum</h1>
          <p class="ck-lead ck-lead-tight">
            Measure the governed funnel, spot where sessions stall, and verify that findings are arriving fast enough to matter.
          </p>
        </div>
        <a href={~p"/"} class="ck-link">Back home</a>
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
      </div>

      <div class="ck-grid ck-grid-dashboard">
        <div class="ck-card">
          <p class="ck-mini-label">Funnel conversion</p>
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
      </div>
    </section>
    """
  end

  defp assign_metrics(socket) do
    assign(socket,
      summary: Analytics.funnel_summary(),
      recent_sessions: Analytics.recent_ship_sessions()
    )
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
end
