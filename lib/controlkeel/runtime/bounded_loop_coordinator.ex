defmodule ControlKeel.Runtime.BoundedLoopCoordinator do
  @moduledoc """
  Synchronous coordinator for approved bounded loops.

  The coordinator composes adapters and existing CK state. It is not a daemon,
  scheduler, worker implementation, verifier implementation, or retry service.
  """

  alias ControlKeel.Platform
  alias ControlKeel.Runtime.BoundedLoop

  @terminal_statuses ~w(awaiting_review succeeded stopped blocked)

  def run_once(session_id, task_id, opts) when is_integer(session_id) and is_integer(task_id) do
    with {:ok, adapters} <- adapters(opts),
         :ok <- not_cancelled(opts),
         {:ok, loop} <- BoundedLoop.status(base_args(session_id, task_id)),
         :ok <- active_loop(loop),
         :ok <- heartbeat(task_id, loop["iteration_count"], "preparing iteration"),
         context <- context(session_id, task_id, loop, opts),
         {:ok, checkpoint} <- adapters.rollback.prepare(context) do
      run_prepared(context, checkpoint, adapters, opts)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def run_once(_session_id, _task_id, _opts),
    do: {:error, {:invalid_arguments, "session_id and task_id must be integers"}}

  defp run_prepared(context, checkpoint, adapters, opts) do
    case execute_iteration(context, adapters, opts) do
      {:ok, result} ->
        with :ok <- maybe_rollback(result, context, checkpoint, adapters.rollback),
             do: {:ok, result}

      {:error, reason} ->
        rollback_after_error(context, checkpoint, adapters.rollback, reason)
    end
  end

  defp execute_iteration(context, adapters, opts) do
    try do
      with :ok <- not_cancelled(opts),
           {:ok, worker_result} <- adapters.worker.run(context),
           :ok <- heartbeat(context.task_id, context.iteration - 1, "verifying iteration"),
           {:ok, verifier_result} <- adapters.verifier.verify(context, worker_result),
           {:ok, result} <-
             BoundedLoop.record(record_arguments(context, worker_result, verifier_result)) do
        {:ok, result}
      end
    rescue
      error -> {:error, {:adapter_exception, Exception.message(error)}}
    catch
      kind, reason -> {:error, {:adapter_throw, kind, reason}}
    end
  end

  defp rollback_after_error(context, checkpoint, rollback, reason) do
    case rollback.rollback(context, checkpoint, "iteration_failed") do
      :ok ->
        {:error, reason}

      {:error, rollback_reason} ->
        handle_rollback({:error, rollback_reason}, context, "iteration_failed")
    end
  end

  def run_until_stop(session_id, task_id, opts) do
    with {:ok, loop} <- BoundedLoop.status(base_args(session_id, task_id)) do
      remaining = max(loop["contract"]["max_iterations"] - loop["iteration_count"], 0)
      do_run(session_id, task_id, opts, remaining, [])
    end
  end

  defp do_run(_session_id, _task_id, _opts, 0, results),
    do: {:ok, %{"status" => "stopped", "reason" => "iteration_bound", "results" => results}}

  defp do_run(session_id, task_id, opts, remaining, results) do
    case run_once(session_id, task_id, opts) do
      {:ok, %{"status" => status} = result} when status in @terminal_statuses ->
        {:ok, %{"status" => status, "results" => results ++ [result]}}

      {:ok, result} ->
        do_run(session_id, task_id, opts, remaining - 1, results ++ [result])

      {:error, reason} ->
        {:error, %{"reason" => inspect(reason), "results" => results}}
    end
  end

  defp adapters(opts) do
    worker = Keyword.get(opts, :worker)
    verifier = Keyword.get(opts, :verifier)
    rollback = Keyword.get(opts, :rollback)

    cond do
      not adapter?(worker, :run, 1) ->
        {:error, {:invalid_arguments, "worker adapter with run/1 is required"}}

      not adapter?(verifier, :verify, 2) ->
        {:error, {:invalid_arguments, "verifier adapter with verify/2 is required"}}

      not adapter?(rollback, :prepare, 1) or not adapter?(rollback, :rollback, 3) ->
        {:error,
         {:invalid_arguments, "rollback adapter with prepare/1 and rollback/3 is required"}}

      true ->
        {:ok, %{worker: worker, verifier: verifier, rollback: rollback}}
    end
  end

  defp adapter?(module, function, arity) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)

  defp adapter?(_module, _function, _arity), do: false

  defp not_cancelled(opts) do
    case Keyword.get(opts, :cancelled?, fn -> false end) do
      fun when is_function(fun, 0) ->
        if fun.(), do: {:error, :cancelled}, else: :ok

      _ ->
        {:error, {:invalid_arguments, "cancelled? must be a zero-arity function"}}
    end
  end

  defp active_loop(%{"status" => "active"}), do: :ok
  defp active_loop(%{"status" => status}), do: {:error, {:loop_not_active, status}}

  defp heartbeat(task_id, iteration_count, note) do
    case Platform.heartbeat_task(task_id, nil, %{
           "progress" => "iteration_#{iteration_count + 1}",
           "note" => note
         }) do
      {:ok, _run} -> :ok
      {:error, reason} -> {:error, {:heartbeat_failed, reason}}
    end
  end

  defp context(session_id, task_id, loop, opts) do
    %{
      session_id: session_id,
      task_id: task_id,
      project_root: Path.expand(Keyword.get(opts, :project_root, File.cwd!())),
      iteration: loop["iteration_count"] + 1,
      contract: loop["contract"],
      loop: loop
    }
  end

  defp record_arguments(context, worker, verifier) do
    base = %{
      "mode" => "record",
      "session_id" => context.session_id,
      "task_id" => context.task_id,
      "iteration" => context.iteration,
      "metric_value" => verifier["metric_value"],
      "verifier_passed" => verifier["verifier_passed"],
      "observed_effect" => verifier["observed_effect"],
      "cost_cents" => Map.get(worker, "cost_cents", 0),
      "changed_paths" => worker["changed_paths"],
      "sandbox_adapter" => worker["sandbox_adapter"],
      "environment_id" => worker["environment_id"],
      "hypothesis" => worker["hypothesis"],
      "mechanism" => worker["mechanism"],
      "documentation_impact" => worker["documentation_impact"],
      "summary" => Map.get(worker, "summary", "")
    }

    if context.contract["artifact_class"] == "lasting_code" do
      strict = %{
        "invariant_effect" => verifier["invariant_effect"],
        "invariant_evidence" => verifier["invariant_evidence"],
        "semantic_changes" => worker["semantic_changes"],
        "complexity_delta" => verifier["complexity_delta"],
        "machine_independence_verified" => verifier["machine_independence_verified"],
        "machine_independence_evidence" => verifier["machine_independence_evidence"],
        "call_graph" => worker["call_graph"],
        "diagnosis_path" => worker["diagnosis_path"],
        "rollback_path" => worker["rollback_path"],
        "maintenance_without_model" => worker["maintenance_without_model"]
      }

      strict =
        if is_map(verifier["promotion_packet"]),
          do: Map.put(strict, "promotion_packet", verifier["promotion_packet"]),
          else: strict

      Map.merge(base, strict)
    else
      base
    end
  end

  defp maybe_rollback(
         %{"decision" => %{"rollback_required" => true, "reason" => reason}},
         context,
         checkpoint,
         rollback
       ),
       do: handle_rollback(rollback.rollback(context, checkpoint, reason), context, reason)

  defp maybe_rollback(_result, _context, _checkpoint, _rollback), do: :ok

  defp handle_rollback(:ok, _context, _reason), do: :ok

  defp handle_rollback({:error, rollback_reason}, context, reason) do
    _ =
      BoundedLoop.stop(%{
        "session_id" => context.session_id,
        "task_id" => context.task_id,
        "reason" => "rollback_failed_after_#{reason}"
      })

    {:error, {:rollback_failed, rollback_reason}}
  end

  defp base_args(session_id, task_id),
    do: %{"session_id" => session_id, "task_id" => task_id, "mode" => "status"}
end
