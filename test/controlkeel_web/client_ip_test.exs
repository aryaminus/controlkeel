defmodule ControlKeelWeb.ClientIpTest do
  use ExUnit.Case, async: true

  alias ControlKeelWeb.ClientIp

  defp socket(connect_info) do
    %Phoenix.LiveView.Socket{private: %{connect_info: connect_info}}
  end

  describe "from_socket/1" do
    test "uses peer_data address from the WebSocket connect_info" do
      socket = socket(%{peer_data: %{address: {203, 0, 113, 7}}, x_headers: []})

      assert ClientIp.from_socket(socket) == "203.0.113.7"
    end

    test "distinct peer addresses yield distinct bucket keys" do
      a = socket(%{peer_data: %{address: {203, 0, 113, 7}}, x_headers: []})
      b = socket(%{peer_data: %{address: {203, 0, 113, 8}}, x_headers: []})

      refute ClientIp.from_socket(a) == ClientIp.from_socket(b)
    end

    test "prefers the forwarded header over the proxy peer address" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 1}},
          x_headers: [{"x-forwarded-for", "198.51.100.9"}]
        })

      assert ClientIp.from_socket(socket) == "198.51.100.9"
    end

    test "uses the rightmost forwarded hop, not the client-supplied leftmost" do
      socket =
        socket(%{
          peer_data: %{address: {10, 0, 0, 1}},
          x_headers: [{"x-forwarded-for", "203.0.113.50, 198.51.100.9"}]
        })

      assert ClientIp.from_socket(socket) == "198.51.100.9"
    end

    test "ignores headers the socket connect_info cannot forward" do
      # Phoenix's :x_headers only carries "x-"-prefixed headers, so a
      # fly-client-ip-only socket must still bucket by the peer address.
      socket =
        socket(%{peer_data: %{address: {10, 0, 0, 1}}, x_headers: [{"fly-client-ip", "a"}]})

      assert ClientIp.from_socket(socket) == "10.0.0.1"
    end

    test "reads the dead-render %Plug.Conn{} and its forwarded header" do
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert ClientIp.from_socket(socket(conn)) == "198.51.100.7"
    end

    test "falls back to the conn remote_ip" do
      conn = %Plug.Conn{remote_ip: {127, 0, 0, 1}, req_headers: []}

      assert ClientIp.from_socket(socket(conn)) == "127.0.0.1"
    end

    test "returns a stable fallback when connect_info is missing" do
      assert ClientIp.from_socket(socket(nil)) == "unknown"
      assert ClientIp.from_socket(%Phoenix.LiveView.Socket{}) == "unknown"
    end
  end

  describe "from_conn/1" do
    test "uses the forwarded header when present" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert ClientIp.from_conn(conn) == "198.51.100.7"
    end

    test "ignores a forged forwarded header when the peer is not a proxy" do
      # A directly connected client must not choose its own bucket.
      conn = %Plug.Conn{
        remote_ip: {203, 0, 113, 7},
        req_headers: [{"x-forwarded-for", "198.51.100.7"}]
      }

      assert ClientIp.from_conn(conn) == "203.0.113.7"
    end

    test "falls back to remote_ip when the header is missing or blank" do
      assert ClientIp.from_conn(%Plug.Conn{remote_ip: {192, 0, 2, 5}, req_headers: []}) ==
               "192.0.2.5"

      assert ClientIp.from_conn(%Plug.Conn{
               remote_ip: {192, 0, 2, 5},
               req_headers: [{"x-forwarded-for", " "}]
             }) == "192.0.2.5"
    end

    test "formats IPv6 addresses without breaking the bucket key" do
      assert ClientIp.from_conn(%Plug.Conn{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}, req_headers: []}) ==
               "::1"
    end
  end
end
