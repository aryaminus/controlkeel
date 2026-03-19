defmodule ControlKeel.BudgetTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  import ControlKeel.MissionFixtures
  import ControlKeel.PolicyTrainingFixtures

  test "estimate is read-only and commit writes an invocation plus spend" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 600, spent_cents: 200})
    task = task_fixture(%{session: session})

    assert {:ok, estimate} =
             Budget.estimate(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "estimated_cost_cents" => 150
             })

    assert estimate["recorded"] == false
    assert Repo.aggregate(Invocation, :count, :id) == 0

    assert {:ok, committed} =
             Budget.commit(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "estimated_cost_cents" => 150
             })

    assert committed["recorded"] == true
    assert Repo.aggregate(Invocation, :count, :id) == 1
    assert Mission.get_session!(session.id).spent_cents == 350
  end

  test "rejects unknown model pricing without explicit estimated cost" do
    session = session_fixture()

    assert {:error, {:invalid_arguments, message}} =
             Budget.estimate(%{
               "session_id" => session.id,
               "provider" => "anthropic",
               "model" => "unknown-model",
               "input_tokens" => 1_000,
               "output_tokens" => 100
             })

    assert message =~ "Unknown model pricing"
  end

  test "warns near the session cap and blocks above the rolling 24h cap" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 300, spent_cents: 750})

    assert {:ok, warning} =
             Budget.estimate(%{
               "session_id" => session.id,
               "estimated_cost_cents" => 60
             })

    assert warning["decision"] == "warn"

    recent = DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.truncate(:second)
    old = DateTime.utc_now() |> DateTime.add(-30, :hour) |> DateTime.truncate(:second)

    Repo.insert_all(Invocation, [
      %{
        session_id: session.id,
        source: "mcp",
        tool: "ck_budget",
        estimated_cost_cents: 250,
        decision: "allow",
        metadata: %{},
        inserted_at: recent,
        updated_at: recent
      },
      %{
        session_id: session.id,
        source: "mcp",
        tool: "ck_budget",
        estimated_cost_cents: 999,
        decision: "allow",
        metadata: %{},
        inserted_at: old,
        updated_at: old
      }
    ])

    assert Budget.rolling_24h_spend_cents(session.id) == 250

    assert {:ok, blocked} =
             Budget.estimate(%{
               "session_id" => session.id,
               "estimated_cost_cents" => 80
             })

    assert blocked["decision"] == "block"
    assert blocked["summary"] =~ "rolling 24-hour budget"
  end

  test "learned budget hints can upgrade allow to warn without changing hard caps" do
    _artifact =
      policy_artifact_fixture(%{
        artifact_type: "budget_hint",
        status: "active",
        version: 2
      })

    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 300})

    assert {:ok, estimate} =
             Budget.estimate(%{
               "session_id" => session.id,
               "provider" => "anthropic",
               "model" => "claude-sonnet-4-5",
               "input_tokens" => 2_500,
               "output_tokens" => 600,
               "estimated_cost_cents" => 220
             })

    assert estimate["decision"] == "warn"
    assert estimate["hint_source"] == "learned"
    assert estimate["hint_probability"] > 0.6
    assert estimate["artifact_version"] == 2
  end

  test "learned budget hints never weaken heuristic warn or block decisions" do
    _artifact =
      policy_artifact_fixture(%{
        artifact_type: "budget_hint",
        status: "active",
        version: 3,
        artifact: %{
          "schema_version" => 1,
          "artifact_type" => "budget_hint",
          "model_family" => "portable_linear_fallback",
          "feature_spec" => default_artifact_payload("budget_hint")["feature_spec"],
          "categorical_vocab" => default_artifact_payload("budget_hint")["categorical_vocab"],
          "normalization" => default_artifact_payload("budget_hint")["normalization"],
          "network" => %{
            "layers" => [
              %{
                "weights" => [List.duplicate(-5.0, 28)],
                "biases" => [-10.0],
                "activation" => "sigmoid"
              }
            ]
          },
          "thresholds" => %{"warn_probability" => 0.6},
          "metrics" => %{}
        }
      })

    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 1_000, spent_cents: 790})

    assert {:ok, warning} =
             Budget.estimate(%{
               "session_id" => session.id,
               "estimated_cost_cents" => 40
             })

    assert warning["decision"] == "warn"
    assert warning["hint_source"] in ["heuristic", "learned"]
  end
end
