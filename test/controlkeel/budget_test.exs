defmodule ControlKeel.BudgetTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  import ControlKeel.MissionFixtures

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
end
