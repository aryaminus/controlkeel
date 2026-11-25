defmodule ControlKeelWeb.Plugs.RuntimeSessionTest do
  use ControlKeelWeb.ConnCase, async: false

  setup do
    previous_mode = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :local)

    on_exit(fn ->
      if is_nil(previous_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, previous_mode)
      end
    end)

    :ok
  end

  test "local HTTP requests retain the session across requests", _context do
    ssl_config =
      Plug.SSL.init(
        rewrite_on: [:x_forwarded_proto],
        exclude: [
          hosts: ["localhost", "127.0.0.1"],
          conn: {ControlKeelWeb.Plugs.RuntimeHTTPS, :allow_http?, []}
        ]
      )

    config =
      ControlKeelWeb.Plugs.RuntimeSession.init(
        store: :cookie,
        key: "_controlkeel_test_key",
        signing_salt: "test-signing-salt",
        encryption_salt: "test-encryption-salt",
        same_site: "Lax"
      )

    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:host, "192.168.1.25")
      |> with_secret_key_base()
      |> Plug.SSL.call(ssl_config)
      |> ControlKeelWeb.Plugs.RuntimeSession.call(config)
      |> fetch_session()

    refute conn.halted

    conn = Plug.Conn.put_session(conn, :session_probe, "local-http-session")
    conn = Plug.Conn.send_resp(conn, 200, "ok")

    assert [set_cookie] = get_resp_header(conn, "set-cookie")
    refute String.contains?(String.downcase(set_cookie), "; secure")

    cookie = set_cookie |> String.split(";", parts: 2) |> hd()

    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:host, "192.168.1.25")
      |> with_secret_key_base()
      |> put_req_header("cookie", cookie)
      |> Plug.SSL.call(ssl_config)
      |> ControlKeelWeb.Plugs.RuntimeSession.call(config)
      |> fetch_session()

    assert get_session(conn, :session_probe) == "local-http-session"
  end

  defp with_secret_key_base(conn) do
    %{conn | secret_key_base: String.duplicate("a", 64)}
  end
end
