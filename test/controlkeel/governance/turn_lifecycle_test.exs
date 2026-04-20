defmodule ControlKeel.Governance.TurnLifecycleTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.TurnLifecycle

  setup do
    start_supervised!({TurnLifecycle, name: TurnLifecycle})
    :ok
  end

  describe "open/4 and get_state/3" do
    test "opens a turn context and retrieves it" do
      turn = TurnLifecycle.open(1, "thread-1", "turn-1", agent_id: "t3code")

      assert turn.session_id == 1
      assert turn.thread_id == "thread-1"
      assert turn.turn_id == "turn-1"
      assert turn.agent_id == "t3code"
      assert turn.status == :open
      assert turn.decisions == []
      assert turn.evidence == []

      {:ok, state} = TurnLifecycle.get_state(1, "thread-1", "turn-1")
      assert state.turn_id == "turn-1"
    end

    test "returns error for non-existent turn" do
      assert {:error, :not_found} = TurnLifecycle.get_state(999, "none", "none")
    end
  end

  describe "record_decision/5" do
    test "records a decision within a turn" do
      TurnLifecycle.open(1, "thread-1", "turn-d")

      decision = %{decision: :accept, reason: "low risk", policy_rule_ids: []}
      {:ok, updated} = TurnLifecycle.record_decision(1, "thread-1", "turn-d", "req-1", decision)

      assert length(updated.decisions) == 1
      [d] = updated.decisions
      assert d.request_id == "req-1"
      assert d.decision.decision == :accept
    end

    test "returns error for non-existent turn" do
      assert {:error, :turn_not_found} =
               TurnLifecycle.record_decision(999, "none", "none", "r1", %{})
    end
  end

  describe "record_evidence/4" do
    test "accumulates evidence within a turn" do
      TurnLifecycle.open(1, "thread-1", "turn-e")

      {:ok, t1} =
        TurnLifecycle.record_evidence(1, "thread-1", "turn-e", %{type: :finding, severity: "high"})

      assert length(t1.evidence) == 1

      {:ok, t2} =
        TurnLifecycle.record_evidence(1, "thread-1", "turn-e", %{type: :review, status: "pending"})

      assert length(t2.evidence) == 2
    end
  end

  describe "close/4" do
    test "closes a turn and returns final state" do
      TurnLifecycle.open(1, "thread-1", "turn-c")
      TurnLifecycle.record_decision(1, "thread-1", "turn-c", "req-1", %{decision: :accept})
      TurnLifecycle.record_evidence(1, "thread-1", "turn-c", %{type: :finding})

      {:ok, final} = TurnLifecycle.close(1, "thread-1", "turn-c")

      assert final.status == :closed
      assert Map.has_key?(final, :closed_at)
      assert Map.has_key?(final, :summary)
      assert final.summary["decision_count"] == 1
      assert final.summary["evidence_count"] == 1
    end

    test "removes turn from active after close" do
      TurnLifecycle.open(1, "thread-1", "turn-rm")
      TurnLifecycle.close(1, "thread-1", "turn-rm")

      assert {:error, :not_found} = TurnLifecycle.get_state(1, "thread-1", "turn-rm")
    end
  end

  describe "active_turns/1" do
    test "lists only active turns for a session" do
      TurnLifecycle.open(1, "thread-a", "turn-a1")
      TurnLifecycle.open(1, "thread-a", "turn-a2")
      TurnLifecycle.open(2, "thread-b", "turn-b1")

      active = TurnLifecycle.active_turns(1)
      assert length(active) == 2
      assert Enum.all?(active, &(&1.session_id == 1))
    end
  end
end
