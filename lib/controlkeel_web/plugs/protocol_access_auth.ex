defmodule ControlKeelWeb.Plugs.ProtocolAccessAuth do
  @moduledoc false

  import Plug.Conn

  alias ControlKeel.ProtocolAccess

  def init(opts), do: opts

  def call(conn, opts) do
    resource = Keyword.fetch!(opts, :resource)
    include_metadata = Keyword.get(opts, :include_resource_metadata, true)

    required_scopes =
      case ProtocolAccess.normalize_resource(resource) do
        {:ok, %{access_scope: scope}} -> [scope]
        _ -> []
      end

    with {:ok, token} <- bearer_token(conn),
         {:ok, auth_context} <-
           ProtocolAccess.verify_access_token(token, resource, required_scopes) do
      assign(conn, :protocol_auth, auth_context)
    else
      {:error, :missing_token} ->
        unauthorized(
          conn,
          resource,
          include_metadata,
          :invalid_token,
          "Bearer access token required."
        )

      {:error, :expired} ->
        unauthorized(conn, resource, include_metadata, :invalid_token, "Access token expired.")

      {:error, :unauthorized} ->
        unauthorized(conn, resource, include_metadata, :invalid_token, "Access token invalid.")

      {:error, :insufficient_scope} ->
        forbidden(conn, resource, include_metadata, "Access token missing the required scope.")

      {:error, :invalid_resource} ->
        forbidden(
          conn,
          resource,
          include_metadata,
          "Access token audience does not match this endpoint."
        )

      {:error, _reason} ->
        unauthorized(conn, resource, include_metadata, :invalid_token, "Access token invalid.")
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp unauthorized(conn, resource, include_metadata, error, description) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ProtocolAccess.challenge_header(resource,
        include_resource_metadata: include_metadata,
        error: Atom.to_string(error),
        error_description: description
      )
    )
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end

  defp forbidden(conn, resource, include_metadata, description) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ProtocolAccess.challenge_header(resource,
        include_resource_metadata: include_metadata,
        error: "insufficient_scope",
        error_description: description
      )
    )
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(%{error: "forbidden"})
    |> halt()
  end
end
