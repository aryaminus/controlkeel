defmodule ControlKeelWeb.ClientIp do
  import Bitwise

  @moduledoc """
  Derives a stable client-IP string for unauthenticated throttling.

  Two socket shapes reach a LiveView:

    * the HTTP dead render, where `connect_info` is the `%Plug.Conn{}`
    * the WebSocket mount, where `connect_info` is a map of the keys the
      endpoint forwards (`:peer_data`, `:x_headers`, `:session`)

  Forwarded headers are trusted only when the peer address matches an
  explicitly configured ingress address or CIDR (`:trusted_ingress_ips`), or
  when Fly proxy mode is enabled and the application listener is restricted to
  Fly Proxy's IPv4 connection path. Private or loopback address space alone
  does not establish trust. All other requests use the peer address directly.

  For configured ingress, `x-forwarded-for` is consulted. In Fly proxy mode,
  the endpoint copies Fly's `fly-client-ip` value into an `x-` header because
  Phoenix socket `:x_headers` drops headers without that prefix.

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
    peer_ip = normalize_mapped_ip(peer_ip)

    cond do
      fly_proxy_client_ip?(opts) -> parse_forwarded_header(headers, "x-fly-client-ip")
      trusted_ingress?(peer_ip, trusted_ingress_ips(opts)) -> parse_forwarded(headers)
      true -> nil
    end
  end

  defp forwarded_ip(_headers, _peer_ip, _opts), do: nil

  defp trusted_ingress_ips(opts) do
    Keyword.get_lazy(opts, :trusted_ingress_ips, fn ->
      Application.get_env(:controlkeel, __MODULE__, [])
      |> Keyword.get(:trusted_ingress_ips, [])
    end)
  end

  defp fly_proxy_client_ip?(opts) do
    Keyword.get_lazy(opts, :fly_proxy_client_ip, fn ->
      Application.get_env(:controlkeel, __MODULE__, [])
      |> Keyword.get(:fly_proxy_client_ip, false)
    end)
  end

  defp trusted_ingress?(peer_ip, entries) do
    Enum.any?(entries, fn
      {address, prefix} -> cidr_match?(peer_ip, address, prefix)
      address when is_tuple(address) -> normalize_mapped_ip(address) == peer_ip
    end)
  end

  defp cidr_match?(peer_ip, network, prefix) do
    peer_ip = normalize_mapped_ip(peer_ip)
    network = normalize_mapped_ip(network)

    with true <- tuple_size(peer_ip) == tuple_size(network),
         bits when prefix <= bits <- tuple_size(peer_ip) * 8 do
      shift = bits - prefix
      ip_to_integer(peer_ip) >>> shift == ip_to_integer(network) >>> shift
    else
      _ -> false
    end
  end

  defp ip_to_integer(address) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> (acc <<< 8) + part end)
  end

  defp normalize_mapped_ip({0, 0, 0, 0, 0, 65_535, high, low}) do
    {high >>> 8, band(high, 255), low >>> 8, band(low, 255)}
  end

  defp normalize_mapped_ip(address), do: address

  defp parse_forwarded(headers), do: parse_forwarded_header(headers, @forwarded_header)

  defp parse_forwarded_header(headers, header) do
    case List.keyfind(headers, header, 0) do
      {^header, value} ->
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
