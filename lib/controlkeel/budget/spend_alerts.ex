defmodule ControlKeel.Budget.SpendAlerts do
  @moduledoc false

  use GenServer

  @check_interval_ms 60_000
  @alert_cooldown_ms 300_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def check_session(session_id) do
    GenServer.call(__MODULE__, {:check_session, session_id})
  end

  def register_callback(callback) do
    GenServer.call(__MODULE__, {:register_callback, callback})
  end

  def get_alerts(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_alerts, session_id, opts})
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :auto_check, true) do
      schedule_check()
    end

    {:ok,
     %{
       callbacks: Keyword.get(opts, :callbacks, []),
       alerts: [],
       last_alert_at: %{}
     }}
  end

  @impl true
  def handle_call({:check_session, session_id}, _from, state) do
    alert_result = do_check_session(session_id, state)
    new_state = record_alerts(state, alert_result)
    {:reply, alert_result, new_state}
  end

  @impl true
  def handle_call({:register_callback, callback}, _from, state) do
    {:reply, :ok, %{state | callbacks: [callback | state.callbacks]}}
  end

  @impl true
  def handle_call({:get_alerts, session_id, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)

    alerts =
      state.alerts
      |> Enum.filter(fn a -> is_nil(session_id) or a.session_id == session_id end)
      |> Enum.take(limit)

    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_info(:periodic_check, state) do
    schedule_check()
    {:noreply, state}
  end

  defp do_check_session(session_id, state) do
    alias ControlKeel.Budget
    alias ControlKeel.Mission

    case Mission.get_session(session_id) do
      nil ->
        {:ok, []}

      session ->
        budget_cents = session.budget_cents || 0
        spent_cents = session.spent_cents || 0
        daily_cents = session.daily_budget_cents || 0
        rolling = Budget.rolling_24h_spend_cents(session_id)

        alerts = []

        alerts =
          if budget_cents > 0 do
            ratio = spent_cents / budget_cents

            cond do
              ratio >= 1.0 ->
                [
                  %{
                    type: :budget_exceeded,
                    severity: :critical,
                    message:
                      "Session budget completely used ($#{spent_cents / 100} of $#{budget_cents / 100})",
                    ratio: ratio
                  }
                  | alerts
                ]

              ratio >= 0.95 ->
                [
                  %{
                    type: :budget_critical,
                    severity: :high,
                    message:
                      "Session budget almost gone (#{Float.round(ratio * 100, 1)}% used, $#{(budget_cents - spent_cents) / 100} remaining)",
                    ratio: ratio
                  }
                  | alerts
                ]

              ratio >= 0.8 ->
                [
                  %{
                    type: :budget_warning,
                    severity: :medium,
                    message:
                      "Session budget approaching limit (#{Float.round(ratio * 100, 1)}% used)",
                    ratio: ratio
                  }
                  | alerts
                ]

              ratio >= 0.5 ->
                [
                  %{
                    type: :budget_info,
                    severity: :low,
                    message: "Half of session budget used (#{Float.round(ratio * 100, 1)}%)",
                    ratio: ratio
                  }
                  | alerts
                ]

              true ->
                alerts
            end
          else
            alerts
          end

        alerts =
          if daily_cents > 0 and rolling > 0 do
            daily_ratio = rolling / daily_cents

            cond do
              daily_ratio >= 1.0 ->
                [
                  %{
                    type: :daily_exceeded,
                    severity: :critical,
                    message:
                      "Daily spending limit reached ($#{rolling / 100} of $#{daily_cents / 100})",
                    ratio: daily_ratio
                  }
                  | alerts
                ]

              daily_ratio >= 0.8 ->
                [
                  %{
                    type: :daily_warning,
                    severity: :medium,
                    message:
                      "Daily spending approaching limit (#{Float.round(daily_ratio * 100, 1)}%)",
                    ratio: daily_ratio
                  }
                  | alerts
                ]

              true ->
                alerts
            end
          else
            alerts
          end

        alerts =
          cond do
            rolling > 1000 and budget_cents > 0 ->
              burn_rate = rolling * 30 / budget_cents

              if burn_rate > 1.0 do
                [
                  %{
                    type: :burn_rate_high,
                    severity: :high,
                    message:
                      "Spending rate suggests budget will be exceeded in #{Float.round(1.0 / (burn_rate / 30), 1)} days at current pace",
                    ratio: burn_rate
                  }
                  | alerts
                ]
              else
                alerts
              end

            true ->
              alerts
          end

        now = DateTime.utc_now()

        fired =
          alerts
          |> Enum.filter(fn alert ->
            key = {session_id, alert.type}
            last = Map.get(state.last_alert_at, key)

            is_nil(last) or DateTime.diff(now, last, :millisecond) > @alert_cooldown_ms
          end)
          |> Enum.map(fn alert ->
            Map.merge(alert, %{
              session_id: session_id,
              timestamp: now,
              budget_cents: budget_cents,
              spent_cents: spent_cents,
              daily_budget_cents: daily_cents,
              rolling_24h_cents: rolling
            })
          end)

        {:ok, fired}
    end
  end

  defp record_alerts(state, {:ok, alerts}) do
    Enum.each(alerts, fn alert ->
      Enum.each(state.callbacks, fn cb ->
        Task.start(fn ->
          try do
            cb.(alert)
          rescue
            _ -> :ok
          end
        end)
      end)
    end)

    new_last_alert_at =
      alerts
      |> Enum.reduce(state.last_alert_at, fn alert, acc ->
        Map.put(acc, {alert.session_id, alert.type}, alert.timestamp)
      end)

    %{state | alerts: alerts ++ state.alerts, last_alert_at: new_last_alert_at}
  end

  defp record_alerts(state, _), do: state

  defp schedule_check do
    Process.send_after(self(), :periodic_check, @check_interval_ms)
  end
end
