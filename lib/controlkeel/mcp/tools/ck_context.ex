defmodule ControlKeel.MCP.Tools.CkContext do
  @moduledoc false

  alias ControlKeel.Budget
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Session}
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Repo
  alias ControlKeel.TaskAugmentation
  alias ControlKeel.TrustBoundary
  alias ControlKeel.WorkspaceContext
  import Ecto.Query, warn: false

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, session} <- fetch_session(session_id),
         {:ok, task} <- resolve_task(session, task_id) do
      project_root = project_root(arguments, session)
      provider_status = ProviderBroker.status(project_root)
      workspace_context = workspace_context(session, project_root)
      transcript_summary = Mission.transcript_summary(session.id)
      recent_events = Mission.list_session_events(session.id)
      context_reacquisition = context_reacquisition(workspace_context)

      {:ok,
       %{
         "session_id" => session.id,
         "project_root" => project_root,
         "session_title" => session.title,
         "risk_tier" => session.risk_tier,
         "compliance_profile" => session.workspace.compliance_profile,
         "active_findings" => active_findings_summary(session.findings),
         "security_case_summary" => Mission.security_case_summary(session.findings),
         "autonomy_profile" => AutonomyLoop.session_autonomy_profile(session),
         "outcome_profile" => AutonomyLoop.session_outcome_profile(session),
         "improvement_loop" => AutonomyLoop.session_improvement_loop(session),
         "budget_summary" => budget_summary(session),
         "boundary_summary" =>
           Intent.boundary_summary(session.execution_brief || %{}, project_root: project_root),
         "current_task" => task_summary(task),
         "past_patterns" => past_patterns(session),
         "proof_summary" => Mission.proof_summary_for_task(task),
         "planning_context" => planning_context(task),
         "task_augmentation" => TaskAugmentation.build(session, task, workspace_context),
         "memory_hits" => memory_hits(session, task),
         "resume_packet" => resume_packet(task),
         "workspace_context" => workspace_context,
         "workspace_cache_key" => workspace_context["cache_key"],
         "context_reacquisition" => context_reacquisition,
         "instruction_hierarchy" => TrustBoundary.instruction_hierarchy(),
         "recent_events" => recent_events,
         "transcript_summary" => transcript_summary,
         "provider_status" => %{
           "source" => provider_status["selected_source"],
           "provider" => provider_status["selected_provider"],
           "model" => provider_status["selected_model"],
           "fallback_chain" => provider_status["fallback_chain"]
         },
         "bootstrap_status" => provider_status["bootstrap"]
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp fetch_session(session_id) do
    case Mission.get_session_context(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp resolve_task(session, nil) do
    task =
      Enum.find(session.tasks, &(&1.status == "in_progress")) ||
        Enum.find(session.tasks, &(&1.status == "queued")) ||
        List.first(session.tasks)

    {:ok, task}
  end

  defp resolve_task(session, task_id) do
    case Enum.find(session.tasks, &(&1.id == task_id)) do
      nil -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
      task -> {:ok, task}
    end
  end

  defp active_findings_summary(findings) do
    active = Enum.filter(findings, &(&1.status in ["open", "blocked", "escalated"]))

    %{
      "count" => length(active),
      "blocked" => Enum.count(active, &(&1.status == "blocked")),
      "open" => Enum.count(active, &(&1.status == "open")),
      "escalated" => Enum.count(active, &(&1.status == "escalated")),
      "categories" => active |> Enum.map(& &1.category) |> Enum.uniq()
    }
  end

  defp budget_summary(session) do
    rolling_24h = Budget.rolling_24h_spend_cents(session.id)

    %{
      "session_budget_cents" => session.budget_cents,
      "spent_cents" => session.spent_cents,
      "remaining_session_cents" => remaining(session.spent_cents, session.budget_cents),
      "daily_budget_cents" => session.daily_budget_cents,
      "rolling_24h_spend_cents" => rolling_24h,
      "remaining_daily_cents" => remaining(rolling_24h, session.daily_budget_cents)
    }
  end

  defp task_summary(nil), do: nil

  defp task_summary(task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "status" => task.status,
      "validation_gate" => task.validation_gate,
      "metadata" => task.metadata,
      "assurance" => Mission.task_assurance_summary(task)
    }
  end

  defp planning_context(nil), do: %{}

  defp planning_context(task) do
    %{
      "review_gate" => Mission.review_gate_status(task),
      "latest_submitted_plan" =>
        get_in(task.metadata || %{}, ["planning_context", "latest_submitted_plan"]),
      "latest_approved_plan" =>
        get_in(task.metadata || %{}, ["planning_context", "latest_approved_plan"]),
      "latest_plan_decision" =>
        get_in(task.metadata || %{}, ["planning_context", "latest_plan_decision"])
    }
  end

  defp memory_hits(_session, nil), do: []

  defp memory_hits(session, task) do
    session
    |> Memory.retrieve_for_task(task, findings: session.findings, top_k: 5)
    |> Map.get(:entries, [])
  end

  defp resume_packet(nil), do: nil

  defp resume_packet(task) do
    case Mission.resume_packet(task.id) do
      {:ok, packet} -> packet
      _error -> nil
    end
  end

  defp workspace_context(session, project_root) do
    Mission.workspace_context(session, fallback_root: project_root)
  end

  defp project_root(arguments, session) do
    fallback_root =
      case Map.get(arguments, "project_root") do
        value when is_binary(value) and value != "" -> Path.expand(value)
        _ -> File.cwd!()
      end

    WorkspaceContext.resolve_project_root(session, fallback_root) || fallback_root
  end

  defp context_reacquisition(workspace_context) do
    %{
      "recent_commits" => get_in(workspace_context, ["orientation", "recent_commits"]) || [],
      "active_assumptions" =>
        get_in(workspace_context, ["orientation", "active_assumptions"]) || [],
      "design_drift_summary" => get_in(workspace_context, ["design_drift", "summary"]),
      "high_risk_design_drift" =>
        get_in(workspace_context, ["design_drift", "high_risk"]) || false
    }
  end

  # ─── Episodic memory: past patterns ─────────────────────────────────────────
  # Pull the most frequently recurring finding categories and rule IDs from the
  # last 10 sessions in the same domain. This gives the agent "what went wrong
  # before" so it can proactively avoid repeat mistakes.

  defp past_patterns(%Session{id: current_session_id, execution_brief: brief}) do
    domain =
      (brief || %{})
      |> then(&(Map.get(&1, "domain_pack") || Map.get(&1, :domain_pack)))

    if is_nil(domain) do
      %{"available" => false}
    else
      past_patterns_for_domain(domain, current_session_id)
    end
  end

  defp past_patterns_for_domain(domain, current_session_id) do
    recent_session_ids =
      Session
      |> where(
        [s],
        fragment("json_extract(?, '$.domain_pack')", s.execution_brief) == ^domain and
          s.id != ^current_session_id
      )
      |> order_by(desc: :inserted_at)
      |> limit(10)
      |> select([s], s.id)
      |> Repo.all()

    if recent_session_ids == [] do
      %{"available" => false}
    else
      top_rules =
        Finding
        |> where([f], f.session_id in ^recent_session_ids)
        |> where([f], f.status == "blocked")
        |> group_by([f], f.rule_id)
        |> order_by([f], desc: count(f.id))
        |> limit(5)
        |> select([f], %{rule_id: f.rule_id, count: count(f.id)})
        |> Repo.all()

      top_categories =
        Finding
        |> where([f], f.session_id in ^recent_session_ids)
        |> group_by([f], f.category)
        |> order_by([f], desc: count(f.id))
        |> limit(3)
        |> select([f], f.category)
        |> Repo.all()

      %{
        "available" => true,
        "domain" => domain,
        "sessions_sampled" => length(recent_session_ids),
        "recurring_rule_ids" =>
          Enum.map(top_rules, &%{"rule_id" => &1.rule_id, "blocked_count" => &1.count}),
        "top_categories" => top_categories,
        "hint" =>
          if top_rules != [] do
            first = List.first(top_rules)

            "In past #{domain} sessions, #{first.rule_id} was blocked #{first.count} time(s). Watch for it."
          else
            "No recurring patterns in past #{domain} sessions."
          end
      }
    end
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  defp optional_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp remaining(_spent, limit) when limit in [nil, 0], do: nil
  defp remaining(spent, limit), do: max(limit - spent, 0)
end
