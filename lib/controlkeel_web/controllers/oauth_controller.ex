defmodule ControlKeelWeb.OAuthController do
  use ControlKeelWeb, :controller

  alias ControlKeel.ProtocolAccess

  def token(conn, params) do
    with :ok <- require_grant_type(params),
         {:ok, client_id, client_secret} <- client_credentials(conn, params),
         {:ok, service_account} <- ProtocolAccess.authenticate_client(client_id, client_secret),
         {:ok, granted_scopes, resource} <-
           ProtocolAccess.grant_scopes(
             service_account,
             Map.get(params, "scope"),
             Map.get(params, "resource")
           ),
         {:ok, access_token, resource} <-
           ProtocolAccess.issue_access_token(service_account, granted_scopes, resource.id) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> json(%{
        access_token: access_token,
        token_type: "Bearer",
        expires_in: ProtocolAccess.token_ttl_seconds(),
        scope: Enum.join(granted_scopes, " "),
        resource: resource.audience
      })
    else
      {:error, :unsupported_grant_type} ->
        oauth_error(
          conn,
          :bad_request,
          "unsupported_grant_type",
          "Only client_credentials is supported."
        )

      {:error, :missing_client} ->
        oauth_error(conn, :unauthorized, "invalid_client", "Client credentials are required.")

      {:error, :unauthorized} ->
        oauth_error(conn, :unauthorized, "invalid_client", "Client credentials are invalid.")

      {:error, :invalid_scope} ->
        oauth_error(conn, :bad_request, "invalid_scope", "Requested scopes are not allowed.")

      {:error, :invalid_resource} ->
        oauth_error(conn, :bad_request, "invalid_target", "Requested resource is not supported.")
    end
  end

  defp require_grant_type(%{"grant_type" => "client_credentials"}), do: :ok
  defp require_grant_type(_params), do: {:error, :unsupported_grant_type}

  defp client_credentials(conn, params) do
    case parse_basic_auth(conn) do
      {:ok, client_id, client_secret} ->
        {:ok, client_id, client_secret}

      _ ->
        with client_id when is_binary(client_id) and client_id != "" <-
               Map.get(params, "client_id"),
             client_secret when is_binary(client_secret) and client_secret != "" <-
               Map.get(params, "client_secret") do
          {:ok, client_id, client_secret}
        else
          _ -> {:error, :missing_client}
        end
    end
  end

  defp parse_basic_auth(conn) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        with {:ok, decoded} <- Base.decode64(encoded),
             [client_id, client_secret] <- String.split(decoded, ":", parts: 2),
             true <- client_id != "" and client_secret != "" do
          {:ok, client_id, client_secret}
        else
          _ -> {:error, :missing_client}
        end

      _ ->
        {:error, :missing_client}
    end
  end

  defp oauth_error(conn, status, error, description) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("www-authenticate", ~s(Basic realm="controlkeel"))
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end
end
