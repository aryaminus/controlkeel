defmodule ControlKeel.MCP.Tools.CkLoopTest do
  use ControlKeel.DataCase

  alias ControlKeel.Mission
  alias ControlKeel.MCP.Tools.{CkLoop, CkReviewFeedback}
  import ControlKeel.MissionFixtures

  setup do
    session = session_fixture()
    task = task_fixture(%{session: session})
    root = Path.join(System.tmp_dir!(), "ck-loop-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))
    File.mkdir_p!(Path.join(root, "docs"))
    File.write!(Path.join(root, "lib/example.ex"), "defmodule Example do\nend\n")
    File.write!(Path.join(root, "test/verifier.exs"), "assert true\n")
    File.write!(Path.join(root, "docs/evidence.md"), "# Evidence\n")
    on_exit(fn -> File.rm_rf(root) end)

    {:ok, worker_invocation} =
      Mission.create_invocation(%{
        source: "worker-agent",
        tool: "bounded_loop_worker",
        provider: "openai",
        model: "gpt-5.6-sol",
        estimated_cost_cents: 0,
        decision: "allow",
        session_id: session.id,
        task_id: task.id
      })

    {:ok, session: session, task: task, root: root, worker_invocation: worker_invocation}
  end

  test "creates an immutable bounded contract and reports status", context do
    assert {:ok, result} = CkLoop.call(create_args(context))
    assert result["status"] == "active"
    assert result["iteration_count"] == 0
    assert result["contract"]["verifier_paths"] == ["test/verifier.exs"]
    assert map_size(result["contract"]["verifier_hashes"]) == 1

    assert {:ok, status} = CkLoop.call(status_args(context))
    assert status["contract_id"] == result["contract_id"]
  end

  test "accepts numeric string identifiers advertised by the MCP schema", context do
    args =
      create_args(context)
      |> Map.put("session_id", Integer.to_string(context.session.id))
      |> Map.put("task_id", Integer.to_string(context.task.id))

    assert {:ok, result} = CkLoop.call(args)
    assert result["session_id"] == context.session.id

    assert {:ok, status} =
             CkLoop.call(%{
               "mode" => "status",
               "session_id" => Integer.to_string(context.session.id),
               "task_id" => Integer.to_string(context.task.id)
             })

    assert status["contract_id"] == result["contract_id"]
  end

  test "rejects overlapping worker and verifier paths", context do
    args = create_args(context) |> Map.put("mutable_paths", ["test"])
    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "disjoint"
  end

  test "accepts improvement and awaits review at the objective target", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    assert {:ok, first} = CkLoop.call(record_args(context, 1, 0.6))
    assert first["decision"]["status"] == "accept"
    assert first["best_metric"] == 0.6

    assert {:ok, second} = CkLoop.call(record_args(context, 2, 0.9))
    assert second["decision"]["status"] == "awaiting_review"
    assert second["status"] == "awaiting_review"

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(record_args(context, 3, 0.95))
    assert message =~ "no longer active"
  end

  test "blocks evaluation when verifier files drift", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    File.write!(Path.join(context.root, "test/verifier.exs"), "assert false\n")
    assert {:ok, result} = CkLoop.call(record_args(context, 1, 0.9))
    assert result["decision"]["status"] == "blocked"
    assert result["decision"]["reason"] == "verifier_drift"
  end

  test "stops after the configured no-progress limit", context do
    assert {:ok, _} = CkLoop.call(create_args(context) |> Map.put("no_progress_limit", 2))
    assert {:ok, _} = CkLoop.call(record_args(context, 1, 0.5))
    assert {:ok, second} = CkLoop.call(record_args(context, 2, 0.4))
    assert second["decision"]["status"] == "reject"
    assert {:ok, third} = CkLoop.call(record_args(context, 3, 0.3))
    assert third["decision"]["status"] == "stopped"
    assert third["decision"]["reason"] == "no_progress_limit"
    assert third["decision"]["rollback_required"]
  end

  test "blocked session findings stop progression", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    finding_fixture(%{session: context.session, status: "blocked"})
    assert {:ok, result} = CkLoop.call(record_args(context, 1, 0.6))
    assert result["decision"]["status"] == "blocked"
    assert result["decision"]["reason"] == "blocked_finding"
  end

  test "hard cost limit wins even when the target metric is reached", context do
    assert {:ok, _} = CkLoop.call(create_args(context) |> Map.put("max_cost_cents", 4))
    assert {:ok, result} = CkLoop.call(record_args(context, 1, 0.9))
    assert result["decision"]["status"] == "stopped"
    assert result["decision"]["reason"] == "cost_limit"
  end

  test "non-improving limit stops require rollback", context do
    assert {:ok, _} = CkLoop.call(create_args(context) |> Map.put("max_cost_cents", 6))
    assert {:ok, _} = CkLoop.call(record_args(context, 1, 0.5))
    assert {:ok, result} = CkLoop.call(record_args(context, 2, 0.4))
    assert result["decision"]["status"] == "stopped"
    assert result["decision"]["reason"] == "cost_limit"
    assert result["decision"]["rollback_required"]
  end

  test "supports minimization objectives", context do
    args =
      create_args(context)
      |> Map.put("direction", "minimize")
      |> Map.put("target", 0.1)

    assert {:ok, _} = CkLoop.call(args)
    assert {:ok, first} = CkLoop.call(record_args(context, 1, 0.5))
    assert first["decision"]["status"] == "accept"
    assert {:ok, second} = CkLoop.call(record_args(context, 2, 0.6))
    assert second["decision"]["status"] == "reject"
  end

  test "rejects out-of-order iteration evidence", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    assert {:error, {:invalid_arguments, message}} = CkLoop.call(record_args(context, 2, 0.6))
    assert message =~ "iteration must be 1"
  end

  test "rejects iteration changes outside the mutable boundary", context do
    assert {:ok, _} = CkLoop.call(create_args(context))

    args = record_args(context, 1, 0.6) |> Map.put("changed_paths", ["test/verifier.exs"])
    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "exceed mutable_paths"
  end

  test "rejects reused sandbox environments", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    assert {:ok, _} = CkLoop.call(record_args(context, 1, 0.5))

    args = record_args(context, 2, 0.6) |> Map.put("environment_id", "sandbox-1")
    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "unique"
  end

  test "requires explicit lasting-code policy", context do
    args = create_args(context) |> Map.put("artifact_class", "lasting_code")

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "invariant_boundaries"
  end

  test "rejects unknown artifact classes", context do
    args = create_args(context) |> Map.put("artifact_class", "productionish")
    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "artifact_class"
  end

  test "rejects metric improvement that exceeds a lasting-code complexity budget", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args =
      lasting_record_args(context, 1, 0.9)
      |> put_in(["complexity_delta", "fallback_branches"], 2)

    assert {:ok, result} = CkLoop.call(args)
    assert result["decision"]["status"] == "reject"
    assert result["decision"]["reason"] == "complexity_budget_exceeded"
  end

  test "rejects machine-dependent lasting code before target success", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args = lasting_record_args(context, 1, 0.9) |> Map.put("machine_independence_verified", false)
    assert {:ok, result} = CkLoop.call(args)
    assert result["decision"]["status"] == "reject"
    assert result["decision"]["reason"] == "machine_independence_failed"
  end

  test "counts accepted structural growth against the immutable budget", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, first} = CkLoop.call(lasting_record_args(context, 1, 0.5))
    assert first["decision"]["status"] == "accept"

    assert {:ok, second} = CkLoop.call(lasting_record_args(context, 2, 0.6))
    assert second["decision"]["status"] == "reject"
    assert second["decision"]["reason"] == "complexity_budget_exceeded"
  end

  test "stops after repeated local-defense attempts", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    first =
      lasting_record_args(context, 1, 0.6) |> Map.put("invariant_effect", "local_defense_added")

    assert {:ok, first_result} = CkLoop.call(first)
    assert first_result["decision"]["status"] == "reject"

    second =
      lasting_record_args(context, 2, 0.7) |> Map.put("invariant_effect", "local_defense_added")

    assert {:ok, second_result} = CkLoop.call(second)
    assert second_result["decision"]["status"] == "stopped"
    assert second_result["decision"]["reason"] == "local_defense_limit"
  end

  test "safe lasting code reaches independent review with comprehension evidence", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, result} = CkLoop.call(lasting_record_args(context, 1, 0.9))
    assert result["decision"]["status"] == "awaiting_review"
    assert hd(result["iterations"])["call_graph"] == "CLI -> Runtime -> Store"
    assert hd(result["iterations"])["machine_independence_verified"]

    stop =
      Mission.list_task_checkpoints(context.session.id, context.task.id)
      |> Enum.find(&(&1.checkpoint_type == "bounded_loop_stop"))

    assert stop.payload["promotion_packet"]["owning_invariant"] ==
             "Only validated state reaches storage"
  end

  test "lasting code cannot reach its target without a structured promotion packet", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    args = lasting_record_args(context, 1, 0.9) |> Map.delete("promotion_packet")

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "promotion_packet"
  end

  test "promotion packet rejects non-local citations", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args =
      lasting_record_args(context, 1, 0.9)
      |> put_in(["promotion_packet", "code_citations"], ["../outside.ex:1"])

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "path:line"
  end

  test "canonical model identity is derived from invocation schema fields", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args = lasting_record_args(context, 1, 0.9)

    {:ok, _result} = CkLoop.call(args)
    stop = stop_checkpoint(context)
    packet = stop.payload["promotion_packet"]

    assert packet["worker_identity"]["canonical_model_id"] == "openai/gpt-5.6-sol"
    assert packet["worker_identity"]["provider"] == "openai"
    assert packet["worker_identity"]["model"] == "gpt-5.6-sol"
  end

  test "promotion packet rejects citations beyond the current file", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args =
      lasting_record_args(context, 1, 0.9)
      |> put_in(["promotion_packet", "code_citations"], ["lib/example.ex:99"])

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "outside the file"
  end

  test "promotion packet rejects missing documentation evidence", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))

    args =
      lasting_record_args(context, 1, 0.9)
      |> put_in(["promotion_packet", "documentation_paths"], ["docs/missing.md"])

    assert {:error, {:invalid_arguments, message}} = CkLoop.call(args)
    assert message =~ "Evidence path must be a file"
  end

  test "lasting-code promotion requires checkpoint-bound ownership attestations", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, _} = CkLoop.call(lasting_record_args(context, 1, 0.9))

    stop =
      Mission.list_task_checkpoints(context.session.id, context.task.id)
      |> Enum.find(&(&1.checkpoint_type == "bounded_loop_stop"))

    review =
      review_fixture(%{
        session: context.session,
        task: context.task,
        review_type: "completion",
        submitted_by: "worker"
      })

    assert {:ok, _} =
             CkReviewFeedback.call(%{
               "review_id" => review.id,
               "decision" => "approved",
               "reviewed_by" => "independent-reviewer"
             })

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "ownership attestations"

    attested_review =
      review_fixture(%{
        session: context.session,
        task: context.task,
        review_type: "completion",
        submitted_by: "worker"
      })

    reviewer_identities = trusted_reviewers(context, diversified_reviewers())

    assert {:ok, _} =
             CkReviewFeedback.call(%{
               "review_id" => attested_review.id,
               "decision" => "approved",
               "reviewed_by" => "independent-reviewer",
               "annotations" => %{
                 "bounded_loop_stop_id" => stop.id,
                 "lasting_code_attestations" => %{
                   "architecture_understandable" => true,
                   "complexity_proportional" => true,
                   "invariants_mechanical" => true,
                   "ownership_accepted" => true,
                   "longevity_justified" => true
                 },
                 "reviewer_identities" => reviewer_identities
               }
             })

    assert {:ok, promoted} = CkLoop.call(promote_args(context, attested_review.id))
    assert promoted["status"] == "succeeded"
  end

  test "lasting-code promotion rejects evidence changed after target", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, _} = CkLoop.call(lasting_record_args(context, 1, 0.9))

    stop =
      Mission.list_task_checkpoints(context.session.id, context.task.id)
      |> Enum.find(&(&1.checkpoint_type == "bounded_loop_stop"))

    File.write!(Path.join(context.root, "docs/evidence.md"), "# Changed evidence\n")
    review = approved_attested_review(context, stop.id)

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "changed after target review"
  end

  test "high-risk promotion requires required personas and a different model", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, _} = CkLoop.call(lasting_record_args(context, 1, 0.9))
    stop = stop_checkpoint(context)

    same_model = [
      %{
        "agent_id" => "independent-reviewer",
        "provider" => "openai",
        "model" => "gpt-5.6-sol",
        "personas" => ["maintainability", "security"]
      }
    ]

    review = approved_attested_review(context, stop.id, same_model)

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "different model"

    missing_persona = [
      %{
        "agent_id" => "independent-reviewer",
        "provider" => "anthropic",
        "model" => "claude-sonnet-4.6",
        "personas" => ["maintainability"]
      }
    ]

    review = approved_attested_review(context, stop.id, missing_persona)

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "security"
  end

  test "critical promotion forbids every same-model reviewer", context do
    args = lasting_create_args(context) |> Map.put("review_risk", "critical")
    assert {:ok, _} = CkLoop.call(args)
    assert {:ok, _} = CkLoop.call(lasting_record_args(context, 1, 0.9))
    stop = stop_checkpoint(context)

    reviewers = [
      %{
        "agent_id" => "independent-reviewer",
        "provider" => "openai",
        "model" => "gpt-5.6-sol",
        "personas" => ["maintainability", "security"]
      }
    ]

    review = approved_attested_review(context, stop.id, reviewers)

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "forbids same-model"
  end

  test "reviewer identity cannot be the worker agent", context do
    assert {:ok, _} = CkLoop.call(lasting_create_args(context))
    assert {:ok, _} = CkLoop.call(lasting_record_args(context, 1, 0.9))
    stop = stop_checkpoint(context)

    reviewer = [
      %{
        "agent_id" => "worker-agent",
        "provider" => "anthropic",
        "model" => "claude-sonnet-4.6",
        "personas" => ["maintainability", "security"]
      }
    ]

    review = approved_attested_review(context, stop.id, reviewer, "worker-agent")

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(promote_args(context, review.id))

    assert message =~ "differ from the worker"
  end

  test "requires an independent approved review to promote", context do
    assert {:ok, _} = CkLoop.call(create_args(context))
    assert {:ok, _} = CkLoop.call(record_args(context, 1, 0.9))

    review =
      review_fixture(%{
        session: context.session,
        task: context.task,
        review_type: "completion",
        submitted_by: "worker"
      })

    assert {:error, {:invalid_arguments, message}} =
             CkLoop.call(%{
               "mode" => "promote",
               "session_id" => context.session.id,
               "task_id" => context.task.id,
               "review_id" => Integer.to_string(review.id)
             })

    assert message =~ "approved independent"

    assert {:ok, _} =
             CkReviewFeedback.call(%{
               "review_id" => review.id,
               "decision" => "approved",
               "reviewed_by" => "independent-reviewer"
             })

    assert {:ok, promoted} =
             CkLoop.call(%{
               "mode" => "promote",
               "session_id" => context.session.id,
               "task_id" => context.task.id,
               "review_id" => review.id
             })

    assert promoted["status"] == "succeeded"
    assert promoted["stop_reason"] == "independent_review_approved"
  end

  defp create_args(context) do
    %{
      "mode" => "create",
      "session_id" => context.session.id,
      "task_id" => context.task.id,
      "project_root" => context.root,
      "artifact_class" => "ephemeral_experiment",
      "mutable_paths" => ["lib"],
      "verifier_paths" => ["test/verifier.exs"],
      "verifier_command" => "mix test test/verifier.exs",
      "metric_name" => "quality",
      "direction" => "maximize",
      "target" => 0.9,
      "max_iterations" => 10,
      "max_cost_cents" => 100,
      "max_duration_seconds" => 600,
      "no_progress_limit" => 3,
      "allowed_sandbox_adapters" => ["docker", "e2b"],
      "require_ephemeral_environment" => true
    }
  end

  defp status_args(context) do
    %{"mode" => "status", "session_id" => context.session.id, "task_id" => context.task.id}
  end

  defp lasting_create_args(context) do
    create_args(context)
    |> Map.merge(%{
      "artifact_class" => "lasting_code",
      "invariant_boundaries" => ["Only validated state reaches storage"],
      "allowed_semantic_changes" => ["add validated operation"],
      "forbidden_semantic_changes" => ["accept malformed state"],
      "machine_independence_requirements" => ["mix test verifies behavior"],
      "review_risk" => "high",
      "required_review_personas" => ["maintainability", "security"],
      "complexity_budget" => %{
        "fallback_branches" => 1,
        "dependencies" => 0,
        "public_interfaces" => 1,
        "cyclomatic_complexity" => 3,
        "changed_lines" => 100
      },
      "local_defense_limit" => 2,
      "human_promotion_required" => true
    })
  end

  defp lasting_record_args(context, iteration, metric) do
    args =
      record_args(context, iteration, metric)
      |> Map.merge(%{
        "invariant_effect" => "strengthened",
        "invariant_evidence" => "Invalid state is rejected at the write boundary",
        "semantic_changes" => ["add validated operation"],
        "complexity_delta" => %{
          "fallback_branches" => 0,
          "dependencies" => 0,
          "public_interfaces" => 1,
          "cyclomatic_complexity" => 1,
          "changed_lines" => 25
        },
        "machine_independence_verified" => true,
        "machine_independence_evidence" => "mix test passed without model access",
        "call_graph" => "CLI -> Runtime -> Store",
        "diagnosis_path" => "Run mix test and inspect persisted checkpoint",
        "rollback_path" => "Restore the recorded iteration checkpoint",
        "maintenance_without_model" => "Tests and module contracts document the behavior"
      })

    if metric >= 0.9,
      do: Map.put(args, "promotion_packet", promotion_packet(context)),
      else: args
  end

  defp promotion_packet(context) do
    %{
      "worker_identity" => %{
        "agent_id" => "worker-agent",
        "invocation_id" => context.worker_invocation.id
      },
      "changed_behavior" => "Invalid state is rejected before persistence",
      "owning_invariant" => "Only validated state reaches storage",
      "bad_state_made_impossible" => "Malformed state cannot reach storage",
      "fallbacks_removed" => [],
      "affected_interfaces" => ["ControlKeel.Runtime.BoundedLoop.record/1"],
      "code_citations" => ["lib/example.ex:1-2"],
      "test_citations" => ["test/verifier.exs:1"],
      "test_commands" => ["mix test test/controlkeel/mcp/tools/ck_loop_test.exs"],
      "build_commands" => ["mix compile --warnings-as-errors"],
      "diagnosis_commands" => ["mix test --failed"],
      "rollback_commands" => ["restore the recorded iteration checkpoint"],
      "documentation_paths" => ["docs/evidence.md"]
    }
  end

  defp promote_args(context, review_id) do
    %{
      "mode" => "promote",
      "session_id" => context.session.id,
      "task_id" => context.task.id,
      "review_id" => review_id
    }
  end

  defp approved_attested_review(
         context,
         stop_id,
         reviewers \\ nil,
         reviewed_by \\ "independent-reviewer"
       ) do
    reviewer_identities = trusted_reviewers(context, reviewers || diversified_reviewers())

    review =
      review_fixture(%{
        session: context.session,
        task: context.task,
        review_type: "completion",
        submitted_by: "worker"
      })

    assert {:ok, _} =
             CkReviewFeedback.call(%{
               "review_id" => review.id,
               "decision" => "approved",
               "reviewed_by" => reviewed_by,
               "annotations" => %{
                 "bounded_loop_stop_id" => stop_id,
                 "lasting_code_attestations" => %{
                   "architecture_understandable" => true,
                   "complexity_proportional" => true,
                   "invariants_mechanical" => true,
                   "ownership_accepted" => true,
                   "longevity_justified" => true
                 },
                 "reviewer_identities" => reviewer_identities
               }
             })

    review
  end

  defp trusted_reviewers(context, reviewers) do
    Enum.map(reviewers, fn reviewer ->
      {:ok, invocation} =
        Mission.create_invocation(%{
          source: reviewer["agent_id"],
          tool: "bounded_loop_review",
          provider: reviewer["provider"],
          model: reviewer["model"],
          estimated_cost_cents: 0,
          decision: "allow",
          metadata: %{},
          session_id: context.session.id,
          task_id: context.task.id
        })

      %{
        "agent_id" => reviewer["agent_id"],
        "invocation_id" => invocation.id,
        "personas" => reviewer["personas"]
      }
    end)
  end

  defp diversified_reviewers do
    [
      %{
        "agent_id" => "independent-reviewer",
        "provider" => "anthropic",
        "model" => "claude-sonnet-4.6",
        "personas" => ["maintainability", "security"]
      }
    ]
  end

  defp stop_checkpoint(context) do
    Mission.list_task_checkpoints(context.session.id, context.task.id)
    |> Enum.find(&(&1.checkpoint_type == "bounded_loop_stop"))
  end

  defp record_args(context, iteration, metric) do
    %{
      "mode" => "record",
      "session_id" => context.session.id,
      "task_id" => context.task.id,
      "iteration" => iteration,
      "metric_value" => metric,
      "cost_cents" => 5,
      "changed_paths" => ["lib/example.ex"],
      "sandbox_adapter" => "docker",
      "environment_id" => "sandbox-#{iteration}",
      "hypothesis" => "Iteration #{iteration} should improve the metric",
      "mechanism" => "Adjust the bounded implementation",
      "observed_effect" => "Verifier returned #{metric}",
      "documentation_impact" => "No documentation change required",
      "verifier_passed" => true
    }
  end
end
