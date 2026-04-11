defmodule ControlKeel.Intent.HarnessPolicy do
  @moduledoc false

  alias ControlKeel.Intent.ExecutionBrief

  @regulated_risk_tiers ~w(high critical)

  @default_policy %{
    "tool_execution" => %{
      "read_only_concurrency" => "parallel",
      "write_concurrency" => "serial",
      "execution_timing" => "in_loop",
      "result_budgeting" => "budget_then_reference",
      "rationale" =>
        "Run read-only discovery concurrently when possible, serialize mutations, and keep tool execution inside the main agent loop so results and failures stay governable."
    },
    "compaction" => %{
      "strategy" => "hierarchical",
      "order" => ["result_budget", "tail_preserving_snip", "summary_compact", "context_collapse"],
      "protected_tail" => true,
      "cheapest_first" => true,
      "rationale" =>
        "Compact the cheapest artifacts first, preserve the active tail of the session, and only pay for expensive summarization or collapse when lighter strategies fail."
    },
    "recovery" => %{
      "mode" => "in_loop_state_machine",
      "error_classes" => [
        "rate_limit",
        "context_overflow",
        "auth_refresh",
        "network_retry",
        "tool_failure"
      ],
      "requires_recovery_path" => true,
      "rationale" =>
        "Every major failure class should have a named recovery path inside the loop so the agent can retry, compact, refresh, or escalate without dropping session state."
    },
    "delegation" => %{
      "isolated_context" => true,
      "isolated_worktree" => "preferred_for_mutating_subagents",
      "authority_model" => "bounded_subtree",
      "rationale" =>
        "Delegated slices should carry isolated context and bounded authority; mutating subagents should prefer isolated worktrees or equivalent runtime sandboxes."
    }
  }

  def build(%ExecutionBrief{} = brief), do: build(ExecutionBrief.to_map(brief))

  def build(brief) when is_map(brief) do
    risk_tier = fetch_string(brief, "risk_tier")
    regulated? = regulated_or_sensitive?(brief, risk_tier)

    %{
      "tool_execution" => tool_execution_policy(regulated?),
      "compaction" => compaction_policy(regulated?),
      "recovery" => recovery_policy(regulated?),
      "delegation" => delegation_policy(regulated?)
    }
  end

  def build(_brief), do: @default_policy

  defp tool_execution_policy(true) do
    %{
      "read_only_concurrency" => "parallel",
      "write_concurrency" => "serial",
      "execution_timing" => "in_loop",
      "result_budgeting" => "budget_then_reference",
      "rationale" =>
        "For regulated or high-risk work, CK should still parallelize read-only discovery, but all mutations remain serialized and fully budgeted inside the loop."
    }
  end

  defp tool_execution_policy(false), do: @default_policy["tool_execution"]

  defp compaction_policy(true) do
    %{
      "strategy" => "hierarchical",
      "order" => ["result_budget", "tail_preserving_snip", "summary_compact", "context_collapse"],
      "protected_tail" => true,
      "cheapest_first" => true,
      "rationale" =>
        "High-risk work should preserve the recent evidence tail while compacting older tool output, then escalate to summaries or collapse only when necessary."
    }
  end

  defp compaction_policy(false), do: @default_policy["compaction"]

  defp recovery_policy(true) do
    %{
      "mode" => "in_loop_state_machine",
      "error_classes" => [
        "rate_limit",
        "context_overflow",
        "auth_refresh",
        "network_retry",
        "tool_failure",
        "approval_escalation"
      ],
      "requires_recovery_path" => true,
      "rationale" =>
        "High-risk sessions need explicit in-loop recovery for operational failures plus approval escalation paths when the work reaches broader authority."
    }
  end

  defp recovery_policy(false), do: @default_policy["recovery"]

  defp delegation_policy(true) do
    %{
      "isolated_context" => true,
      "isolated_worktree" => "required_for_mutating_subagents",
      "authority_model" => "bounded_subtree",
      "rationale" =>
        "High-risk delegated work should use isolated context and require isolated worktrees or equivalent governed runtimes before mutation proceeds."
    }
  end

  defp delegation_policy(false), do: @default_policy["delegation"]

  defp regulated_or_sensitive?(brief, risk_tier) do
    compliance = normalize_list(fetch_value(brief, "compliance"))

    risk_tier in @regulated_risk_tiers or
      compliance != [] or
      sensitive_summary?(brief)
  end

  defp sensitive_summary?(brief) do
    [fetch_string(brief, "data_summary"), fetch_string(brief, "recommended_stack")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
    |> then(fn text ->
      Enum.any?(
        ~w(api webhook postgres mysql redis salesforce stripe slack pii phi payroll billing patient healthcare legal finance),
        &String.contains?(text, &1)
      )
    end)
  end

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(_value), do: []

  defp fetch_string(map, key) do
    case fetch_value(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp fetch_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp known_atom_key("risk_tier"), do: :risk_tier
  defp known_atom_key("compliance"), do: :compliance
  defp known_atom_key("data_summary"), do: :data_summary
  defp known_atom_key("recommended_stack"), do: :recommended_stack
  defp known_atom_key(_key), do: nil
end
