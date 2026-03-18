defmodule ControlKeelWeb.Plugs.ApiAuth do
  @moduledoc false

  import Plug.Conn

  @doc """
  Checks for a Bearer token when `CONTROLKEEL_API_TOKEN` is set.
  When the env var is not set, all requests pass through (local dev default).
  Returns 401 JSON on mismatch.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case configured_token() do
      nil ->
        conn

      expected ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> provided] when provided == expected ->
            conn

          _ ->
            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{error: "unauthorized"})
            |> halt()
        end
    end
  end

  defp configured_token do
    Application.get_env(:controlkeel, :api_token)
  end
end
