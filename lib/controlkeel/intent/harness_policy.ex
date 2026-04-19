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
    "capability_egress" => %{
      "network_default" => "deny",
      "grant_model" => "explicit_task_scoped_allowlist",
      "approval_path" => "ck_review_or_trusted_human",
      "audit_posture" => "approved_capabilities_are_traceable",
      "rationale" =>
        "Execution should start from no implicit network or side-effect authority. Grant egress and high-impact capabilities explicitly per task through reviewed, auditable allowlists."
    },
    "context_contract" => %{
      "ownership" => "operator_visible_and_ck_controlled",
      "system_prompt_posture" => "minimal_and_stable",
      "tool_schema_posture" => "versioned_and_additive",
      "hidden_context_mutation" => "forbid_silent_instruction_injection",
      "relevance_injection" => "scoped_and_attributed",
      "rationale" =>
        "The working context should belong to the operator and the governed runtime, not to silent host-side mutations. Keep the core system contract small, keep tool schemas stable and additive, and make any extra reminders or retrieved context explicit, scoped, and attributable."
    },
    "memory" => %{
      "ownership" => "workspace_or_ck_controlled",
      "portability" => "typed_records_and_resume_packets",
      "retrieval_mode" => "ranked_memory_hits",
      "retrieval_strategy" => "single_vector",
      "supported_retrieval_strategies" => [
        "single_vector",
        "bm25",
        "hybrid_bm25_vector",
        "late_interaction",
        "late_interaction_rerank"
      ],
      "integration_mode" => "agent_must_reconcile_with_active_context",
      "citation_posture" => "cite_memory_before_claim",
      "compaction_visibility" => "explicit_summary_and_protected_tail",
      "provider_state_posture" => "prefer_portable_ck_state",
      "rationale" =>
        "Keep durable agent memory in CK-controlled typed surfaces such as memory records, proofs, traces, and resume packets so context survives host changes and does not disappear into opaque provider-managed state. Treat retrieval and integration as separate governed steps: CK can return ranked memory hits, but the agent still has to reconcile them with the active task context before making claims. Current default is single-vector cosine similarity; late-interaction (multi-vector MaxSim) retrieval is a recognized future strategy for harder recall tasks."
    },
    "compaction" => %{
      "strategy" => "hierarchical",
      "order" => ["result_budget", "tail_preserving_snip", "summary_compact", "context_collapse"],
      "protected_tail" => true,
      "cheapest_first" => true,
      "rationale" =>
        "Compact the cheapest artifacts first, preserve the active tail of the session, and only pay for expensive summarization or collapse when lighter strategies fail."
    },
    "observability" => %{
      "transcript_visibility" => "recent_events_and_resume_packets",
      "tool_result_posture" => "budget_then_reference",
      "compaction_audit" => "runtime_context_integrity",
      "mutation_audit" => "proofs_findings_and_reviews",
      "rationale" =>
        "Agents should not operate as a black box. CK keeps recent events, runtime context integrity, findings, reviews, and proofs visible so compaction, delegated work, and high-impact mutations stay inspectable after the fact."
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
    "extensibility" => %{
      "host_surface_strategy" => "truthful_host_native_extensions",
      "operator_override" => "repo_visible_configuration",
      "self_modification_scope" => "skills_plugins_and_runtime_bundles",
      "rationale" =>
        "Prefer small governed cores plus repo-visible extensions over monolithic hidden behavior. CK should meet hosts on their real native surfaces and let operators adapt workflows through skills, plugins, hooks, and runtime bundles that remain reviewable."
    },
    "provider_choice" => %{
      "selection_strategy" => "explicit_and_budget_aware",
      "model_portability" => "cross_provider_handoff_supported",
      "rationale" =>
        "Model and provider choice should stay explicit and portable. CK tracks provider selection, fallback chains, and budget pressure so teams are not locked into a single opaque host-managed runtime."
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
      "capability_egress" => capability_egress_policy(regulated?),
      "context_contract" => context_contract_policy(),
      "memory" => memory_policy(regulated?),
      "compaction" => compaction_policy(regulated?),
      "observability" => observability_policy(),
      "recovery" => recovery_policy(regulated?),
      "extensibility" => extensibility_policy(),
      "provider_choice" => provider_choice_policy(),
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

  defp capability_egress_policy(true) do
    %{
      "network_default" => "deny",
      "grant_model" => "explicit_task_scoped_allowlist",
      "approval_path" => "ck_review_or_trusted_human",
      "audit_posture" => "approved_capabilities_are_traceable",
      "rationale" =>
        "High-risk sessions should require explicit, reviewed capability grants before network or other high-impact execution paths are opened."
    }
  end

  defp capability_egress_policy(false), do: @default_policy["capability_egress"]

  defp context_contract_policy, do: @default_policy["context_contract"]

  defp memory_policy(true) do
    %{
      "ownership" => "workspace_or_ck_controlled",
      "portability" => "typed_records_and_resume_packets",
      "retrieval_mode" => "ranked_memory_hits",
      "integration_mode" => "agent_must_reconcile_with_active_context",
      "citation_posture" => "cite_memory_before_claim",
      "compaction_visibility" => "explicit_summary_and_protected_tail",
      "provider_state_posture" => "avoid_opaque_provider_memory",
      "rationale" =>
        "High-risk work should keep durable state in CK-controlled typed memory, proofs, traces, and resume packets so evidence remains portable, reviewable, and independent of proprietary provider-side memory behavior. Memory retrieval should stay ranked and citable, and the final integration step should still be treated as a governed reasoning task rather than perfect recall."
    }
  end

  defp memory_policy(false), do: @default_policy["memory"]

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

  defp observability_policy, do: @default_policy["observability"]

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

  defp extensibility_policy, do: @default_policy["extensibility"]

  defp provider_choice_policy, do: @default_policy["provider_choice"]

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
