defmodule ControlKeelWeb.ProxySocketController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Mission
  alias ControlKeel.Proxy

  @filtered_headers ~w(connection host sec-websocket-key sec-websocket-version sec-websocket-extensions upgrade)

  def openai_realtime(conn, %{"proxy_token" => proxy_token}) do
    with {:ok, session} <- fetch_proxy_session(proxy_token) do
      state = %{
        session: session,
        provider: :openai,
        upstream_path: "/v1/realtime",
        upstream_url: Proxy.websocket_upstream_url(:openai, "/v1/realtime", conn.query_string),
        headers: forwarded_headers(conn.req_headers),
        route: conn.request_path,
        preflight: nil,
        usage: nil,
        model: nil,
        committed?: false
      }

      WebSockAdapter.upgrade(conn, ControlKeelWeb.ProxyWebSock, state,
        timeout: Proxy.timeout_ms()
      )
    else
      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => %{"message" => "Proxy session not found"}})
    end
  end

  defp fetch_proxy_session(proxy_token) do
    case Mission.get_session_by_proxy_token(proxy_token) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  defp forwarded_headers(headers) do
    Enum.reject(headers, fn {key, _value} -> String.downcase(key) in @filtered_headers end)
  end
end
