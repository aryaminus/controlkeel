defmodule ControlKeelWeb.ClientIp do
  @moduledoc """
  Derives a stable client-IP string for unauthenticated throttling.

  Two socket shapes reach a LiveView:

    * the HTTP dead render, where `connect_info` is the `%Plug.Conn{}`
    * the WebSocket mount, where `connect_info` is a map of the keys the
      endpoint forwards (`:peer_data`, `:x_headers`, `:session`)

  Forwarded headers are trusted only when the peer address exactly matches an
  explicitly configured ingress address (`:trusted_ingress_ips`). Private or
  loopback address space alone does not establish that a peer is trusted. All
  other requests use the peer address directly.

  Only `x-forwarded-for` is consulted: Phoenix's socket `:x_headers`
  connect-info drops headers without an `x-` prefix, so `fly-client-ip` can
  never reach the connected mount, and using it on one pass only would put the
  dead render and the WebSocket mount in different buckets.

  The rightmost hop is used, matching the configured ingress contract: the
  ingress appends the address it observed to `x-forwarded-for`. The selected
  value must parse as an IP address and is normalized before use.

  This value is a rate-limit bucket key only. It is never used for
  authorization.
  """

  @forwarded_header "x-forwarded-for"

  @doc "Client IP string for a LiveView socket (dead render or connected mount)."
  @spec from_socket(Phoenix.LiveView.Socket.t()) :: String.t()
  def from_socket(socket, opts \\ [])

  def from_socket(%Phoenix.LiveView.Socket{private: %{connect_info: %Plug.Conn{} = conn}}, opts),
    do: from_conn(conn, opts)

  def from_socket(%Phoenix.LiveView.Socket{private: %{connect_info: info}}, opts)
      when is_map(info) do
    peer_ip = peer_ip(info[:peer_data])
    client_ip(info[:x_headers], peer_ip, opts)
  end

  def from_socket(_socket, _opts), do: "unknown"

  @doc "Client IP string for a Plug connection."
  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn, opts \\ [])

  def from_conn(%Plug.Conn{remote_ip: remote_ip} = conn, opts) do
    client_ip(conn.req_headers, remote_ip, opts)
  end

  # ── Forwarded header ─────────────────────────────────────────────────

  defp client_ip(headers, peer_ip, opts) do
    forwarded_ip(headers, peer_ip, opts) || format_ip(peer_ip) || "unknown"
  end

  defp forwarded_ip(headers, peer_ip, opts) when is_list(headers) and is_tuple(peer_ip) do
    if peer_ip in trusted_ingress_ips(opts), do: parse_forwarded(headers)
  end

  defp forwarded_ip(_headers, _peer_ip, _opts), do: nil

  defp trusted_ingress_ips(opts) do
    Keyword.get_lazy(opts, :trusted_ingress_ips, fn ->
      Application.get_env(:controlkeel, __MODULE__, [])
      |> Keyword.get(:trusted_ingress_ips, [])
    end)
  end

  defp parse_forwarded(headers) do
    case List.keyfind(headers, @forwarded_header, 0) do
      {@forwarded_header, value} ->
        value
        |> String.split(",")
        |> List.last()
        |> String.trim()
        |> parse_ip()

      nil ->
        nil
    end
  end

  defp parse_ip(""), do: nil

  defp parse_ip(value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> format_ip(address)
      {:error, _} -> nil
    end
  end

  # ── Peer address ─────────────────────────────────────────────────────

  defp peer_ip(%{address: address}) when is_tuple(address), do: address
  defp peer_ip(_peer_data), do: nil

  defp format_ip(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      address -> to_string(address)
    end
  end

  defp format_ip(_ip), do: nil
end
