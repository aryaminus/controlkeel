defmodule ControlKeelWeb.ClientIp do
  @moduledoc """
  Derives a stable client-IP string for unauthenticated throttling.

  Two socket shapes reach a LiveView:

    * the HTTP dead render, where `connect_info` is the `%Plug.Conn{}`
    * the WebSocket mount, where `connect_info` is a map of the keys the
      endpoint forwards (`:peer_data`, `:x_headers`, `:session`)

  Behind ControlKeel Cloud's edge proxy, `peer_data.address` is the proxy —
  not the visitor — so the proxy's `x-forwarded-for` header is preferred when
  the peer is a loopback/private address (see `private_ip?/1`). A direct
  client connection is never allowed to choose its own bucket with a forged
  header.

  Only `x-forwarded-for` is consulted: Phoenix's socket `:x_headers`
  connect-info drops headers without an `x-` prefix, so `fly-client-ip` can
  never reach the connected mount, and using it on one pass only would put the
  dead render and the WebSocket mount in different buckets.

  The rightmost hop is used. Proxies append to `x-forwarded-for`, so the
  leftmost value can be client-supplied; the rightmost is the address observed
  by the nearest proxy.

  This value is a rate-limit bucket key only. It is never used for
  authorization.
  """

  @forwarded_header "x-forwarded-for"

  @doc "Client IP string for a LiveView socket (dead render or connected mount)."
  @spec from_socket(Phoenix.LiveView.Socket.t()) :: String.t()
  def from_socket(%Phoenix.LiveView.Socket{private: %{connect_info: %Plug.Conn{} = conn}}),
    do: from_conn(conn)

  def from_socket(%Phoenix.LiveView.Socket{private: %{connect_info: info}}) when is_map(info) do
    peer_ip = peer_ip(info[:peer_data])
    forwarded_ip(info[:x_headers], peer_ip) || format_ip(peer_ip) || "unknown"
  end

  def from_socket(_socket), do: "unknown"

  @doc "Client IP string for a Plug connection (forwarded header wins behind a proxy)."
  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(%Plug.Conn{remote_ip: remote_ip} = conn) do
    forwarded_ip(conn.req_headers, remote_ip) || format_ip(remote_ip) || "unknown"
  end

  # ── Forwarded header ─────────────────────────────────────────────────

  # The header is only trusted when the peer really is a proxy on this host or
  # a private network (Fly 6PN, Docker, Kubernetes ingress, a local reverse
  # proxy). Otherwise a direct client could rotate the header to evade the
  # throttle.
  defp forwarded_ip(headers, peer_ip) when is_list(headers) and is_tuple(peer_ip) do
    if private_ip?(peer_ip) and List.keymember?(headers, @forwarded_header, 0) do
      parse_forwarded(headers)
    end
  end

  defp forwarded_ip(_headers, _peer_ip), do: nil

  defp parse_forwarded(headers) do
    case List.keyfind(headers, @forwarded_header, 0) do
      {@forwarded_header, value} ->
        value
        |> String.split(",")
        |> List.last()
        |> String.trim()
        |> blank_to_nil()

      nil ->
        nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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

  # ── Private ranges ───────────────────────────────────────────────────

  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, b, _, _}) when b in 16..31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({0, 0, 0, 0}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp private_ip?({fc, _, _, _, _, _, _, _}) when fc in 0xFC00..0xFDFF, do: true
  defp private_ip?({fe, _, _, _, _, _, _, _}) when fe in 0xFE80..0xFEBF, do: true
  defp private_ip?(_ip), do: false
end
