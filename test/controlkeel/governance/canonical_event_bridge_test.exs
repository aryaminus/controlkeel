defmodule ControlKeel.Governance.CanonicalEventBridgeTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.CanonicalEventBridge

  describe "normalize_event_type/1" do
    test "maps t3code canonical events to CK namespace" do
      assert CanonicalEventBridge.normalize_event_type("request.opened") ==
               "ck.policy.check.request"

      assert CanonicalEventBridge.normalize_event_type("request.resolved") ==
               "ck.policy.check.resolution"

      assert CanonicalEventBridge.normalize_event_type("user-input.requested") ==
               "ck.hitl.input.requested"

      assert CanonicalEventBridge.normalize_event_type("turn.started") == "ck.turn.open"
      assert CanonicalEventBridge.normalize_event_type("turn.completed") == "ck.turn.close"
      assert CanonicalEventBridge.normalize_event_type("runtime.error") == "ck.incident.signal"

      assert CanonicalEventBridge.normalize_event_type("thread.token-usage.updated") ==
               "ck.budget.telemetry.input"
    end

    test "unknown types get ck.unmapped prefix" do
      assert CanonicalEventBridge.normalize_event_type("custom.event") ==
               "ck.unmapped.custom.event"
    end
  end

  describe "event_mapping/0" do
    test "returns all 7 canonical mappings" do
      mapping = CanonicalEventBridge.event_mapping()

      assert map_size(mapping) == 7
      assert Map.has_key?(mapping, "request.opened")
      assert Map.has_key?(mapping, "turn.started")
      assert Map.has_key?(mapping, "turn.completed")
    end
  end

  describe "ingest/2" do
    setup do
      start_supervised!(
        {ControlKeel.Governance.IdempotencyLedger, name: ControlKeel.Governance.IdempotencyLedger}
      )

      :ok
    end

    test "evaluates request.opened events" do
      {:ok, result} =
        CanonicalEventBridge.ingest(
          %{
            "type" => "request.opened",
            "id" => "req-#{System.unique_integer([:positive])}",
            "tool" => "file_read",
            "session_id" => nil
          },
          agent_id: "t3code"
        )

      assert result.action == :evaluate_request
      assert result.ck_event == "ck.policy.check.request"
      assert result.decision.decision in [:accept, :accept_for_session]
    end

    test "handles turn.started events" do
      {:ok, result} =
        CanonicalEventBridge.ingest(%{
          "type" => "turn.started",
          "id" => "turn-#{System.unique_integer([:positive])}",
          "threadId" => "thread-1",
          "turnId" => "turn-1"
        })

      assert result.action == :turn_opened
      assert result.thread_id == "thread-1"
      assert result.turn_id == "turn-1"
      assert result.ck_event == "ck.turn.open"
    end

    test "handles turn.completed events" do
      {:ok, result} =
        CanonicalEventBridge.ingest(%{
          "type" => "turn.completed",
          "id" => "turn-close-#{System.unique_integer([:positive])}",
          "threadId" => "thread-1",
          "turnId" => "turn-1"
        })

      assert result.action == :turn_closed
      assert result.ck_event == "ck.turn.close"
      assert Map.has_key?(result, :post_turn_validation)
    end

    test "handles runtime.error events" do
      {:ok, result} =
        CanonicalEventBridge.ingest(%{
          "type" => "runtime.error",
          "id" => "err-#{System.unique_integer([:positive])}",
          "error" => "something broke"
        })

      assert result.action == :incident_recorded
      assert result.error == "something broke"
    end

    test "handles unmapped events gracefully" do
      {:ok, result} =
        CanonicalEventBridge.ingest(%{
          "type" => "unknown.event",
          "id" => "unm-#{System.unique_integer([:positive])}"
        })

      assert result.action == :unmapped
      assert result.original_type == "unknown.event"
    end

    test "deduplicates identical events" do
      event = %{
        "type" => "runtime.error",
        "id" => "dedup-#{System.unique_integer([:positive])}",
        "error" => "test"
      }

      {:ok, _first} = CanonicalEventBridge.ingest(event)
      {:ok, second} = CanonicalEventBridge.ingest(event)

      assert second == :duplicate
    end
  end

  describe "ingest_batch/2" do
    setup do
      start_supervised!(
        {ControlKeel.Governance.IdempotencyLedger, name: ControlKeel.Governance.IdempotencyLedger}
      )

      :ok
    end

    test "processes multiple events" do
      events = [
        %{
          "type" => "turn.started",
          "id" => "b1-#{System.unique_integer([:positive])}",
          "threadId" => "t1",
          "turnId" => "tu1"
        },
        %{
          "type" => "request.opened",
          "id" => "b2-#{System.unique_integer([:positive])}",
          "tool" => "file_read"
        },
        %{
          "type" => "turn.completed",
          "id" => "b3-#{System.unique_integer([:positive])}",
          "threadId" => "t1",
          "turnId" => "tu1"
        }
      ]

      results = CanonicalEventBridge.ingest_batch(events, agent_id: "t3code")

      assert length(results) == 3

      [{_, {:ok, r1}}, {_, {:ok, r2}}, {_, {:ok, r3}}] = results
      assert r1.action == :turn_opened
      assert r2.action == :evaluate_request
      assert r3.action == :turn_closed
    end
  end
end
