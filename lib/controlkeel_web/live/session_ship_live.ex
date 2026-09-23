defmodule ControlKeelWeb.SessionShipLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Analytics
  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
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

          SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()
            {:ok, assign_session(socket, session)}
        end
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    {autonomy_profile, outcome_profile, improvement_loop, ship_outcome_metrics,
     ship_agent_outcomes} =
      safe_ship_profile(session)

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(:breadcrumbs, [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      },
      %{label: "Ship", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Ship readiness")
    |> assign(:session, session)
    |> assign(:autonomy_profile, autonomy_profile)
    |> assign(:outcome_profile, outcome_profile)
    |> assign(:improvement_loop, improvement_loop)
    |> assign(:ship_outcome_metrics, ship_outcome_metrics)
    |> assign(:ship_agent_outcomes, ship_agent_outcomes)
    |> assign(:ship_verdict, ship_verdict(improvement_loop, ship_outcome_metrics))
  end

  # Ship-readiness profile is isolated so a raise in the autonomy/outcome
  # computations can never take down the periodic refresh loop.
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

      Logger.warning("SessionShipLive ship profile rescued: #{inspect(e)}")

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

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title
        title="Ship readiness"
        subtitle="Run health, bottleneck coaching, and outcome metrics for this session."
      />

      <div class="flex flex-wrap items-center gap-3">
        <span class={[
          "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em]",
          verdict_badge_class(@ship_verdict.tone)
        ]}>
          {@ship_verdict.label}
        </span>
      </div>

      <p class="text-sm text-muted-foreground mt-4">
        {get_in(@improvement_loop || %{}, ["bottleneck_summary", "recommendation"])}
      </p>
      <p class="text-xs text-muted-foreground mt-1">
        Next: {get_in(@improvement_loop || %{}, ["recommended_next_step"]) || "—"}
      </p>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mt-5">
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Proof-backed tasks
          </p>
          <strong class="block mt-1">
            {format_percent(@ship_outcome_metrics.proof_backed_task_coverage_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Deploy-ready rate
          </p>
          <strong class="block mt-1">
            {format_percent(@ship_outcome_metrics.deploy_ready_task_rate_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Cost / deploy-ready
          </p>
          <strong class="block mt-1">
            {format_cost(@ship_outcome_metrics.cost_per_deploy_ready_task_cents)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            First deploy-ready proof
          </p>
          <strong class="block mt-1">
            {format_duration(@ship_outcome_metrics.average_time_to_first_deploy_ready_proof_seconds)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Risky interventions
          </p>
          <strong class="block mt-1">
            {format_percent(@ship_outcome_metrics.risky_intervention_rate_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Resume success
          </p>
          <strong class="block mt-1">
            {format_percent(@ship_outcome_metrics.resume_success_rate_percent)}
          </strong>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-5">
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Autonomy posture
          </p>
          <p class="text-sm text-foreground">{@autonomy_profile["label"]}</p>
          <p class="text-xs text-muted-foreground mt-1">
            {@autonomy_profile["human_role"]} · {@autonomy_profile["operator_posture"]}
          </p>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Outcome alignment
          </p>
          <p class="text-sm text-foreground">
            {@outcome_profile["label"]} · {@outcome_profile["status"]}
          </p>
          <p class="text-xs text-muted-foreground mt-1 truncate">{@outcome_profile["target"]}</p>
        </div>
      </div>

      <%= if @ship_agent_outcomes != [] do %>
        <div class="mt-5">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Task completion by agent
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <%= for row <- @ship_agent_outcomes do %>
              <div class="rounded-2xl bg-muted p-4">
                <p class="text-sm font-semibold text-foreground">{row.agent}</p>
                <p class="text-xs text-muted-foreground mt-1">
                  {row.completed_tasks}/{row.total_tasks} done · {format_percent(
                    row.completion_rate_percent
                  )} · {row.deploy_ready_tasks} deploy-ready
                </p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp verdict_badge_class("ready"),
    do: "bg-success/15 text-success border-success/30"

  defp verdict_badge_class("blocked"),
    do: "bg-destructive/15 text-destructive border-destructive/30"

  defp verdict_badge_class("progress"),
    do: "bg-info/15 text-info border-info/30"

  defp verdict_badge_class(_),
    do: "bg-warning/15 text-warning border-warning/30"

  defp format_percent(nil), do: "Not enough data"
  defp format_percent(value), do: "#{value}%"

  defp format_cost(nil), do: "Not recorded"
  defp format_cost(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

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
end
