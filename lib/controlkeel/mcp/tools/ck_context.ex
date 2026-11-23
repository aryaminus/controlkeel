defmodule ControlKeel.MCP.Tools.CkContext do
  @moduledoc false

  alias ControlKeel.Budget
  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Session}
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Memory.Precedent
  alias ControlKeel.Project.Local
  alias ControlKeel.Repo
  alias ControlKeel.Mission.TaskAugmentation
  alias ControlKeel.Governance.TrustBoundary
  alias ControlKeel.Project.WorkspaceContext
  import Ecto.Query, warn: false

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_session_id(arguments),
         {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, session} <- fetch_session(session_id, arguments),
         {:ok, task} <- resolve_task(session, task_id) do
      project_root = project_root(arguments, session)
      provider_status = ProviderBroker.status(project_root)
      workspace_context = workspace_context(session, project_root)
      transcript_summary = Mission.transcript_summary(session.id)
      recent_events = Mission.list_session_events(session.id)
      context_reacquisition = context_reacquisition(workspace_context)

      context = %{
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
        "boundary_summary" => Intent.boundary_summary(session.execution_brief || %{}),
        "current_task" => task_summary(task),
        "past_patterns" => past_patterns(session),
        "proof_summary" => Mission.proof_summary_for_task(task),
        "planning_context" => planning_context(task),
        "task_augmentation" => TaskAugmentation.build(session, task, workspace_context),
        "memory_hits" => memory_hits(session, task),
        "precedent" => precedent_hits(session),
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
        "bootstrap_status" => provider_status["bootstrap"],
        "attach_advisory" => attach_advisory(project_root, provider_status["bootstrap"])
      }

      {:ok, apply_detail_level(context, arguments)}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp apply_detail_level(context, arguments) do
    case Map.get(arguments, "detail_level", "compact") do
      value when value in ["full", :full] -> Map.put(context, "detail_level", "full")
      _ -> compact_context(context)
    end
  end

  # Compact context is what an agent needs to act: open blockers, budget, the
  # current task and its review gate, a short recent history, and the next
  # step. Static policy (harness posture, instruction hierarchy) and copies
  # nested in the resume packet live only in `detail_level: full`.
  defp compact_context(context) do
    task = context["current_task"]
    planning = context["planning_context"] || %{}
    gate = planning["review_gate"] || %{}
    loop = context["improvement_loop"] || %{}

    %{
      "detail_level" => "compact",
      "detail_hint" =>
        "Pass detail_level: full for policy posture, workspace and transcript detail.",
      "session_id" => context["session_id"],
      "project_root" => context["project_root"],
      "session_title" => context["session_title"],
      "risk_tier" => context["risk_tier"],
      "compliance_profile" => context["compliance_profile"],
      "active_findings" => context["active_findings"],
      "budget_summary" => context["budget_summary"],
      "current_task" => compact_task(task),
      "planning_context" => %{
        "review_gate" =>
          Map.take(gate, [
            "phase",
            "execution_ready",
            "latest_review_id",
            "latest_review_status",
            "latest_review_type"
          ])
      },
      "improvement_loop" =>
        %{
          "recommended_next_step" => loop["recommended_next_step"],
          "bottleneck" => get_in(loop, ["bottleneck_summary", "primary"]),
          "deploy_ready" => loop["deploy_ready"]
        }
        |> reject_nil_values(),
      "autonomy_profile" => Map.take(context["autonomy_profile"] || %{}, ["mode", "label"]),
      "memory_hits" =>
        context["memory_hits"]
        |> compact_list(3)
        |> Enum.map(&take_keys(&1, ["id", "title", "summary", "record_type"])),
      "precedent" =>
        context["precedent"]
        |> compact_list(3)
        |> Enum.map(&take_keys(&1, ["id", "title", "rule_id", "disposition", "summary"])),
      "recent_events" =>
        context["recent_events"]
        |> compact_list(5)
        |> Enum.map(&take_keys(&1, ["id", "event_type", "summary", "inserted_at"])),
      "workspace_context" => compact_workspace_context(context["workspace_context"]),
      "workspace_cache_key" => context["workspace_cache_key"],
      "provider_status" =>
        Map.take(context["provider_status"] || %{}, ["source", "provider", "model"])
    }
    |> maybe_put_advisory(context["attach_advisory"])
  end

  defp compact_task(%{} = task) do
    task
    |> Map.take(["id", "title", "status", "validation_gate"])
    |> Map.put(
      "verification_status",
      get_in(task, ["assurance", "verification", "status"])
    )
    |> reject_nil_values()
  end

  defp compact_task(other), do: other

  # Only surface the attach advisory when it asks for something.
  defp maybe_put_advisory(map, %{"status" => status} = advisory) when status != "attached",
    do: Map.put(map, "attach_advisory", Map.take(advisory, ["status", "guidance"]))

  defp maybe_put_advisory(map, _advisory), do: map

  # Records may carry string or atom keys depending on their source.
  defp take_keys(%{} = record, keys) do
    for key <- keys,
        value = Map.get(record, key, Map.get(record, String.to_atom(key))),
        not is_nil(value),
        into: %{},
        do: {key, value}
  end

  defp take_keys(other, _keys), do: other

  defp reject_nil_values(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  defp compact_workspace_context(workspace_context) when is_map(workspace_context) do
    %{
      "cache_key" => workspace_context["cache_key"],
      "recent_commits" =>
        workspace_context
        |> get_in(["orientation", "recent_commits"])
        |> compact_list(3)
        |> Enum.map(fn
          %{} = commit -> Map.take(commit, ["short_sha", "subject"])
          other -> other
        end),
      "design_drift_high_risk" => get_in(workspace_context, ["design_drift", "high_risk"])
    }
  end

  defp compact_workspace_context(value), do: value

  defp compact_list(list, limit) when is_list(list), do: Enum.take(list, limit)
  defp compact_list(_value, _limit), do: []

  defp fetch_session(session_id, arguments) do
    case Mission.get_session_context(session_id) do
      nil -> fallback_active_session(arguments)
      session -> {:ok, session}
    end
  end

  defp fallback_active_session(arguments) do
    with {:ok, active_session_id} <- resolve_active_session_id(arguments),
         session when not is_nil(session) <- Mission.get_session_context(active_session_id) do
      {:ok, session}
    else
      _ -> {:error, {:invalid_arguments, "Session not found"}}
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
    {count, blocked, open, escalated, categories} =
      Enum.reduce(findings, {0, 0, 0, 0, MapSet.new()}, fn finding, {c, b, o, e, cats} ->
        case finding.status do
          "blocked" -> {c + 1, b + 1, o, e, MapSet.put(cats, finding.category)}
          "open" -> {c + 1, b, o + 1, e, MapSet.put(cats, finding.category)}
          "escalated" -> {c + 1, b, o, e + 1, MapSet.put(cats, finding.category)}
          _ -> {c, b, o, e, cats}
        end
      end)

    %{
      "count" => count,
      "blocked" => blocked,
      "open" => open,
      "escalated" => escalated,
      "categories" => MapSet.to_list(categories),
      "top_blocked" =>
        findings
        |> Enum.filter(&(&1.status == "blocked"))
        |> Enum.sort_by(& &1.id, :desc)
        |> Enum.take(5)
        |> Enum.map(fn finding ->
          %{
            "id" => finding.id,
            "severity" => finding.severity,
            "rule_id" => finding.rule_id,
            "title" => finding.title
          }
        end)
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

  defp precedent_hits(session) do
    Precedent.workspace_precedent(session, limit: 5)
  rescue
    _ -> []
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

  # Detect whether the host that started this MCP session has actually been
  # attached (hooks/skills/AGENTS.md installed) or whether the user only ran
  # a one-line MCP-add command and skipped `controlkeel attach <host>`. The
  # advisory surfaces the gap and the fix (call ck_attach) without forcing
  # action — the LLM can read it and decide.
  defp attach_advisory(project_root, bootstrap_status) do
    binding =
      case ControlKeel.Project.Binding.read(project_root) do
        {:ok, b} -> b
        _ -> %{}
      end

    attached = Map.get(binding, "attached_agents") || %{}

    auto_bootstrapped =
      is_map(bootstrap_status) and Map.get(bootstrap_status, "auto_bootstrapped")

    cond do
      map_size(attached) > 0 ->
        %{
          "status" => "attached",
          "hosts" => Map.keys(attached),
          "guidance" =>
            "Host attachment is recorded as installed. Runtime hook execution has not been verified by this advisory."
        }

      auto_bootstrapped ->
        %{
          "status" => "mcp_only",
          "hosts" => [],
          "guidance" =>
            "This project has MCP tools wired but no host attachment recorded in its binding. " <>
              "Host files may already exist; inspect them before refreshing attachment. To configure SessionStart auto-context, PreToolUse auto-validate, " <>
              "completion-review slash command, and AGENTS.md governance preamble, call " <>
              "the `ck_attach` tool with the host you're running in " <>
              "(e.g. {\"host\":\"claude-code\"}), or run `controlkeel attach <host>` " <>
              "from your shell. See docs/agent-integrations.md for the full host list."
        }

      true ->
        %{
          "status" => "unbound",
          "hosts" => [],
          "guidance" =>
            "No ControlKeel project binding detected. Run `controlkeel attach <host>` " <>
              "or call the `ck_attach` MCP tool to wire CK into the current agent host."
        }
    end
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
        json_extract_path(s.execution_brief, ["domain_pack"]) == ^domain and
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

  defp required_session_id(arguments) do
    case Map.get(arguments, "session_id") do
      nil ->
        resolve_active_session_id(arguments)

      value when is_binary(value) ->
        normalized = String.trim(value)

        case String.downcase(normalized) do
          alias_value when alias_value in ["current", "active"] ->
            resolve_active_session_id(arguments)

          _ ->
            Arguments.normalize_integer(normalized, "session_id")
        end

      value ->
        Arguments.normalize_integer(value, "session_id")
    end
  end

  defp resolve_active_session_id(arguments) do
    project_root =
      case Map.get(arguments, "project_root") do
        value when is_binary(value) and value != "" -> Path.expand(value)
        _ -> File.cwd!()
      end

    case Local.load(project_root) do
      {:ok, _binding, session} ->
        {:ok, session.id}

      _ ->
        {:error,
         {:invalid_arguments,
          "`session_id` must be an integer. For `current`, run from a bound project or pass --project-root with an active binding."}}
    end
  end

  defp remaining(_spent, limit) when limit in [nil, 0], do: nil
  defp remaining(spent, limit), do: max(limit - spent, 0)
end
