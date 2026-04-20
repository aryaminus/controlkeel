defmodule ControlKeel.Budget.Telemetry do
  @moduledoc false

  # Budget telemetry configuration and orchestration event emission.
  # Bridges CK's existing SpendAlerts with the OrchestrationEvents namespace
  # so budget state is visible in provider-neutral UI surfaces.

  alias ControlKeel.OrchestrationEvents

  @default_thresholds [warn: 0.5, high: 0.8, critical: 0.95]

  @doc """
  Get the configured thresholds for budget alerts.
  Returns a keyword list of atom -> ratio pairs.
  """
  def thresholds do
    case System.get_env("CK_BUDGET_THRESHOLDS") do
      nil ->
        @default_thresholds

      env ->
        parse_thresholds(env)
    end
  end

  @doc """
  Check budget state and return a telemetry payload suitable for
  orchestration event emission.

  Returns {:ok, payload} or {:ok, nil} if no alert is needed.
  """
  def check(_session_id, budget_cents, spent_cents, opts \\ []) do
    daily_cents = Keyword.get(opts, :daily_budget_cents, 0)
    rolling_24h = Keyword.get(opts, :rolling_24h_cents, 0)

    session_ratio = if budget_cents > 0, do: spent_cents / budget_cents, else: 0.0
    daily_ratio = if daily_cents > 0, do: rolling_24h / daily_cents, else: 0.0

    severity = highest_triggered_severity(session_ratio, daily_ratio)

    payload = %{
      session_budget_cents: budget_cents,
      spent_cents: spent_cents,
      remaining_session_cents: budget_cents - spent_cents,
      remaining_daily_cents: daily_cents - rolling_24h,
      session_usage_ratio: Float.round(session_ratio, 4),
      daily_usage_ratio: Float.round(daily_ratio, 4)
    }

    if severity != nil do
      {:ok, OrchestrationEvents.budget_payload(Map.put(payload, :severity, severity))}
    else
      {:ok, nil}
    end
  end

  @doc """
  Build a budget snapshot for orchestration emission regardless of threshold state.
  """
  def snapshot(_session_id, budget_cents, spent_cents, opts \\ []) do
    daily_cents = Keyword.get(opts, :daily_budget_cents, 0)
    rolling_24h = Keyword.get(opts, :rolling_24h_cents, 0)

    OrchestrationEvents.budget_payload(%{
      "session_budget_cents" => budget_cents,
      "spent_cents" => spent_cents,
      "remaining_session_cents" => budget_cents - spent_cents,
      "remaining_daily_cents" => daily_cents - rolling_24h
    })
  end

  @doc """
  Return the threshold level labels and ratios.
  """
  def threshold_levels do
    thresholds()
    |> Enum.map(fn {level, ratio} ->
      %{level: level, ratio: ratio, percentage: Float.round(ratio * 100, 1)}
    end)
  end

  defp highest_triggered_severity(session_ratio, daily_ratio) do
    max_ratio = max(session_ratio, daily_ratio)

    thresholds()
    |> Enum.reverse()
    |> Enum.find_value(fn {level, threshold} ->
      if max_ratio >= threshold, do: level
    end)
  end

  defp parse_thresholds(env) do
    env
    |> String.split(",")
    |> Enum.map(&parse_threshold/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> @default_thresholds
      parsed -> parsed
    end
  end

  defp parse_threshold(pair) do
    case String.split(pair, ":", parts: 2) do
      [level, ratio_str] ->
        case Float.parse(ratio_str) do
          {ratio, _} when ratio > 0 and ratio <= 1.0 ->
            try do
              {String.to_existing_atom(String.trim(level)), ratio}
            rescue
              ArgumentError -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end
end
