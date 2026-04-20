defmodule ControlKeel.Governance.IdempotencyLedgerTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.IdempotencyLedger

  setup do
    start_supervised!({IdempotencyLedger, name: IdempotencyLedger})
    :ok
  end

  describe "check_and_mark/1" do
    test "returns :new for first write and :duplicate for repeat" do
      key =
        IdempotencyLedger.build_key(%{
          session_id: 999_991,
          thread_id: "t1",
          turn_id: "turn1",
          event_id: "e#{System.unique_integer([:positive])}",
          event_type: "finding"
        })

      assert :new = IdempotencyLedger.check_and_mark(key)
      assert :duplicate = IdempotencyLedger.check_and_mark(key)
    end

    test "different keys are independent" do
      base = %{session_id: 999_992, thread_id: "t1"}

      key1 =
        IdempotencyLedger.build_key(Map.merge(base, %{event_id: "e1", event_type: "finding"}))

      key2 =
        IdempotencyLedger.build_key(Map.merge(base, %{event_id: "e2", event_type: "finding"}))

      assert :new = IdempotencyLedger.check_and_mark(key1)
      assert :new = IdempotencyLedger.check_and_mark(key2)
      assert :duplicate = IdempotencyLedger.check_and_mark(key1)
    end
  end

  describe "build_key/1" do
    test "builds deterministic key from map with atoms" do
      key =
        IdempotencyLedger.build_key(%{
          session_id: 1,
          thread_id: "t1",
          turn_id: "turn1",
          event_id: "e1",
          event_type: "finding.opened"
        })

      assert is_binary(key)
      assert key =~ "1:"
      assert key =~ "t1:"
      assert key =~ "finding.opened"
    end

    test "builds same key for atom and string keys" do
      atom_key = IdempotencyLedger.build_key(%{session_id: 1, thread_id: "t1", event_id: "e1"})

      string_key =
        IdempotencyLedger.build_key(%{"session_id" => 1, "thread_id" => "t1", "event_id" => "e1"})

      assert atom_key == string_key
    end

    test "builds same key with event_id or sequence" do
      with_event_id = IdempotencyLedger.build_key(%{session_id: 1, event_id: "e1"})
      with_sequence = IdempotencyLedger.build_key(%{session_id: 1, sequence: "e1"})

      assert with_event_id == with_sequence
    end

    test "passes through binary keys unchanged" do
      assert IdempotencyLedger.build_key("raw-key") == "raw-key"
    end
  end
end
