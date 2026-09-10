defmodule ControlKeelWeb.Plugs.BrowserAuthPlugsTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeelWeb.Plugs.{LoadCurrentUser, RequireCloudMode}

  setup %{conn: conn} do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, user, _created} = Accounts.find_or_create_user("user@example.com", "Test User")

    {:ok, membership} =
      %ControlKeel.Accounts.Membership{}
      |> ControlKeel.Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> ControlKeel.Repo.insert()

    conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})
    {:ok, conn: conn, org: org, user: user, membership: membership}
  end

  test "LoadCurrentUser assigns user and active membership", %{
    conn: conn,
    user: user,
    membership: membership
  } do
    conn = LoadCurrentUser.call(conn, [])
    assert conn.assigns.current_user.id == user.id
    assert conn.assigns.current_membership.id == membership.id
  end

  test "RequireCloudMode redirects signed-in visitors away from /auth/login", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/auth/login")
      |> RequireCloudMode.call([])

    assert redirected_to(conn, 302) == "/"
    assert conn.halted
  end

  test "RequireCloudMode allows auth paths in cloud mode", %{conn: conn} do
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    conn =
      conn
      |> Map.put(:request_path, "/auth/google/request")
      |> Plug.Conn.fetch_session()
      |> Phoenix.Controller.fetch_flash()
      |> RequireCloudMode.call([])

    refute conn.halted
  end

  test "RequireCloudMode redirects auth paths in local mode with an info flash", %{conn: conn} do
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :local)

    on_exit(fn ->
      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    conn =
      conn
      |> Map.put(:request_path, "/auth/google/request")
      |> Plug.Conn.fetch_session()
      |> Phoenix.Controller.fetch_flash()
      |> RequireCloudMode.call([])

    assert redirected_to(conn, 302) == "/"
    assert conn.halted

    assert get_session(conn, "phoenix_flash")["info"] ==
             "This feature is not available in local mode."
  end
end
