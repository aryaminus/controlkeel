defmodule ControlKeel.PolicyTrainingTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.MissionFixtures
  import ControlKeel.PolicyTrainingFixtures

  alias ControlKeel.Benchmark
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.PolicyTraining
  alias ControlKeel.PolicyTraining.{Artifact, Run}
  alias ControlKeel.Repo

  test "public suite listing hides the held-out policy suite but it remains loadable" do
    public_slugs = Benchmark.list_suites() |> Enum.map(& &1.slug)
    holdout = benchmark_suite_fixture("policy_holdout_v1")

    refute "policy_holdout_v1" in public_slugs
    assert holdout.slug == "policy_holdout_v1"
    assert get_in(holdout.metadata, ["internal"]) == true

    assert Enum.all?(holdout.scenarios, fn scenario ->
             metadata = scenario.metadata || %{}

             (scenario.split == "held_out" and
                metadata["task_type"]) &&
               metadata["risk_tier"] &&
               metadata["domain_pack"] &&
               metadata["budget_tier"]
           end)
  end

  test "router policy training persists a candidate artifact with held-out metrics" do
    benchmark_run_fixture(%{
      "suite" => "vibe_failures_v1",
      "subjects" => "controlkeel_validate,controlkeel_proxy",
      "baseline_subject" => "controlkeel_validate",
      "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
    })

    assert {:ok, artifact} = PolicyTraining.start_training(%{"type" => "router"})

    assert artifact.artifact_type == "router"
    assert artifact.status == "candidate"
    assert artifact.version >= 1
    assert artifact.training_run.status == "trained"
    assert get_in(artifact.metrics, ["held_out", "reward"]) != nil
    assert Map.has_key?(artifact.metadata, "source_suite_slugs")
    assert Repo.aggregate(Run, :count, :id) >= 1
    assert Repo.aggregate(Artifact, :count, :id) >= 1
  end

  test "budget hint training builds from invocation history and records metrics" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 600, spent_cents: 400})
    task = task_fixture(%{session: session})

    Repo.insert!(%Invocation{
      session_id: session.id,
      task_id: task.id,
      source: "mcp",
      tool: "ck_budget",
      provider: "anthropic",
      model: "claude-sonnet-4-5",
      input_tokens: 2_000,
      output_tokens: 500,
      estimated_cost_cents: 180,
      decision: "warn",
      metadata: %{}
    })

    assert {:ok, artifact} = PolicyTraining.start_training(%{"type" => "budget_hint"})

    assert artifact.artifact_type == "budget_hint"
    assert artifact.status == "candidate"
    assert get_in(artifact.metrics, ["held_out", "precision"]) != nil
    refute artifact.metadata["heuristically_seeded"]
  end

  test "failed promotion keeps the current active artifact" do
    active =
      policy_artifact_fixture(%{
        artifact_type: "router",
        status: "active",
        version: 1,
        metrics: %{"gates" => %{"eligible" => true, "reasons" => []}}
      })

    candidate =
      policy_artifact_fixture(%{
        artifact_type: "router",
        version: 2,
        metrics: %{
          "held_out" => %{"reward" => 0.8},
          "baseline" => %{"held_out" => %{"reward" => 1.0}},
          "gates" => %{
            "eligible" => false,
            "reasons" => ["held-out reward did not beat the heuristic baseline"]
          }
        }
      })

    assert {:error, {:promotion_failed, [_reason | _]}} =
             PolicyTraining.promote_artifact(candidate.id)

    assert PolicyTraining.active_artifact("router").id == active.id
    assert Repo.get!(Run, candidate.training_run_id).status == "promotion_failed"
  end

  test "invalid python path fails cleanly and marks the training run failed" do
    original = System.get_env("CONTROLKEEL_POLICY_TRAINING_PYTHON")
    System.put_env("CONTROLKEEL_POLICY_TRAINING_PYTHON", "/missing/python3")

    on_exit(fn ->
      if original do
        System.put_env("CONTROLKEEL_POLICY_TRAINING_PYTHON", original)
      else
        System.delete_env("CONTROLKEEL_POLICY_TRAINING_PYTHON")
      end
    end)

    assert {:error, :python_not_found} = PolicyTraining.start_training(%{"type" => "router"})

    latest_run =
      Run
      |> Repo.all()
      |> Enum.sort_by(& &1.id, :desc)
      |> List.first()

    assert latest_run.status == "failed"
    assert latest_run.failure_reason =~ "python_not_found"
  end
end
