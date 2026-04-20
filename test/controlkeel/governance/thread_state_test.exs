defmodule ControlKeel.Governance.ThreadStateTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Governance.ThreadState

  describe "list/2" do
    test "returns findings, reviews, and budget for a session" do
      session = session_fixture()
      _finding = finding_fixture(%{session: session})
      task = task_fixture(%{session: session})

      {:ok, _review} =
        ControlKeel.Mission.submit_review(%{
          "task_id" => task.id,
          "submission_body" => "Test review for thread state"
        })

      result = ThreadState.list(session.id)

      assert is_list(result.findings)
      assert is_list(result.reviews)
      assert is_map(result.budget)
      assert result.budget["event"] == "ck.budget.updated"
    end

    test "returns empty state for non-existent session" do
      result = ThreadState.list(999_999_999)

      assert result.findings == []
      assert result.reviews == []
      assert result.budget["session_budget_cents"] == 0
    end
  end

  describe "budget_summary/1" do
    test "returns budget snapshot for a session with budget" do
      session = session_fixture(%{budget_cents: 5000, spent_cents: 1200})

      budget = ThreadState.budget_summary(session.id)

      assert budget["session_budget_cents"] == 5000
      assert budget["spent_cents"] == 1200
      assert budget["remaining_session_cents"] == 3800
      assert budget["event"] == "ck.budget.updated"
    end
  end
end
