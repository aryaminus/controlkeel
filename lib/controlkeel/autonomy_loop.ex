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
    bottleneck = bottleneck_summary(session, current_task, latest_proof, trace_summary)
    ownership = ownership_summary(session)
    diagnostic_findings = bottleneck_findings(bottleneck) ++ ownership_findings(ownership)

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
      "bottleneck_summary" => bottleneck,
      "ownership_summary" => ownership,
      "diagnostic_findings" => diagnostic_findings,
      "recommended_next_step" =>
        recommended_next_step(current_task, trace_packet, cluster_count, latest_proof, bottleneck)
    }
  end

  def bottleneck_summary(%Session{} = session, current_task, latest_proof, trace_summary \\ %{}) do
    findings = assoc_list(session.findings)
    active_findings = Enum.filter(findings, &(&1.status in ["open", "blocked", "escalated"]))
    blocked_findings = Enum.count(active_findings, &(&1.status == "blocked"))
    review_gate = if current_task, do: Mission.review_gate_status(current_task), else: %{}

    budget_ratio =
      case session.budget_cents do
        budget when is_integer(budget) and budget > 0 ->
          Float.round((session.spent_cents || 0) / budget, 3)

        _ ->
          0.0
      end

    candidates =
      [
        {"unresolved_findings",
         blocked_findings * 30 + max(length(active_findings) - blocked_findings, 0) * 10},
        {"review_wait", if(review_gate["execution_ready"] == false, do: 35, else: 0)},
        {"missing_deploy_ready_proof",
         if(get_in(latest_proof || %{}, ["deploy_ready"]) == true, do: 0, else: 20)},
        {"budget_pressure", if(budget_ratio >= 0.8, do: 25, else: 0)},
        {"trace_gap", if((trace_summary["invocations"] || 0) == 0, do: 10, else: 0)}
      ]

    {primary, score} =
      candidates
      |> Enum.max_by(fn {_name, score} -> score end, fn -> {"none", 0} end)

    %{
      "primary" => if(score > 0, do: primary, else: "none"),
      "score" => min(score, 100),
      "signals" => %{
        "active_findings" => length(active_findings),
        "blocked_findings" => blocked_findings,
        "review_execution_ready" => review_gate["execution_ready"],
        "deploy_ready" => get_in(latest_proof || %{}, ["deploy_ready"]) == true,
        "budget_spend_ratio" => budget_ratio,
        "trace_invocations" => trace_summary["invocations"] || 0
      },
      "recommendation" => bottleneck_recommendation(primary, score)
    }
  end

  def ownership_summary(%Session{} = session) do
    task_owners =
      session.tasks
      |> assoc_list()
      |> Enum.map(&metadata_owner/1)
      |> Enum.reject(&is_nil/1)

    review_submitters =
      session
      |> Map.get(:reviews)
      |> assoc_list()
      |> Enum.map(& &1.submitted_by)
      |> Enum.reject(&blank?/1)

    finding_categories =
      session.findings
      |> assoc_list()
      |> Enum.map(& &1.category)
      |> Enum.reject(&blank?/1)

    concentrations = %{
      "task_owner" => concentration(task_owners),
      "review_submitter" => concentration(review_submitters),
      "finding_category" => concentration(finding_categories)
    }

    risks =
      concentrations
      |> Enum.filter(fn {_key, value} -> concentration_risky?(value) end)
      |> Enum.map(fn {key, value} -> "#{key}:#{value["top"]}" end)

    %{
      "signals" => concentrations,
      "risk" => if(risks == [], do: "clear", else: "concentrated"),
      "risks" => risks,
      "recommendation" => ownership_recommendation(risks)
    }
  end

  def bottleneck_findings(summary, attrs \\ %{}) when is_map(summary) do
    base =
      case summary["primary"] do
        primary when primary in ["unresolved_findings", "review_wait", "budget_pressure"] ->
          [
            %{
              "category" => "delivery-analytics",
              "severity" => if(primary == "unresolved_findings", do: "high", else: "medium"),
              "rule_id" => "delivery.serial_bottleneck.#{primary}",
              "title" => "Delivery bottleneck: #{String.replace(primary, "_", " ")}",
              "plain_message" => summary["recommendation"],
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "autonomy_loop_bottleneck",
                  "bottleneck_summary" => summary
                })
            }
          ]

        _ ->
          []
      end

    coordination =
      if get_in(summary, ["signals", "active_findings"]) >= 5 and
           get_in(summary, ["signals", "blocked_findings"]) >= 2 do
        [
          %{
            "category" => "delivery-analytics",
            "severity" => "medium",
            "rule_id" => "delegation.coordination_overhead",
            "title" => "Coordination overhead from blocked findings",
            "plain_message" =>
              "The session has #{get_in(summary, ["signals", "blocked_findings"])} blocked findings among #{get_in(summary, ["signals", "active_findings"])} active. Widening delegation before resolving blockers will increase coordination cost without improving throughput.",
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "autonomy_loop_bottleneck",
                "bottleneck_summary" => summary
              })
          }
        ]
      else
        []
      end

    base ++ coordination
  end

  def ownership_findings(summary, attrs \\ %{}) when is_map(summary) do
    base =
      if summary["risk"] == "concentrated" do
        [
          %{
            "category" => "delivery-analytics",
            "severity" => "medium",
            "rule_id" => "teams.ownership_concentration",
            "title" => "Ownership concentration detected",
            "plain_message" => summary["recommendation"],
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "autonomy_loop_ownership",
                "ownership_summary" => summary
              })
          }
        ]
      else
        []
      end

    bus_factor =
      case get_in(summary, ["signals", "task_owner"]) do
        %{"total" => total, "top_share" => share} when total >= 3 and share >= 0.9 ->
          [
            %{
              "category" => "delivery-analytics",
              "severity" => "high",
              "rule_id" => "teams.bus_factor.low",
              "title" => "Bus factor is critically low",
              "plain_message" =>
                "A single owner holds >= 90% of task assignments (#{share |> Kernel.*(100) |> round()}% of #{total} tasks). If this agent or person becomes unavailable, delivery stalls.",
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "autonomy_loop_ownership",
                  "ownership_summary" => summary
                })
            }
          ]

        _ ->
          []
      end

    approval_concentration =
      case get_in(summary, ["signals", "review_submitter"]) do
        %{"total" => total, "top_share" => share} when total >= 3 and share >= 0.85 ->
          [
            %{
              "category" => "delivery-analytics",
              "severity" => "medium",
              "rule_id" => "teams.approval_concentration",
              "title" => "Review approval is concentrated",
              "plain_message" =>
                "A single reviewer handles >= 85% of review submissions. Diversify reviewers to improve coverage and reduce single-point-of-failure risk.",
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "autonomy_loop_ownership",
                  "ownership_summary" => summary
                })
            }
          ]

        _ ->
          []
      end

    base ++ bus_factor ++ approval_concentration
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

  defp recommended_next_step(nil, _trace_packet, _cluster_count, _latest_proof, _bottleneck) do
    "Define or queue the next task so the governed loop has an execution target."
  end

  defp recommended_next_step(_task, _trace_packet, _cluster_count, _latest_proof, %{
         "primary" => "review_wait"
       }) do
    "Clear the pending review gate before adding more parallel work."
  end

  defp recommended_next_step(_task, _trace_packet, _cluster_count, _latest_proof, %{
         "primary" => "unresolved_findings"
       }) do
    "Resolve or disposition unresolved findings before widening delegation."
  end

  defp recommended_next_step(_task, _trace_packet, cluster_count, latest_proof, _bottleneck)
       when cluster_count > 0 and not is_nil(latest_proof) do
    "Turn the recurring failure clusters into evals or skill updates before the next run."
  end

  defp recommended_next_step(_task, trace_packet, _cluster_count, _latest_proof, _bottleneck) do
    if is_map(trace_packet) and (get_in(trace_packet, ["eval_candidates"]) || []) != [] do
      "Promote the trace packet's eval candidates into a reusable benchmark or review check."
    else
      "Run the next governed cycle and capture a trace packet so CK has evidence to improve."
    end
  end

  defp bottleneck_recommendation(_primary, 0), do: "No serial bottleneck detected yet."

  defp bottleneck_recommendation("unresolved_findings", _score) do
    "Findings are the serial constraint; more agents will not help until blockers are resolved or accepted."
  end

  defp bottleneck_recommendation("review_wait", _score) do
    "Review readiness is the serial constraint; get approval or refine the plan before parallelizing."
  end

  defp bottleneck_recommendation("missing_deploy_ready_proof", _score) do
    "Proof readiness is the serial constraint; capture validation evidence before calling the loop done."
  end

  defp bottleneck_recommendation("budget_pressure", _score) do
    "Budget pressure is the serial constraint; prefer cheaper validation or narrower execution."
  end

  defp bottleneck_recommendation("trace_gap", _score) do
    "Trace coverage is thin; run one governed cycle and capture evidence before optimizing the loop."
  end

  defp bottleneck_recommendation(_primary, _score), do: "Keep the current governed loop moving."

  defp metadata_owner(%{metadata: metadata}) when is_map(metadata) do
    value =
      metadata["owner"] || metadata["assignee"] || metadata["agent"] || metadata["submitted_by"]

    if blank?(value), do: nil, else: to_string(value)
  end

  defp metadata_owner(_task), do: nil

  defp concentration([]), do: %{"total" => 0, "top" => nil, "top_count" => 0, "top_share" => 0.0}

  defp concentration(values) do
    {top, count} =
      values
      |> Enum.frequencies()
      |> Enum.max_by(fn {_value, count} -> count end)

    %{
      "total" => length(values),
      "top" => top,
      "top_count" => count,
      "top_share" => Float.round(count / length(values), 3)
    }
  end

  defp concentration_risky?(%{"total" => total, "top_share" => share}) do
    total >= 3 and share >= 0.75
  end

  defp ownership_recommendation([]), do: "No ownership concentration risk detected."

  defp ownership_recommendation(_risks) do
    "Review ownership concentration before widening the work; add a second reviewer, proof author, or task owner where possible."
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

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp assoc_list(%Ecto.Association.NotLoaded{}), do: []
  defp assoc_list(nil), do: []
  defp assoc_list(list) when is_list(list), do: list
  defp assoc_list(_value), do: []
end
