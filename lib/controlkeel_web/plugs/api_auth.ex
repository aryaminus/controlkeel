defmodule ControlKeelWeb.Plugs.ApiAuth do
  @moduledoc false

  alias ControlKeel.Platform
  alias ControlKeel.Runtime.Mode

  import Plug.Conn

  @doc """
  Authenticates service accounts in every mode. Bootstrap tokens and
  unauthenticated loopback access are available only in local mode.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        if Mode.current() != :local or configured_token() do
          unauthorized(conn)
        else
          # No token configured (local default). The API is still reachable,
          # but only from this machine — a server bound to a non-loopback
          # interface without a configured token must not serve remote peers.
          # The credential is recorded explicitly as `:local` so downstream
          # authorization can distinguish "authenticated loopback caller" from
          # "no credential was ever established" and fail closed on the latter.
          if loopback_peer?(conn) do
            assign(conn, :api_auth, %{type: :local})
          else
            forbidden_nonlocal_peer(conn)
          end
        end

      provided ->
        cond do
          Mode.current() == :local && configured_token() &&
              token_matches?(provided, configured_token()) ->
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

  # Constant-time comparison for the configured bootstrap token so a remote
  # caller cannot recover it byte-by-byte by measuring response latency.
  defp token_matches?(provided, configured)
       when is_binary(provided) and is_binary(configured) do
    byte_size(provided) == byte_size(configured) and
      Plug.Crypto.secure_compare(provided, configured)
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
