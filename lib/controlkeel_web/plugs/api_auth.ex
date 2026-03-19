defmodule ControlKeelWeb.Plugs.ApiAuth do
  @moduledoc false

  alias ControlKeel.Platform

  import Plug.Conn

  @doc """
  Checks for a Bearer token when `CONTROLKEEL_API_TOKEN` is set.
  When the env var is not set, all requests pass through (local dev default).
  Returns 401 JSON on mismatch.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        if configured_token() do
          unauthorized(conn)
        else
          conn
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
                if configured_token() do
                  unauthorized(conn)
                else
                  unauthorized(conn)
                end
            end
        end
    end
  end

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
end
