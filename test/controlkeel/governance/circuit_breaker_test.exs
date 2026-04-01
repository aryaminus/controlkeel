defmodule ControlKeel.Governance.CircuitBreakerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.CircuitBreaker

  setup do
    start_supervised!(
      {CircuitBreaker,
       thresholds: %{
         api_calls_per_minute: 120,
         file_modifications_per_minute: 60,
         error_rate_percent: 50,
         consecutive_failures: 5
       }}
    )

    :ok
  end

  test "initial status is closed" do
    assert {:ok, status} = CircuitBreaker.check_status("agent_1")
    assert status.status == :closed
  end

  test "records events without tripping under threshold" do
    for _ <- 1..10 do
      CircuitBreaker.record_event("agent_1", :api_call)
    end

    {:ok, status} = CircuitBreaker.check_status("agent_1")
    assert status.status == :closed
  end

  test "trips on api_call threshold exceeded" do
    for _ <- 1..130 do
      CircuitBreaker.record_event("agent_2", :api_call)
    end

    {:ok, status} = CircuitBreaker.check_status("agent_2")
    assert status.status == :tripped
    assert status.trip_reason == :api_call_threshold_exceeded
  end

  test "trips on consecutive failures" do
    for _ <- 1..20 do
      CircuitBreaker.record_event("agent_3", :api_call)
    end

    for _ <- 1..6 do
      CircuitBreaker.record_event("agent_3", :error)
    end

    {:ok, status} = CircuitBreaker.check_status("agent_3")
    assert status.status == :tripped
    assert status.trip_reason == :consecutive_failure_threshold_exceeded
  end

  test "manual trip works" do
    assert {:ok, result} = CircuitBreaker.trip_breaker("agent_manual", "manual override")
    assert result.status == :tripped
    assert result.reason == "manual override"

    {:ok, status} = CircuitBreaker.check_status("agent_manual")
    assert status.status == :tripped
  end

  test "reset reopens the breaker" do
    CircuitBreaker.trip_breaker("agent_reset", "test")

    assert {:ok, result} = CircuitBreaker.reset_breaker("agent_reset")
    assert result.status == :closed

    {:ok, status} = CircuitBreaker.check_status("agent_reset")
    assert status.status == :closed
  end

  test "get_all_statuses returns per-agent status" do
    CircuitBreaker.record_event("tracked_agent", :api_call)
    CircuitBreaker.record_event("tracked_agent", :api_call)

    assert {:ok, statuses} = CircuitBreaker.get_all_statuses()
    assert is_list(statuses)
    assert Enum.any?(statuses, &(&1.agent_id == "tracked_agent"))
  end

  test "get_config returns current thresholds" do
    assert {:ok, config} = CircuitBreaker.get_config()
    assert is_map(config.thresholds)
    assert config.thresholds.api_calls_per_minute == 120
  end

  test "update_threshold changes a threshold" do
    assert {:ok, %{api_calls_per_minute: 200}} =
             CircuitBreaker.update_threshold(:api_calls_per_minute, 200)

    {:ok, config} = CircuitBreaker.get_config()
    assert config.thresholds.api_calls_per_minute == 200
  end

  test "trips on file_modification threshold exceeded" do
    for _ <- 1..65 do
      CircuitBreaker.record_event("agent_fm", :file_modification)
    end

    {:ok, status} = CircuitBreaker.check_status("agent_fm")
    assert status.status == :tripped
    assert status.trip_reason == :file_modification_threshold_exceeded
  end

  test "trips on error rate threshold exceeded" do
    for _ <- 1..3, do: CircuitBreaker.record_event("agent_err_rate", :api_call)
    for _ <- 1..4, do: CircuitBreaker.record_event("agent_err_rate", :error)

    {:ok, status} = CircuitBreaker.check_status("agent_err_rate")
    assert status.status == :tripped
    assert status.trip_reason == :error_rate_threshold_exceeded
  end

  test "trips on budget burn rate threshold exceeded" do
    for _ <- 1..9, do: CircuitBreaker.record_event("agent_budget", :api_call)
    for _ <- 1..2, do: CircuitBreaker.record_event("agent_budget", :budget_consumption)

    {:ok, status} = CircuitBreaker.check_status("agent_budget")
    assert status.status == :tripped
    assert status.trip_reason == :budget_burn_rate_threshold_exceeded
  end

  test "does not trip again once already tripped" do
    CircuitBreaker.trip_breaker("already_tripped", "test")
    CircuitBreaker.record_event("already_tripped", :error)

    {:ok, status} = CircuitBreaker.check_status("already_tripped")
    assert status.status == :tripped
  end
end
