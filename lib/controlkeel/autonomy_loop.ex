defmodule ControlKeel.AutonomyLoop do
  @moduledoc false

  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.SecurityWorkflow

  @feedback_loop ["run", "observe", "evaluate", "improve", "rerun"]
  @autonomy_modes ["advise", "supervised_execute", "guarded_autonomy", "long_running_autonomy"]

  def autonomy_modes, do: @autonomy_modes
  def feedback_loop, do: @feedback_loop

  def session_autonomy_profile(%Session{} = session) do
    mode = autonomy_mode(session)

    %{
      "mode" => mode,
      "label" => autonomy_label(mode),
      "long_running" => mode == "long_running_autonomy",
      "human_role" => human_role(mode),
      "operator_posture" => operator_posture(mode),
      "reason" => autonomy_reason(session, mode)
    }
  end

  def session_outcome_profile(%Session{} = session) do
    metadata = session.metadata || %{}

    explicit_target? =
      present?(metadata["outcome_target"]) or present?(metadata["outcome_metric"])

    goal_type = if explicit_target?, do: "kpi", else: "delivery"

    %{
      "goal_type" => goal_type,
      "label" => goal_label(goal_type),
      "target" => metadata["outcome_target"] || session.objective,
      "metric" => metadata["outcome_metric"] || default_metric(session),
      "window" => metadata["outcome_window"] || default_window(goal_type),
      "status" => if(explicit_target?, do: "explicit", else: "implicit")
    }
  end

  def session_improvement_loop(%Session{} = session) do
    current_task = current_task(session)
    trace_packet = trace_packet(session, current_task)

    failure_clusters =
      case Mission.failure_mode_clusters(session.id, session_limit: 5, same_domain_only: true) do
        {:ok, packet} -> packet
        _ -> nil
      end

    suites =
      Benchmark.list_suites(domain_pack: get_in(session.execution_brief || %{}, ["domain_pack"]))

    latest_proof = current_task && Mission.proof_summary_for_task(current_task)
    eval_candidates = get_in(trace_packet || %{}, ["eval_candidates"]) || []
    trace_summary = get_in(trace_packet || %{}, ["trace_summary"]) || %{}
    cluster_count = get_in(failure_clusters || %{}, ["cluster_count"]) || 0

    %{
      "loop" => @feedback_loop,
      "current_task_id" => current_task && current_task.id,
      "current_task_title" => current_task && current_task.title,
      "trace_packet_available" => is_map(trace_packet),
      "trace_signals" => %{
        "invocations" => trace_summary["invocations"] || 0,
        "reviews" => trace_summary["reviews"] || 0,
        "findings" => trace_summary["findings"] || 0
      },
      "eval_candidate_count" => length(eval_candidates),
      "failure_cluster_count" => cluster_count,
      "benchmark_suite_count" => length(suites),
      "benchmark_suite_slugs" => Enum.map(suites, & &1.slug) |> Enum.take(3),
      "deploy_ready" => get_in(latest_proof || %{}, ["deploy_ready"]) == true,
      "recommended_next_step" =>
        recommended_next_step(current_task, trace_packet, cluster_count, latest_proof)
    }
  end

  def workspace_improvement_summary(sessions) when is_list(sessions) do
    autonomy_profiles = Enum.map(sessions, &session_autonomy_profile/1)
    outcome_profiles = Enum.map(sessions, &session_outcome_profile/1)

    %{
      "recent_session_count" => length(sessions),
      "autonomy_mix" => Enum.frequencies_by(autonomy_profiles, & &1["mode"]),
      "goal_type_mix" => Enum.frequencies_by(outcome_profiles, & &1["goal_type"]),
      "long_running_sessions" =>
        Enum.count(autonomy_profiles, &(&1["mode"] == "long_running_autonomy")),
      "explicit_outcome_sessions" => Enum.count(outcome_profiles, &(&1["status"] == "explicit")),
      "improvement_ready_sessions" => Enum.count(sessions, &improvement_ready?/1),
      "recommended_focus" =>
        recommended_workspace_focus(autonomy_profiles, outcome_profiles, sessions)
    }
  end

  defp autonomy_mode(%Session{} = session) do
    metadata = session.metadata || %{}
    brief = session.execution_brief || %{}
    explicit_mode = metadata["autonomy_mode"] || brief["autonomy_mode"]

    cond do
      explicit_mode in @autonomy_modes ->
        explicit_mode

      long_running_session?(session) ->
        "long_running_autonomy"

      supervised_session?(session) ->
        "supervised_execute"

      advise_only_session?(session) ->
        "advise"

      true ->
        "guarded_autonomy"
    end
  end

  defp advise_only_session?(%Session{} = session) do
    session.status == "planned" and Enum.empty?(assoc_list(session.tasks))
  end

  defp supervised_session?(%Session{} = session) do
    brief = session.execution_brief || %{}
    constraints = get_in(brief, ["constraints"]) || []
    cyber_mode = SecurityWorkflow.session_cyber_access_mode(session)

    session.risk_tier in ["high", "critical"] or
      cyber_mode == "verified_research" or
      Enum.any?(constraints, &String.contains?(String.downcase(to_string(&1)), "approval"))
  end

  defp long_running_session?(%Session{} = session) do
    metadata = session.metadata || %{}

    present?(metadata["outcome_target"]) or
      present?(metadata["outcome_metric"]) or
      length(assoc_list(session.tasks)) >= 4
  end

  defp autonomy_label("advise"), do: "Advise"
  defp autonomy_label("supervised_execute"), do: "Supervised execute"
  defp autonomy_label("guarded_autonomy"), do: "Guarded autonomy"
  defp autonomy_label("long_running_autonomy"), do: "Long-running autonomy"
  defp autonomy_label(mode), do: mode

  defp human_role("advise"), do: "operator_driven"
  defp human_role("supervised_execute"), do: "approval_required"
  defp human_role("guarded_autonomy"), do: "review_on_findings"
  defp human_role("long_running_autonomy"), do: "goal_steward"
  defp human_role(_mode), do: "review_on_findings"

  defp operator_posture("advise"), do: "Humans steer each step; CK packages context and evidence."

  defp operator_posture("supervised_execute"),
    do: "Agents execute, but approvals remain close to the work."

  defp operator_posture("guarded_autonomy"),
    do: "CK allows the loop to run while proofs, findings, and budgets stay active."

  defp operator_posture("long_running_autonomy"),
    do: "Operators steer outcomes and thresholds while the agent loop iterates across tasks."

  defp operator_posture(_mode), do: "CK keeps the loop reviewable."

  defp autonomy_reason(%Session{} = _session, "long_running_autonomy") do
    "This session has an explicit outcome target or enough coordinated tasks to behave like a sustained loop."
  end

  defp autonomy_reason(%Session{} = _session, "supervised_execute") do
    "The session carries high-risk or approval-heavy work, so CK keeps human gates close to execution."
  end

  defp autonomy_reason(%Session{} = _session, "advise") do
    "The session is still in planning shape, so CK keeps the agent in recommendation mode."
  end

  defp autonomy_reason(%Session{} = _session, "guarded_autonomy") do
    "The session can execute through the normal CK loop with findings, proofs, budgets, and routing controls in place."
  end

  defp goal_label("kpi"), do: "Outcome / KPI"
  defp goal_label("delivery"), do: "Task delivery"
  defp goal_label(goal_type), do: goal_type

  defp default_metric(%Session{} = session) do
    case get_in(session.execution_brief || %{}, ["domain_pack"]) do
      "security" -> "validated vulnerability cases merged"
      _other -> "deploy-ready tasks"
    end
  end

  defp default_window("kpi"), do: "rolling"
  defp default_window(_goal_type), do: "per session"

  defp current_task(%Session{} = session) do
    tasks = assoc_list(session.tasks)

    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "queued")) ||
      List.first(tasks)
  end

  defp trace_packet(%Session{} = session, nil) do
    case Mission.trace_improvement_packet(session.id, events_limit: 10) do
      {:ok, packet} -> packet
      _ -> nil
    end
  end

  defp trace_packet(%Session{} = session, task) do
    case Mission.trace_improvement_packet(session.id, task_id: task.id, events_limit: 10) do
      {:ok, packet} -> packet
      _ -> nil
    end
  end

  defp recommended_next_step(nil, _trace_packet, _cluster_count, _latest_proof) do
    "Define or queue the next task so the governed loop has an execution target."
  end

  defp recommended_next_step(_task, _trace_packet, cluster_count, latest_proof)
       when cluster_count > 0 and not is_nil(latest_proof) do
    "Turn the recurring failure clusters into evals or skill updates before the next run."
  end

  defp recommended_next_step(_task, trace_packet, _cluster_count, _latest_proof) do
    if is_map(trace_packet) and (get_in(trace_packet, ["eval_candidates"]) || []) != [] do
      "Promote the trace packet's eval candidates into a reusable benchmark or review check."
    else
      "Run the next governed cycle and capture a trace packet so CK has evidence to improve."
    end
  end

  defp improvement_ready?(%Session{} = session) do
    tasks = assoc_list(session.tasks)
    findings = assoc_list(session.findings)

    not Enum.empty?(tasks) and
      (not Enum.empty?(findings) or session.status == "done")
  end

  defp recommended_workspace_focus(autonomy_profiles, outcome_profiles, sessions) do
    cond do
      Enum.all?(outcome_profiles, &(&1["status"] == "implicit")) ->
        "Define explicit outcome targets for more sessions so CK can optimize beyond one-off completion."

      Enum.count(autonomy_profiles, &(&1["mode"] == "supervised_execute")) >
          div(max(length(autonomy_profiles), 1), 2) ->
        "A large share of recent work is running in supervised mode; the next leverage point is better traces and evals, not more autonomy."

      Enum.any?(sessions, &improvement_ready?/1) ->
        "Recent sessions already have enough evidence to evolve prompts, skills, or evals. Use trace packets and failure clusters to close the loop."

      true ->
        "Collect more governed runs, proofs, and findings so CK can recommend concrete harness improvements."
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(value), do: value != nil

  defp assoc_list(%Ecto.Association.NotLoaded{}), do: []
  defp assoc_list(nil), do: []
  defp assoc_list(list) when is_list(list), do: list
  defp assoc_list(_value), do: []
end
