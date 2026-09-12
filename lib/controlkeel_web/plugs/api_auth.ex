defmodule ControlKeelWeb.Plugs.ApiAuth do
  @moduledoc false

  alias ControlKeel.Platform

  import Plug.Conn

  @doc """
  Checks for a Bearer token when `CONTROLKEEL_API_TOKEN` is set.
  When the env var is not set (local dev default), unauthenticated requests
  are only accepted from loopback peers; anything else gets a 403. Bound
  tokens are validated as bootstrap or service-account credentials.
  Returns 401 JSON on token mismatch.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        if configured_token() do
          unauthorized(conn)
        else
          # No token configured (local default). The API is still reachable,
          # but only from this machine — a server bound to a non-loopback
          # interface without a configured token must not serve remote peers.
          if loopback_peer?(conn) do
            conn
          else
            forbidden_nonlocal_peer(conn)
          end
        end

      provided ->
        cond do
          configured_token() && provided == configured_token() ->
            assign(conn, :api_auth, %{type: :bootstrap})

          true ->
            case Platform.authenticate_service_account(provided) do
              {:ok, service_account} ->
                assign(conn, :api_auth, %{
                  type: :service_account,
                  service_account: service_account
                })

              {:error, :unauthorized} ->
                unauthorized(conn)
            end
        end
    end
  end

  defp loopback_peer?(%Plug.Conn{remote_ip: {127, _, _, _}}), do: true
  defp loopback_peer?(%Plug.Conn{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}), do: true
  defp loopback_peer?(_conn), do: false

  defp configured_token do
    Application.get_env(:controlkeel, :api_token)
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> provided] when provided != "" -> provided
      _ -> nil
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end

  defp forbidden_nonlocal_peer(conn) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(%{error: "forbidden_nonlocal_peer"})
    |> halt()
  end
end
