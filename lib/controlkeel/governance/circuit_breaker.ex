defmodule ControlKeel.Governance.CircuitBreaker do
  @moduledoc false

  use GenServer

  @default_window_ms 60_000
  @default_thresholds %{
    api_calls_per_minute: 120,
    file_modifications_per_minute: 60,
    error_rate_percent: 50,
    consecutive_failures: 5,
    budget_burn_rate_percent_per_minute: 10
  }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def record_event(agent_id, event_type, opts \\ []) do
    GenServer.cast(__MODULE__, {:event, agent_id, event_type, opts})
  end

  def check_status(agent_id) do
    GenServer.call(__MODULE__, {:check_status, agent_id})
  end

  def trip_breaker(agent_id, reason) do
    GenServer.call(__MODULE__, {:trip, agent_id, reason})
  end

  def reset_breaker(agent_id) do
    GenServer.call(__MODULE__, {:reset, agent_id})
  end

  def get_all_statuses do
    GenServer.call(__MODULE__, :get_all_statuses)
  end

  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  def update_threshold(key, value) do
    GenServer.call(__MODULE__, {:update_threshold, key, value})
  end

  @impl true
  def init(opts) do
    thresholds = Keyword.get(opts, :thresholds, @default_thresholds)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)

    state = %{
      thresholds: Map.merge(@default_thresholds, thresholds),
      window_ms: window_ms,
      agents: %{},
      callbacks: Keyword.get(opts, :callbacks, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:event, agent_id, event_type, opts}, state) do
    now = System.monotonic_time(:millisecond)
    metadata = Keyword.get(opts, :metadata, %{})

    event = %{
      type: event_type,
      timestamp: now,
      metadata: metadata
    }

    agent_state =
      Map.get(state.agents, agent_id, %{events: [], breaker_tripped: false, trip_reason: nil})

    events = [event | agent_state.events]
    trimmed = trim_to_window(events, now, state.window_ms)

    new_agent_state =
      %{agent_state | events: trimmed}
      |> maybe_trip_breaker(state.thresholds)

    new_agents = Map.put(state.agents, agent_id, new_agent_state)

    if new_agent_state.breaker_tripped and not agent_state.breaker_tripped do
      notify_callbacks(state.callbacks, :breaker_tripped, agent_id, new_agent_state.trip_reason)
    end

    {:noreply, %{state | agents: new_agents}}
  end

  @impl true
  def handle_call({:check_status, agent_id}, _from, state) do
    agent_state =
      Map.get(state.agents, agent_id, %{breaker_tripped: false, events: [], trip_reason: nil})

    status = build_status(agent_id, agent_state, state)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:trip, agent_id, reason}, _from, state) do
    agent_state =
      Map.get(state.agents, agent_id, %{events: [], breaker_tripped: false, trip_reason: nil})

    new_agent_state = %{agent_state | breaker_tripped: true, trip_reason: reason}
    new_agents = Map.put(state.agents, agent_id, new_agent_state)

    notify_callbacks(state.callbacks, :breaker_tripped, agent_id, reason)

    {:reply, {:ok, %{agent_id: agent_id, status: :tripped, reason: reason}},
     %{state | agents: new_agents}}
  end

  @impl true
  def handle_call({:reset, agent_id}, _from, state) do
    agent_state =
      Map.get(state.agents, agent_id, %{events: [], breaker_tripped: false, trip_reason: nil})

    new_agent_state = %{agent_state | breaker_tripped: false, trip_reason: nil, events: []}
    new_agents = Map.put(state.agents, agent_id, new_agent_state)

    {:reply, {:ok, %{agent_id: agent_id, status: :closed}}, %{state | agents: new_agents}}
  end

  @impl true
  def handle_call(:get_all_statuses, _from, state) do
    statuses =
      state.agents
      |> Enum.map(fn {agent_id, agent_state} ->
        build_status(agent_id, agent_state, state)
      end)

    {:reply, {:ok, statuses}, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, {:ok, %{thresholds: state.thresholds, window_ms: state.window_ms}}, state}
  end

  @impl true
  def handle_call({:update_threshold, key, value}, _from, state) do
    new_thresholds = Map.put(state.thresholds, key, value)
    {:reply, {:ok, %{key => value}}, %{state | thresholds: new_thresholds}}
  end

  defp trim_to_window(events, now, window_ms) do
    cutoff = now - window_ms
    Enum.filter(events, fn e -> e.timestamp > cutoff end)
  end

  defp maybe_trip_breaker(agent_state, thresholds) do
    if agent_state.breaker_tripped do
      agent_state
    else
      events = agent_state.events

      api_calls = count_by_type(events, :api_call)
      file_mods = count_by_type(events, :file_modification)
      errors = count_by_type(events, :error)
      budget_events = count_by_type(events, :budget_consumption)
      total = max(length(events), 1)

      error_rate = errors / total * 100
      budget_rate = budget_events / total * 100
      consecutive = count_consecutive_failures(events)

      cond do
        api_calls > thresholds.api_calls_per_minute ->
          %{agent_state | breaker_tripped: true, trip_reason: :api_call_threshold_exceeded}

        file_mods > thresholds.file_modifications_per_minute ->
          %{
            agent_state
            | breaker_tripped: true,
              trip_reason: :file_modification_threshold_exceeded
          }

        error_rate > thresholds.error_rate_percent ->
          %{agent_state | breaker_tripped: true, trip_reason: :error_rate_threshold_exceeded}

        consecutive >= thresholds.consecutive_failures ->
          %{
            agent_state
            | breaker_tripped: true,
              trip_reason: :consecutive_failure_threshold_exceeded
          }

        budget_rate > thresholds.budget_burn_rate_percent_per_minute ->
          %{
            agent_state
            | breaker_tripped: true,
              trip_reason: :budget_burn_rate_threshold_exceeded
          }

        true ->
          agent_state
      end
    end
  end

  defp count_by_type(events, type) do
    Enum.count(events, fn e -> e.type == type end)
  end

  defp count_consecutive_failures([]), do: 0

  defp count_consecutive_failures(events) do
    events
    |> Enum.take_while(fn e -> e.type in [:error, :failure] end)
    |> length()
  end

  defp build_status(agent_id, agent_state, state) do
    events = agent_state.events

    %{
      agent_id: agent_id,
      status: if(agent_state.breaker_tripped, do: :tripped, else: :closed),
      trip_reason: agent_state.trip_reason,
      event_count: length(events),
      api_calls: count_by_type(events, :api_call),
      file_modifications: count_by_type(events, :file_modification),
      errors: count_by_type(events, :error),
      window_ms: state.window_ms,
      thresholds: state.thresholds
    }
  end

  defp notify_callbacks(callbacks, event, agent_id, reason) do
    Enum.each(callbacks, fn cb ->
      Task.start(fn ->
        try do
          cb.(event, agent_id, reason)
        rescue
          _ -> :ok
        end
      end)
    end)
  end
end
