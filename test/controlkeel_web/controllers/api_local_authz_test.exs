defmodule ControlKeelWeb.ApiLocalAuthzTest do
  @moduledoc """
  A1 boundary: with no CONTROLKEEL_API_TOKEN configured (local default),
  the API serves loopback peers only, and project-root-keyed skills/config
  endpoints are pinned to the server's governed root. Authenticated
  (bootstrap token) callers keep arbitrary-root capability.
  """
  use ControlKeelWeb.ConnCase, async: false

  @test_token "local-authz-test-token"

  setup do
    previous = Application.get_env(:controlkeel, :api_token)
    Application.put_env(:controlkeel, :api_token, nil)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :api_token, previous)
      else
        Application.delete_env(:controlkeel, :api_token)
      end
    end)

    :ok
  end

  defp bootstrap_conn(conn) do
    # Configure the token then present it: authenticated bootstrap caller.
    Application.put_env(:controlkeel, :api_token, @test_token)

    on_exit(fn ->
      Application.put_env(:controlkeel, :api_token, nil)
    end)

    put_req_header(conn, "authorization", "Bearer " <> @test_token)
  end

  describe "loopback gate" do
    test "loopback peer passes without a token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions")
      assert json_response(conn, 200)
    end

    test "non-loopback peer is forbidden without a token", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 0, 0, 5}}
      conn = get(conn, ~p"/api/v1/sessions")
      assert %{"error" => "forbidden_nonlocal_peer"} = json_response(conn, 403)
    end

    test "non-loopback peer with a valid bearer token passes", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> @test_token)
        |> Map.put(:remote_ip, {10, 0, 0, 5})

      Application.put_env(:controlkeel, :api_token, @test_token)

      conn = get(conn, ~p"/api/v1/sessions")
      assert json_response(conn, 200)
    after
      Application.put_env(:controlkeel, :api_token, nil)
    end
  end

  describe "project_root containment" do
    test "unauthenticated foreign project_root is forbidden", %{conn: conn} do
      tmp = System.tmp_dir!()

      conn = get(conn, ~p"/api/v1/skills?project_root=#{tmp}")
      assert %{"error" => error} = json_response(conn, 403)
      assert error =~ "project_root not authorized"
    end

    test "unauthenticated absent project_root serves the governed root", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/skills")
      body = json_response(conn, 200)
      assert is_list(body["skills"])
    end

    test "unauthenticated governed root itself is accepted", %{conn: conn} do
      governed = ControlKeel.Project.Root.resolve(File.cwd!())

      conn = get(conn, ~p"/api/v1/skills?project_root=#{governed}")
      assert json_response(conn, 200)
    end

    test "bootstrap-authenticated caller may pass any root", %{conn: conn} do
      tmp = Path.join(System.tmp_dir!(), "ck-authz-anyroot-#{System.unique_integer()}")
      Application.put_env(:controlkeel, :api_token, @test_token)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> @test_token)
        |> post(~p"/api/v1/skills/export", %{target: "open-standard", project_root: tmp})

      assert json_response(conn, 200)
      File.rm_rf!(tmp)
    after
      Application.put_env(:controlkeel, :api_token, nil)
    end

    test "unauthenticated export with foreign root is forbidden", %{conn: conn} do
      tmp = System.tmp_dir!()

      conn =
        post(conn, ~p"/api/v1/skills/export", %{target: "open-standard", project_root: tmp})

      assert %{"error" => error} = json_response(conn, 403)
      assert error =~ "project_root not authorized"
    end

    test "unauthenticated token_audit with foreign root is forbidden", %{conn: conn} do
      tmp = System.tmp_dir!()

      conn = get(conn, ~p"/api/v1/skills/token-audit?project_root=#{tmp}")
      assert %{"error" => error} = json_response(conn, 403)
      assert error =~ "project_root not authorized"
    end

    test "unauthenticated bootstrap_project with foreign root is forbidden", %{conn: conn} do
      tmp = System.tmp_dir!()

      conn = post(conn, ~p"/api/v1/bootstrap", %{project_root: tmp})
      assert %{"error" => error} = json_response(conn, 403)
      assert error =~ "project_root not authorized"
    end
  end
end
