defmodule ControlKeel.Budget.TelemetryTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Budget.Telemetry

  describe "thresholds/0" do
    test "returns default thresholds" do
      thresholds = Telemetry.thresholds()

      assert Keyword.get(thresholds, :warn) == 0.5
      assert Keyword.get(thresholds, :high) == 0.8
      assert Keyword.get(thresholds, :critical) == 0.95
    end
  end

  describe "threshold_levels/0" do
    test "returns list of maps with level, ratio, and percentage" do
      levels = Telemetry.threshold_levels()

      assert is_list(levels)
      assert length(levels) >= 3

      for level <- levels do
        assert Map.has_key?(level, :level)
        assert Map.has_key?(level, :ratio)
        assert Map.has_key?(level, :percentage)
        assert level.ratio > 0
        assert level.ratio <= 1.0
      end
    end
  end

  describe "check/4" do
    test "returns nil when budget usage is below thresholds" do
      {:ok, result} = Telemetry.check(1, 2000, 100)

      assert result == nil
    end

    test "returns budget payload when session usage exceeds warn threshold" do
      {:ok, result} = Telemetry.check(1, 2000, 1200)

      assert result["event"] == "ck.budget.updated"
      assert result["spent_cents"] == 1200
      assert result["session_budget_cents"] == 2000
      assert result["remaining_session_cents"] == 800
    end

    test "returns payload at critical threshold" do
      {:ok, result} = Telemetry.check(1, 2000, 1950)

      assert result["event"] == "ck.budget.updated"
      assert result["spent_cents"] == 1950
    end

    test "handles zero budget gracefully" do
      {:ok, result} = Telemetry.check(1, 0, 0)

      assert result == nil
    end
  end

  describe "snapshot/4" do
    test "always returns a budget payload" do
      payload = Telemetry.snapshot(1, 2000, 500)

      assert payload["event"] == "ck.budget.updated"
      assert payload["session_budget_cents"] == 2000
      assert payload["spent_cents"] == 500
      assert payload["remaining_session_cents"] == 1500
      assert is_binary(payload["timestamp"])
    end

    test "includes daily budget when provided" do
      payload =
        Telemetry.snapshot(1, 2000, 500, daily_budget_cents: 5000, rolling_24h_cents: 1000)

      assert payload["remaining_daily_cents"] == 4000
    end
  end
end
