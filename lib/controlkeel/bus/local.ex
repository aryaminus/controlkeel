defmodule ControlKeel.Bus.Local do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def publish(topic, payload) do
    GenServer.cast(__MODULE__, {:publish, topic, payload})
    :ok
  end

  def publish_json(topic, payload) do
    publish(topic, Jason.encode!(payload))
  end

  def last_messages(limit \\ 50) do
    GenServer.call(__MODULE__, {:last_messages, limit})
  end

  @impl true
  def init(state), do: {:ok, Map.put(state, :messages, [])}

  @impl true
  def handle_cast({:publish, topic, payload}, state) do
    messages =
      [
        %{topic: topic, payload: payload, published_at: DateTime.utc_now()}
        | Map.get(state, :messages, [])
      ]
      |> Enum.take(100)

    {:noreply, Map.put(state, :messages, messages)}
  end

  @impl true
  def handle_call({:last_messages, limit}, _from, state) do
    {:reply, Map.get(state, :messages, []) |> Enum.take(limit), state}
  end
end
