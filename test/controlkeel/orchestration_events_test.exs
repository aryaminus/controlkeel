defmodule ControlKeel.OrchestrationEventsTest do
  use ExUnit.Case, async: true

  alias ControlKeel.OrchestrationEvents

  test "all event names use ck namespace" do
    for name <- OrchestrationEvents.all_event_names() do
      assert String.starts_with?(name, "ck.")
    end
  end

  test "finding payload includes required fields" do
    finding = %{
      severity: "high",
      rule_id: "SEC001",
      category: "security",
      plain_message: "SQL injection risk",
      decision: "block"
    }

    payload = OrchestrationEvents.finding_payload(finding)

    assert payload["event"] == "ck.finding.opened"
    assert payload["severity"] == "high"
    assert payload["rule_id"] == "SEC001"
    assert payload["category"] == "security"
    assert payload["decision"] == "block"
    assert is_binary(payload["timestamp"])
  end

  test "review payload maps status to correct event name" do
    review = %{id: 42, title: "Test review"}

    pending = OrchestrationEvents.review_payload(review, :pending)
    assert pending["event"] == "ck.review.pending"
    assert pending["review_id"] == 42

    approved = OrchestrationEvents.review_payload(review, :approved)
    assert approved["event"] == "ck.review.approved"

    denied = OrchestrationEvents.review_payload(review, :denied)
    assert denied["event"] == "ck.review.denied"
  end

  test "budget payload includes spend fields" do
    budget = %{
      session_budget_cents: 2000,
      spent_cents: 500,
      remaining_session_cents: 1500,
      remaining_daily_cents: 9500
    }

    payload = OrchestrationEvents.budget_payload(budget)

    assert payload["event"] == "ck.budget.updated"
    assert payload["session_budget_cents"] == 2000
    assert payload["spent_cents"] == 500
    assert payload["remaining_session_cents"] == 1500
    assert payload["remaining_daily_cents"] == 9500
  end

  test "turn payload produces open and close events" do
    open = OrchestrationEvents.turn_payload(:open, "thread-1", "turn-1")
    assert open["event"] == "ck.turn.opened"
    assert open["thread_id"] == "thread-1"

    close = OrchestrationEvents.turn_payload(:close, "thread-1", "turn-1")
    assert close["event"] == "ck.turn.closed"
  end

  test "policy check payload includes decision and rule IDs" do
    payload =
      OrchestrationEvents.policy_check_payload("req-1", "decline",
        rule_ids: ["SEC001", "OPS002"],
        reason: "blocked by policy"
      )

    assert payload["event"] == "ck.policy.check"
    assert payload["request_id"] == "req-1"
    assert payload["decision"] == "decline"
    assert payload["rule_ids"] == ["SEC001", "OPS002"]
    assert payload["reason"] == "blocked by policy"
  end

  test "proof payload includes type and reference" do
    payload = OrchestrationEvents.proof_payload(%{type: "session_summary", reference: "ref-abc"})

    assert payload["event"] == "ck.proof.ready"
    assert payload["proof_type"] == "session_summary"
    assert payload["reference"] == "ref-abc"
  end
end
