defmodule ControlKeelWeb.Plugs.ApiAuthTest do
  use ControlKeelWeb.ConnCase, async: false

  import Plug.Test
  import Plug.Conn

  alias ControlKeelWeb.Plugs.ApiAuth

  @token "api-auth-constant-time-token"

  setup do
    previous_mode = System.get_env("CONTROLKEEL_RUNTIME_MODE")
    previous_token = Application.get_env(:controlkeel, :api_token)
    System.put_env("CONTROLKEEL_RUNTIME_MODE", "local")
    Application.put_env(:controlkeel, :api_token, @token)

    on_exit(fn ->
      if previous_mode,
        do: System.put_env("CONTROLKEEL_RUNTIME_MODE", previous_mode),
        else: System.delete_env("CONTROLKEEL_RUNTIME_MODE")

      if previous_token,
        do: Application.put_env(:controlkeel, :api_token, previous_token),
        else: Application.delete_env(:controlkeel, :api_token)
    end)

    :ok
  end

  defp conn_with_bearer(value) do
    :get
    |> conn("/api/v1/sessions")
    |> put_req_header("authorization", "Bearer " <> value)
    |> assign(:remote_ip, {127, 0, 0, 1})
  end

  describe "bootstrap token authentication" do
    test "accepts the exact configured token as bootstrap" do
      conn = conn_with_bearer(@token) |> ApiAuth.call([])

      refute conn.halted
      assert conn.assigns.api_auth == %{type: :bootstrap}
    end

    test "rejects a near-miss token that shares a long prefix" do
      # Exercises the fixed-length fast path: a differing byte at the end must
      # still be rejected, and the comparison must not leak via behavior.
      near_miss = String.slice(@token, 0, byte_size(@token) - 1) <> "X"
      conn = conn_with_bearer(near_miss) |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects a same-length token differing only in the first byte" do
      mutated = "X" <> String.slice(@token, 1, byte_size(@token) - 1)
      conn = conn_with_bearer(mutated) |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects a token of different length" do
      conn = conn_with_bearer(@token <> "extra") |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "missing credentials" do
    test "returns 401 when no bearer token is supplied and one is configured" do
      conn = :get |> conn("/api/v1/sessions") |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 for an empty bearer value" do
      conn =
        :get
        |> conn("/api/v1/sessions")
        |> put_req_header("authorization", "Bearer ")
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  for mode <- ["cloud", "self_hosted"] do
    test "#{mode} rejects missing credentials even from loopback" do
      System.put_env("CONTROLKEEL_RUNTIME_MODE", unquote(mode))
      Application.delete_env(:controlkeel, :api_token)

      conn = :get |> conn("/api/v1/sessions") |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "#{mode} rejects the configured bootstrap token" do
      System.put_env("CONTROLKEEL_RUNTIME_MODE", unquote(mode))

      conn = conn_with_bearer(@token) |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "#{mode} rejects missing credentials when a bootstrap token is configured" do
      System.put_env("CONTROLKEEL_RUNTIME_MODE", unquote(mode))

      conn = :get |> conn("/api/v1/sessions") |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  test "local mode permits an unauthenticated loopback caller when no token is configured" do
    Application.delete_env(:controlkeel, :api_token)

    conn = :get |> conn("/api/v1/sessions") |> ApiAuth.call([])

    refute conn.halted
    assert conn.assigns.api_auth == %{type: :local}
  end
end
