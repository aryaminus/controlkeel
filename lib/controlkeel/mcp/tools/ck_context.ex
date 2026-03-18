defmodule ControlKeel.MCP.Tools.CkContext do
  @moduledoc false

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Session}
  alias ControlKeel.Repo
  import Ecto.Query, warn: false

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, session} <- fetch_session(session_id),
         {:ok, task} <- resolve_task(session, task_id) do
      {:ok,
       %{
         "session_id" => session.id,
         "session_title" => session.title,
         "risk_tier" => session.risk_tier,
         "compliance_profile" => session.workspace.compliance_profile,
         "active_findings" => active_findings_summary(session.findings),
         "budget_summary" => budget_summary(session),
         "current_task" => task_summary(task),
         "past_patterns" => past_patterns(session)
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
      "metadata" => task.metadata
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
        "recurring_rule_ids" => Enum.map(top_rules, &%{"rule_id" => &1.rule_id, "blocked_count" => &1.count}),
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
