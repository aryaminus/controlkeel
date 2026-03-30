defmodule ControlKeel.Governance.AgentMonitor do
  @moduledoc false

  use GenServer

  @max_events_per_agent 200
  @prune_interval_ms 30_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def track(agent_id, event_type, opts \\ []) do
    GenServer.cast(__MODULE__, {:track, agent_id, event_type, opts})
  end

  def get_events(agent_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_events, agent_id, opts})
  end

  def get_active_agents do
    GenServer.call(__MODULE__, :get_active_agents)
  end

  def get_feed(opts \\ []) do
    GenServer.call(__MODULE__, {:get_feed, opts})
  end

  @impl true
  def init(_opts) do
    schedule_prune()
    {:ok, %{agents: %{}, callbacks: []}}
  end

  @impl true
  def handle_cast({:track, agent_id, event_type, opts}, state) do
    now = DateTime.utc_now()
    metadata = Keyword.get(opts, :metadata, %{})
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)

    event = %{
      id: System.unique_integer([:positive]),
      agent_id: agent_id,
      event_type: event_type,
      session_id: session_id,
      task_id: task_id,
      metadata: metadata,
      timestamp: now
    }

    agent_events =
      state.agents
      |> Map.get(agent_id, [])
      |> then(fn events ->
        [event | events] |> Enum.take(@max_events_per_agent)
      end)

    new_agents = Map.put(state.agents, agent_id, agent_events)

    Enum.each(state.callbacks, fn cb ->
      Task.start(fn ->
        try do
          cb.(event)
        rescue
          _ -> :ok
        end
      end)
    end)

    {:noreply, %{state | agents: new_agents}}
  end

  @impl true
  def handle_call({:get_events, agent_id, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)
    event_type = Keyword.get(opts, :event_type)

    events =
      state.agents
      |> Map.get(agent_id, [])
      |> then(fn events ->
        case event_type do
          nil -> events
          type -> Enum.filter(events, fn e -> e.event_type == type end)
        end
      end)
      |> Enum.take(limit)

    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call(:get_active_agents, _from, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -300, :second)

    active =
      state.agents
      |> Enum.map(fn {agent_id, events} ->
        latest = List.first(events)
        event_count = length(events)

        recent_events =
          events
          |> Enum.filter(fn e ->
            DateTime.compare(e.timestamp, cutoff) in [:gt, :eq]
          end)
          |> length()

        %{
          agent_id: agent_id,
          last_event: latest,
          total_events: event_count,
          recent_events_5min: recent_events,
          status: if(recent_events > 0, do: :active, else: :idle)
        }
      end)
      |> Enum.sort_by(& &1.recent_events_5min, :desc)

    {:reply, {:ok, active}, state}
  end

  @impl true
  def handle_call({:get_feed, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)

    all_events =
      state.agents
      |> Enum.flat_map(fn {_agent_id, events} -> events end)
      |> Enum.sort_by(fn e -> {e.timestamp, e.id} end, :desc)
      |> Enum.take(limit)

    {:reply, {:ok, all_events}, state}
  end

  @impl true
  def handle_info(:prune, state) do
    schedule_prune()

    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    pruned_agents =
      state.agents
      |> Enum.map(fn {agent_id, events} ->
        filtered =
          Enum.filter(events, fn e -> DateTime.compare(e.timestamp, cutoff) in [:gt, :eq] end)

        {agent_id, filtered}
      end)
      |> Enum.reject(fn {_agent_id, events} -> events == [] end)
      |> Map.new()

    {:noreply, %{state | agents: pruned_agents}}
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval_ms)
  end
end
