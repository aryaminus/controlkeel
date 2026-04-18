defmodule ControlKeel.Intent.BoundarySummaryTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent

  import ControlKeel.IntentFixtures

  test "builds a production boundary summary from the execution brief and compiler answers" do
    brief = execution_brief_fixture()

    summary =
      Intent.boundary_summary(
        brief,
        provider_status: %{
          "selected_source" => "agent_bridge",
          "selected_provider" => "anthropic",
          "attached_agents" => [%{"id" => "claude-code"}],
          "runtime_hints" => [%{"agent_id" => "claude-code"}]
        }
      )

    assert summary["risk_tier"] == "critical"
    assert summary["budget_note"] == "$40/month to start"
    assert summary["data_summary"] == "Patient names, insurance notes, and scheduling details."
    assert summary["compliance"] == ["HIPAA", "HITECH", "OWASP Top 10"]
    assert summary["constraints"] == ["Approval before deploy"]

    assert summary["open_questions"] == [
             "Which EHR integration should the first release support?"
           ]

    assert summary["launch_window"] == "Internal pilot before broader rollout"

    assert summary["next_step"] ==
             "Lock the architecture, hosting boundary, and approval flow before code generation."

    assert summary["execution_posture"]["exploration_surface"] == "virtual_workspace"
    assert summary["execution_posture"]["state_surface"] == "typed_storage"
    assert summary["execution_posture"]["api_execution_surface"] == "typed_runtime"
    assert summary["execution_posture"]["shell_role"] == "broad_fallback_only"
    assert summary["harness_policy"]["tool_execution"]["read_only_concurrency"] == "parallel"
    assert summary["harness_policy"]["tool_execution"]["write_concurrency"] == "serial"

    assert summary["harness_policy"]["context_contract"]["system_prompt_posture"] ==
             "minimal_and_stable"

    assert summary["harness_policy"]["context_contract"]["hidden_context_mutation"] ==
             "forbid_silent_instruction_injection"

    assert summary["harness_policy"]["memory"]["ownership"] == "workspace_or_ck_controlled"
    assert summary["harness_policy"]["memory"]["retrieval_mode"] == "ranked_memory_hits"

    assert summary["harness_policy"]["memory"]["integration_mode"] ==
             "agent_must_reconcile_with_active_context"

    assert summary["harness_policy"]["memory"]["citation_posture"] ==
             "cite_memory_before_claim"

    assert summary["harness_policy"]["memory"]["provider_state_posture"] ==
             "avoid_opaque_provider_memory"

    assert summary["harness_policy"]["compaction"]["strategy"] == "hierarchical"

    assert summary["harness_policy"]["observability"]["compaction_audit"] ==
             "runtime_context_integrity"

    assert summary["harness_policy"]["recovery"]["mode"] == "in_loop_state_machine"

    assert summary["harness_policy"]["extensibility"]["host_surface_strategy"] ==
             "truthful_host_native_extensions"

    assert summary["harness_policy"]["provider_choice"]["selection_strategy"] ==
             "explicit_and_budget_aware"

    assert summary["harness_policy"]["delegation"]["isolated_worktree"] ==
             "required_for_mutating_subagents"

    assert summary["runtime_recommendation"]["strategy"] == "attach_client"
    assert summary["runtime_recommendation"]["recommended_integration"]["id"] == "claude-code"

    assert summary["runtime_recommendation"]["recommended_integration"]["availability"] ==
             "attached"

    assert summary["runtime_recommendation"]["recommended_integration"]["attach_command"] ==
             "controlkeel attach claude-code"
  end

  test "normalizes blank or comma-separated constraints into a short list" do
    brief =
      execution_brief_fixture(
        compiler: %{
          "interview_answers" => %{
            "constraints" => "Local-first deploy,\napproval before production,  "
          }
        }
      )

    assert Intent.boundary_summary(brief)["constraints"] == [
             "Local-first deploy",
             "approval before production"
           ]

    empty =
      execution_brief_fixture(compiler: %{"interview_answers" => %{"constraints" => "   "}})

    assert Intent.boundary_summary(empty)["constraints"] == []
  end

  test "returns an empty nil-safe summary when the brief or compiler metadata is missing" do
    assert Intent.boundary_summary(nil) == %{
             "risk_tier" => nil,
             "budget_note" => nil,
             "data_summary" => nil,
             "compliance" => [],
             "constraints" => [],
             "open_questions" => [],
             "launch_window" => nil,
             "next_step" => nil,
             "execution_posture" => %{
               "exploration_surface" => "virtual_workspace",
               "state_surface" => "typed_storage",
               "api_execution_surface" => "typed_runtime_or_shell",
               "mutation_surface" => "shell_sandbox",
               "shell_role" => "fallback",
               "clearance_focus" => ["file_write", "network", "deploy", "secrets"],
               "rationale" =>
                 "Prefer read-only discovery first, keep durable state in typed storage surfaces, use typed runtimes for large tool and API interactions when available, and treat shell as the broad fallback surface for mutation and execution."
             },
             "harness_policy" => %{
               "tool_execution" => %{
                 "read_only_concurrency" => "parallel",
                 "write_concurrency" => "serial",
                 "execution_timing" => "in_loop",
                 "result_budgeting" => "budget_then_reference",
                 "rationale" =>
                   "Run read-only discovery concurrently when possible, serialize mutations, and keep tool execution inside the main agent loop so results and failures stay governable."
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
                 "order" => [
                   "result_budget",
                   "tail_preserving_snip",
                   "summary_compact",
                   "context_collapse"
                 ],
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
             },
             "runtime_recommendation" => %{
               "strategy" => "undecided",
               "recommended_integration" => nil,
               "alternatives" => [],
               "rationale" =>
                 "CK needs a populated execution brief before it can recommend a concrete host or runtime path."
             }
           }

    assert Intent.boundary_summary(%{"risk_tier" => "high"})["constraints"] == []
  end
end
