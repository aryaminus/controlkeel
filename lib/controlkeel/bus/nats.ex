defmodule ControlKeel.Bus.Nats do
  @moduledoc false

  use GenServer

  @default_port 4222

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def publish(topic, payload) do
    GenServer.call(__MODULE__, {:publish, topic, payload})
  end

  def publish_json(topic, payload) do
    publish(topic, Jason.encode!(payload))
  end

  @impl true
  def init(state) do
    settings = Application.get_env(:controlkeel, __MODULE__, [])[:connection_settings] || []

    case Gnat.start_link(settings) do
      {:ok, conn} -> {:ok, Map.put(state, :conn, conn)}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def handle_call({:publish, topic, payload}, _from, %{conn: conn} = state) do
    reply =
      case Gnat.pub(conn, topic, payload) do
        :ok -> :ok
        {:error, _reason} = error -> error
      end

    {:reply, reply, state}
  end

  def connection_settings_from_env(url) when is_binary(url) do
    uri = URI.parse(url)
    [host: uri.host || "127.0.0.1", port: uri.port || @default_port]
  end
end
