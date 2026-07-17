defmodule ControlKeel.Runtime.BoundedLoopCoordinatorTest do
  use ControlKeel.DataCase

  alias ControlKeel.{Mission, Platform}
  alias ControlKeel.Runtime.{BoundedLoop, BoundedLoopCoordinator}

  import ControlKeel.MissionFixtures

  setup do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "ready"})
    {:ok, _run} = Platform.claim_task(task.id, nil, %{"execution_mode" => "local"})

    root = Path.join(System.tmp_dir!(), "ck-coordinator-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))
    File.mkdir_p!(Path.join(root, "docs"))
    File.write!(Path.join(root, "lib/example.ex"), "defmodule Example do\nend\n")
    File.write!(Path.join(root, "test/verifier.exs"), "assert true\n")
    File.write!(Path.join(root, "docs/evidence.md"), "# Evidence\n")
    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, _} = BoundedLoop.create(contract_args(session, task, root))
    Process.delete(:bounded_loop_worker_error)
    Process.delete(:bounded_loop_rollback_error)
    Process.delete(:bounded_loop_invariant_effect)
    Process.delete(:bounded_loop_verifier_error)
    Process.delete(:bounded_loop_worker_invocation_id)
    Process.put(:bounded_loop_metrics, [0.5])

    {:ok, session: session, task: task, root: root}
  end

  test "runs one accepted iteration without rollback", context do
    assert {:ok, result} = run_once(context)
    assert result["decision"]["status"] == "accept"
    assert_received {:prepared, 1}
    refute_received {:rolled_back, _, _, _}
  end

  test "rolls back a rejected iteration", context do
    Process.put(:bounded_loop_metrics, [0.5, 0.4])
    assert {:ok, _} = run_once(context)
    assert {:ok, result} = run_once(context)
    assert result["decision"]["status"] == "reject"
    assert_received {:rolled_back, 2, {:checkpoint, 2}, "metric_not_improved"}
  end

  test "runs until the target awaits independent review", context do
    Process.put(:bounded_loop_metrics, [0.5, 0.9])

    assert {:ok, result} =
             BoundedLoopCoordinator.run_until_stop(
               context.session.id,
               context.task.id,
               coordinator_opts(context)
             )

    assert result["status"] == "awaiting_review"
    assert length(result["results"]) == 2
  end

  test "stops on worker adapter error without retrying", context do
    Process.put(:bounded_loop_worker_error, :provider_failed)
    assert {:error, :provider_failed} = run_once(context)
    assert_received {:prepared, 1}
    assert_received {:rolled_back, 1, {:checkpoint, 1}, "iteration_failed"}
  end

  test "rolls back when verifier adapter fails", context do
    Process.put(:bounded_loop_verifier_error, :verifier_failed)
    assert {:error, :verifier_failed} = run_once(context)
    assert_received {:rolled_back, 1, {:checkpoint, 1}, "iteration_failed"}
  end

  test "honors cancellation before preparing an iteration", context do
    opts = Keyword.put(coordinator_opts(context), :cancelled?, fn -> true end)

    assert {:error, :cancelled} =
             BoundedLoopCoordinator.run_once(context.session.id, context.task.id, opts)

    refute_received {:prepared, _}
  end

  test "rolls back cancellation after preparing an iteration", context do
    Process.put(:cancellation_checks, 0)

    cancelled? = fn ->
      checks = Process.get(:cancellation_checks, 0)
      Process.put(:cancellation_checks, checks + 1)
      checks > 0
    end

    opts = Keyword.put(coordinator_opts(context), :cancelled?, cancelled?)

    assert {:error, :cancelled} =
             BoundedLoopCoordinator.run_once(context.session.id, context.task.id, opts)

    assert_received {:prepared, 1}
    assert_received {:rolled_back, 1, {:checkpoint, 1}, "iteration_failed"}
  end

  test "stops the loop when a rejected iteration cannot be rolled back", context do
    Process.put(:bounded_loop_metrics, [0.5, 0.4])
    assert {:ok, _} = run_once(context)
    Process.put(:bounded_loop_rollback_error, :conflict)

    assert {:error, {:rollback_failed, :conflict}} = run_once(context)

    assert {:ok, status} =
             BoundedLoop.status(%{
               "session_id" => context.session.id,
               "task_id" => context.task.id
             })

    assert status["status"] == "stopped"
    assert status["stop_reason"] == "rollback_failed_after_metric_not_improved"
  end

  test "requires an explicit rollback adapter", context do
    opts = Keyword.delete(coordinator_opts(context), :rollback)

    assert {:error, {:invalid_arguments, message}} =
             BoundedLoopCoordinator.run_once(context.session.id, context.task.id, opts)

    assert message =~ "rollback adapter"
  end

  test "forwards strict lasting-code evidence from explicit adapters", context do
    task = task_fixture(%{session: context.session, status: "ready"})
    {:ok, _run} = Platform.claim_task(task.id, nil, %{"execution_mode" => "local"})
    put_worker_invocation(context.session, task)

    assert {:ok, _} =
             BoundedLoop.create(lasting_contract_args(context.session, task, context.root))

    Process.put(:bounded_loop_metrics, [0.9])

    assert {:ok, result} =
             BoundedLoopCoordinator.run_once(
               context.session.id,
               task.id,
               coordinator_opts(context)
             )

    assert result["status"] == "awaiting_review"
    assert hd(result["iterations"])["invariant_effect"] == "strengthened"
    assert hd(result["iterations"])["call_graph"] == "Coordinator -> Worker -> Candidate"
  end

  test "rolls back the candidate when a lasting-code safety stop fires", context do
    task = task_fixture(%{session: context.session, status: "ready"})
    {:ok, _run} = Platform.claim_task(task.id, nil, %{"execution_mode" => "local"})
    put_worker_invocation(context.session, task)

    assert {:ok, _} =
             BoundedLoop.create(lasting_contract_args(context.session, task, context.root))

    Process.put(:bounded_loop_metrics, [0.5])
    Process.put(:bounded_loop_invariant_effect, "local_defense_added")

    assert {:ok, result} =
             BoundedLoopCoordinator.run_once(
               context.session.id,
               task.id,
               coordinator_opts(context)
             )

    assert result["status"] == "stopped"
    assert_received {:rolled_back, 1, {:checkpoint, 1}, "local_defense_limit"}
  end

  defp run_once(context) do
    BoundedLoopCoordinator.run_once(
      context.session.id,
      context.task.id,
      coordinator_opts(context)
    )
  end

  defp coordinator_opts(context) do
    [
      worker: ControlKeel.BoundedLoopTestAdapter,
      verifier: ControlKeel.BoundedLoopTestAdapter,
      rollback: ControlKeel.BoundedLoopTestAdapter,
      project_root: context.root
    ]
  end

  defp contract_args(session, task, root) do
    %{
      "session_id" => session.id,
      "task_id" => task.id,
      "project_root" => root,
      "artifact_class" => "ephemeral_experiment",
      "mutable_paths" => ["lib"],
      "verifier_paths" => ["test/verifier.exs"],
      "verifier_command" => "external verifier adapter",
      "metric_name" => "quality",
      "direction" => "maximize",
      "target" => 0.9,
      "max_iterations" => 5,
      "max_cost_cents" => 100,
      "max_duration_seconds" => 600,
      "no_progress_limit" => 3,
      "allowed_sandbox_adapters" => ["docker"],
      "require_ephemeral_environment" => true
    }
  end

  defp lasting_contract_args(session, task, root) do
    contract_args(session, task, root)
    |> Map.merge(%{
      "artifact_class" => "lasting_code",
      "invariant_boundaries" => ["Only validated state reaches storage"],
      "allowed_semantic_changes" => ["add validated operation"],
      "forbidden_semantic_changes" => ["accept malformed state"],
      "machine_independence_requirements" => ["tests run without a model"],
      "review_risk" => "high",
      "required_review_personas" => ["maintainability", "security"],
      "complexity_budget" => %{
        "fallback_branches" => 0,
        "dependencies" => 0,
        "public_interfaces" => 1,
        "cyclomatic_complexity" => 2,
        "changed_lines" => 50
      },
      "local_defense_limit" => 1,
      "human_promotion_required" => true
    })
  end

  defp put_worker_invocation(session, task) do
    {:ok, invocation} =
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

    Process.put(:bounded_loop_worker_invocation_id, invocation.id)
  end
end
