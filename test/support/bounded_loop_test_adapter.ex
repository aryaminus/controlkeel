defmodule ControlKeel.BoundedLoopTestAdapter do
  @behaviour ControlKeel.Runtime.BoundedLoopWorker
  @behaviour ControlKeel.Runtime.BoundedLoopVerifier
  @behaviour ControlKeel.Runtime.BoundedLoopRollback

  @impl true
  def run(context) do
    case Process.get(:bounded_loop_worker_error) do
      nil ->
        metrics = Process.get(:bounded_loop_metrics, [0.5])
        [metric | rest] = metrics
        Process.put(:bounded_loop_metrics, if(rest == [], do: [metric], else: rest))

        {:ok,
         %{
           "sandbox_adapter" => "docker",
           "environment_id" => "sandbox-#{context.iteration}",
           "changed_paths" => ["lib/example.ex"],
           "hypothesis" => "Iteration #{context.iteration} improves quality",
           "mechanism" => "Adjust implementation",
           "documentation_impact" => "No documentation impact",
           "observed_metric" => metric,
           "cost_cents" => 2
         }
         |> Map.merge(worker_longevity_evidence(context))}

      reason ->
        {:error, reason}
    end
  end

  @impl true
  def verify(_context, worker_result) do
    case Process.get(:bounded_loop_verifier_error) do
      nil ->
        metric = worker_result["observed_metric"]

        {:ok,
         %{
           "metric_value" => metric,
           "verifier_passed" => true,
           "observed_effect" => "Metric was #{metric}"
         }
         |> Map.merge(verifier_longevity_evidence(worker_result, metric))}

      reason ->
        {:error, reason}
    end
  end

  @impl true
  def prepare(context) do
    send(self(), {:prepared, context.iteration})
    {:ok, {:checkpoint, context.iteration}}
  end

  @impl true
  def rollback(context, checkpoint, reason) do
    send(self(), {:rolled_back, context.iteration, checkpoint, reason})

    case Process.get(:bounded_loop_rollback_error) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  defp worker_longevity_evidence(%{contract: %{"artifact_class" => "lasting_code"}}) do
    %{
      "semantic_changes" => ["add validated operation"],
      "call_graph" => "Coordinator -> Worker -> Candidate",
      "diagnosis_path" => "Run the verifier command",
      "rollback_path" => "Restore the prepared checkpoint",
      "maintenance_without_model" => "Use tests and module contracts"
    }
  end

  defp worker_longevity_evidence(_context), do: %{}

  defp verifier_longevity_evidence(%{"semantic_changes" => _}, metric) do
    evidence = %{
      "invariant_effect" => Process.get(:bounded_loop_invariant_effect, "strengthened"),
      "invariant_evidence" => "The write boundary rejects invalid state",
      "complexity_delta" => %{
        "fallback_branches" => 0,
        "dependencies" => 0,
        "public_interfaces" => 1,
        "cyclomatic_complexity" => 1,
        "changed_lines" => 20
      },
      "machine_independence_verified" => true,
      "machine_independence_evidence" => "Verifier ran without model access"
    }

    if metric >= 0.9,
      do: Map.put(evidence, "promotion_packet", promotion_packet()),
      else: evidence
  end

  defp verifier_longevity_evidence(_worker_result, _metric), do: %{}

  defp promotion_packet do
    %{
      "worker_identity" => %{
        "agent_id" => "worker-agent",
        "invocation_id" => Process.get(:bounded_loop_worker_invocation_id)
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
      "rollback_commands" => ["restore the prepared iteration checkpoint"],
      "documentation_paths" => ["docs/evidence.md"]
    }
  end
end
