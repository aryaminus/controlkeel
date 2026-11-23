defmodule ControlKeelWeb.ClientIpTest do
  use ExUnit.Case, async: true

  alias ControlKeelWeb.ClientIp

  @trusted_ingress_ips [{10, 0, 0, 1}, {127, 0, 0, 1}]

  defp socket(connect_info) do
    %Phoenix.LiveView.Socket{private: %{connect_info: connect_info}}
  end

  defp socket_bucket(socket, ingress_ips \\ @trusted_ingress_ips) do
    ClientIp.from_socket(socket, trusted_ingress_ips: ingress_ips)
  end

  defp conn_bucket(conn, ingress_ips \\ @trusted_ingress_ips) do
    ClientIp.from_conn(conn, trusted_ingress_ips: ingress_ips)
  end

  describe "from_socket/1" do
    test "uses peer_data address from the WebSocket connect_info" do
      socket = socket(%{peer_data: %{address: {203, 0, 113, 7}}, x_headers: []})

      assert socket_bucket(socket) == "203.0.113.7"
    end

    test "distinct peer addresses yield distinct bucket keys" do
      a = socket(%{peer_data: %{address: {203, 0, 113, 7}}, x_headers: []})
      b = socket(%{peer_data: %{address: {203, 0, 113, 8}}, x_headers: []})

      refute socket_bucket(a) == socket_bucket(b)
    end

    test "uses the forwarded header from a configured ingress peer" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 1}},
          x_headers: [{"x-forwarded-for", "198.51.100.9"}]
        })

      assert socket_bucket(socket) == "198.51.100.9"
    end

    test "uses and normalizes the rightmost forwarded IP from configured ingress" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 1}},
          x_headers: [{"x-forwarded-for", "203.0.113.50, 198.51.100.9"}]
        })

      assert socket_bucket(socket) == "198.51.100.9"
    end

    test "ignores headers the socket connect_info cannot forward" do
      # Phoenix's :x_headers only carries "x-"-prefixed headers, so a
      # fly-client-ip-only socket must still bucket by the peer address.
      socket =
        socket(%{peer_data: %{address: {10, 0, 0, 1}}, x_headers: [{"fly-client-ip", "a"}]})

      assert socket_bucket(socket) == "10.0.0.1"
    end

    test "ignores forwarded headers from an unconfigured private peer" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 2}},
          x_headers: [{"x-forwarded-for", "198.51.100.9"}]
        })

      assert socket_bucket(socket) == "10.0.0.2"
    end

    test "falls back to the peer when the forwarded value is not an IP" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 1}},
          x_headers: [{"x-forwarded-for", "attacker-controlled"}]
        })

      assert socket_bucket(socket) == "10.0.0.1"
    end

    test "reads the dead-render %Plug.Conn{} and its forwarded header" do
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert socket_bucket(socket(conn)) == "198.51.100.7"
    end

    test "falls back to the conn remote_ip" do
      conn = %Plug.Conn{remote_ip: {127, 0, 0, 1}, req_headers: []}

      assert socket_bucket(socket(conn)) == "127.0.0.1"
    end

    test "returns a stable fallback when connect_info is missing" do
      assert socket_bucket(socket(nil)) == "unknown"
      assert socket_bucket(%Phoenix.LiveView.Socket{}) == "unknown"
    end
  end

  describe "from_conn/1" do
    test "uses the forwarded header when present" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert conn_bucket(conn) == "198.51.100.7"
    end

    test "normalizes valid forwarded addresses" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.7, 2001:0db8:0:0:0:0:0:1"}]
      }

      assert conn_bucket(conn) == "2001:db8::1"
    end

    test "ignores a forwarded header from an unconfigured private peer" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 2},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert conn_bucket(conn) == "10.0.0.2"
    end

    test "falls back to the peer when the forwarded value is not an IP" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "not-an-ip"}]
      }

      assert conn_bucket(conn) == "10.0.0.1"
    end

    test "ignores a forged forwarded header when the peer is not a proxy" do
      # A directly connected client must not choose its own bucket.
      conn = %Plug.Conn{
        remote_ip: {203, 0, 113, 7},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert conn_bucket(conn) == "203.0.113.7"
    end

    test "falls back to remote_ip when the header is missing or blank" do
      assert conn_bucket(%Plug.Conn{remote_ip: {192, 0, 2, 5}, req_headers: []}) ==
               "192.0.2.5"

      assert conn_bucket(%Plug.Conn{
               remote_ip: {192, 0, 2, 5},
               req_headers: [{"x-forwarded-for", " "}]
             }) == "192.0.2.5"
    end

    test "formats IPv6 addresses without breaking the bucket key" do
      assert conn_bucket(%Plug.Conn{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}, req_headers: []}) ==
               "::1"
    end
  end
end
