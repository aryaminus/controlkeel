defmodule ControlKeelWeb.ProtocolController do
  use ControlKeelWeb, :controller

  alias ControlKeel.ProtocolAccess
  alias ControlKeel.ProtocolInterop

  def mcp(conn, _params) do
    request = conn.body_params
    auth_context = conn.assigns.protocol_auth

    case ProtocolInterop.handle_mcp_request(request, auth_context) do
      :no_response ->
        send_resp(conn, :accepted, "")

      response ->
        conn
        |> maybe_put_protocol_error_status(response)
        |> json(response)
    end
  end

  def mcp_get(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> put_status(:method_not_allowed)
    |> json(%{
      error: "method_not_allowed",
      message: "Hosted MCP uses stateless JSON-response POST requests in v1."
    })
  end

  def mcp_delete(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> put_status(:method_not_allowed)
    |> json(%{
      error: "method_not_allowed",
      message: "Hosted MCP does not expose session lifecycle endpoints in v1."
    })
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
