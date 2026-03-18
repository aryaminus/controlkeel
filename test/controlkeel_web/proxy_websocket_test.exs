defmodule ControlKeelWeb.ProxyWebsocketTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Proxy
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, Proxy, [])

    on_exit(fn ->
      Application.put_env(:controlkeel, Proxy, previous)
    end)

    {:ok, upstream_pid} =
      start_supervised(
        {Bandit, plug: {__MODULE__.UpstreamPlug, test_pid: self()}, port: 0, startup_log: false}
      )

    {:ok, {_ip, upstream_port}} = ThousandIsland.listener_info(upstream_pid)

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(previous,
        openai_upstream: "http://127.0.0.1:#{upstream_port}",
        timeout_ms: 1_000
      )
    )

    {:ok, proxy_pid} =
      start_supervised({Bandit, plug: ControlKeelWeb.Endpoint, port: 0, startup_log: false})

    {:ok, {_ip, proxy_port}} = ThousandIsland.listener_info(proxy_pid)

    {:ok, proxy_port: proxy_port}
  end

  test "realtime websocket relays safe text frames and records usage", %{proxy_port: proxy_port} do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    {:ok, client} =
      __MODULE__.TestClient.start_link(
        "ws://127.0.0.1:#{proxy_port}/proxy/openai/#{session.proxy_token}/v1/realtime",
        self()
      )

    :ok =
      __MODULE__.TestClient.send_text(
        client,
        Jason.encode!(%{"mode" => "safe", "model" => "gpt-5.4-mini", "text" => "hello"})
      )

    assert_receive {:upstream_in, payload}, 1_000
    assert payload =~ "\"mode\":\"safe\""
    assert_receive {:client_text, text_frame}, 1_000
    assert text_frame =~ "\"safe text\""
    assert_receive {:client_text, usage_frame}, 1_000
    assert usage_frame =~ "\"usage\""
    assert_receive {:client_disconnect, {:remote, 1000, ""}}, 1_000
    assert Repo.aggregate(Invocation, :count, :id) == 1
    assert Mission.get_session!(session.id).spent_cents > 0
  end

  test "realtime websocket sends a policy error event and closes with 1008", %{
    proxy_port: proxy_port
  } do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    {:ok, client} =
      __MODULE__.TestClient.start_link(
        "ws://127.0.0.1:#{proxy_port}/proxy/openai/#{session.proxy_token}/v1/realtime",
        self()
      )

    :ok =
      __MODULE__.TestClient.send_text(
        client,
        Jason.encode!(%{"mode" => "block", "model" => "gpt-5.4-mini", "text" => "hello"})
      )

    assert_receive {:client_text, error_frame}, 1_000
    assert error_frame =~ "controlkeel_policy_violation"
    assert_receive {:client_disconnect, {:remote, 1008, _reason}}, 1_000
    assert Repo.aggregate(Invocation, :count, :id) == 1
  end

  defmodule UpstreamPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(%Plug.Conn{request_path: "/v1/realtime"} = conn, opts) do
      WebSockAdapter.upgrade(
        conn,
        ControlKeelWeb.ProxyWebsocketTest.UpstreamSock,
        %{test_pid: opts[:test_pid]},
        timeout: 1_000
      )
    end

    def call(conn, _opts), do: send_resp(conn, 404, "not found")
  end

  defmodule UpstreamSock do
    @behaviour WebSock

    def init(state), do: {:ok, state}

    def handle_in({payload, opcode: :text}, state) do
      send(state.test_pid, {:upstream_in, payload})

      case Jason.decode(payload) do
        {:ok, %{"mode" => "safe"}} ->
          safe =
            Jason.encode!(%{
              "type" => "response.output_text.delta",
              "text" => "safe text"
            })

          usage =
            Jason.encode!(%{
              "usage" => %{"input_tokens" => 12, "output_tokens" => 5}
            })

          {:stop, :normal, 1000, [{:text, safe}, {:text, usage}], state}

        {:ok, %{"mode" => "block"}} ->
          blocked =
            Jason.encode!(%{
              "type" => "response.output_text.delta",
              "text" => "AKIA1234567890ABCDEF"
            })

          {:stop, :normal, 1000, [{:text, blocked}], state}

        _other ->
          {:ok, state}
      end
    end

    def handle_info(_message, state), do: {:ok, state}
  end

  defmodule TestClient do
    use WebSockex

    def start_link(url, owner) do
      WebSockex.start(url, __MODULE__, owner)
    end

    def send_text(pid, payload) do
      WebSockex.cast(pid, {:send_text, payload})
    end

    @impl true
    def handle_connect(_conn, owner), do: {:ok, owner}

    @impl true
    def handle_cast({:send_text, payload}, owner), do: {:reply, {:text, payload}, owner}

    @impl true
    def handle_frame({:text, payload}, owner) do
      send(owner, {:client_text, payload})
      {:ok, owner}
    end

    def handle_frame(_frame, owner), do: {:ok, owner}

    @impl true
    def handle_disconnect(%{reason: reason}, owner) do
      send(owner, {:client_disconnect, reason})
      {:ok, owner}
    end
  end
end
