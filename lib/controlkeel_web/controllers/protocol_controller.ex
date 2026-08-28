defmodule ControlKeelWeb.ProtocolController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Mcp.ProtocolAccess
  alias ControlKeel.Mcp.ProtocolInterop
  alias ControlKeel.Mcp.StreamableSessions

  @session_header "mcp-session-id"

  def mcp(conn, _params) do
    request = conn.body_params
    auth_context = conn.assigns.protocol_auth

    with :ok <- validate_session_header(conn, request) do
      case ProtocolInterop.handle_mcp_request(request, auth_context) do
        :no_response ->
          send_resp(conn, :accepted, "")

        response ->
          conn
          |> maybe_issue_session(request, response)
          |> maybe_put_protocol_error_status(response)
          |> json(response)
      end
    end
  end

  # Streamable HTTP (MCP 2025-03-26): the server assigns Mcp-Session-Id on
  # initialize; a client-present id on any later request MUST be known, else
  # 404. Requests without a header stay valid (stateless v1 clients).
  defp validate_session_header(_conn, %{"method" => "initialize"}), do: :ok

  defp validate_session_header(conn, _request) do
    case get_req_header(conn, @session_header) do
      [session_id | _] when session_id != "" ->
        if StreamableSessions.valid?(session_id) do
          :ok
        else
          conn
          |> put_status(:not_found)
          |> json(%{
            jsonrpc: "2.0",
            error: %{
              code: -32001,
              message: "MCP session not found or expired. Re-initialize the session."
            }
          })
          |> halt()
        end

      _ ->
        :ok
    end
  end

  defp maybe_issue_session(conn, %{"method" => "initialize"}, %{"result" => _result}) do
    case get_req_header(conn, @session_header) do
      [session_id | _] when session_id != "" ->
        # Client echoed an id it already holds: keep it valid.
        if StreamableSessions.valid?(session_id) do
          put_resp_header(conn, @session_header, session_id)
        else
          conn
        end

      _ ->
        put_resp_header(conn, @session_header, StreamableSessions.issue())
    end
  end

  defp maybe_issue_session(conn, _request, _response), do: conn

  def mcp_get(conn, _params) do
    # The server does not offer a GET SSE stream (spec-permitted); clients
    # MUST fall back to POST-only JSON responses.
    conn
    |> put_resp_header("allow", "POST, DELETE")
    |> put_status(:method_not_allowed)
    |> json(%{
      error: "method_not_allowed",
      message: "This MCP server uses POST-only JSON responses; GET streams are not offered."
    })
  end

  def mcp_delete(conn, _params) do
    case get_req_header(conn, @session_header) do
      [session_id | _] when session_id != "" ->
        StreamableSessions.terminate(session_id)
        send_resp(conn, :no_content, "")

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "session_not_found",
          message: "DELETE requires an #{Macro.camelize(@session_header)} header."
        })
    end
  end

  def protected_resource_mcp(conn, _params) do
    json(conn, ProtocolAccess.protected_resource_metadata("mcp"))
  end

  def protected_resource_alias(conn, _params) do
    json(conn, ProtocolAccess.protected_resource_metadata("mcp"))
  end

  def authorization_server(conn, _params) do
    json(conn, ProtocolAccess.authorization_server_metadata())
  end

  def a2a_card(conn, _params) do
    json(conn, ProtocolInterop.agent_card())
  end

  def a2a(conn, _params) do
    response = ProtocolInterop.handle_a2a_request(conn.body_params, conn.assigns.protocol_auth)

    conn
    |> maybe_put_protocol_error_status(response)
    |> json(response)
  end

  defp maybe_put_protocol_error_status(conn, %{"error" => %{"code" => -32001}}),
    do: put_status(conn, :forbidden)

  defp maybe_put_protocol_error_status(conn, _response), do: conn
end
