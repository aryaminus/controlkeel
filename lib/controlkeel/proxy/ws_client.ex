defmodule ControlKeel.Proxy.WSClient do
  @moduledoc false

  use WebSockex

  def start_link(url, headers, owner) do
    conn = WebSockex.Conn.new(url, extra_headers: headers, insecure: true)
    WebSockex.start_link(conn, __MODULE__, %{owner: owner})
  end

  def send_text(pid, payload) do
    WebSockex.send_frame(pid, {:text, payload})
  end

  @impl true
  def handle_connect(_conn, state) do
    send(state.owner, {:proxy_ws_upstream_connected, self()})
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    send(state.owner, {:proxy_ws_upstream_frame, payload})
    {:ok, state}
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    send(state.owner, {:proxy_ws_upstream_disconnect, reason})
    {:ok, state}
  end
end
