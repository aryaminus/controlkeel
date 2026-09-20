defmodule ControlKeelWeb.MissionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts

  test "missions index shows the full session history", %{conn: conn} do
    workspace = workspace_fixture(%{name: "History Workspace"})

    for n <- 1..7 do
      session_fixture(%{workspace: workspace, title: "Session #{n}"})
    end

    {:ok, _view, html} = live(conn, ~p"/sessions")

    assert html =~ "Session 7"
    assert html =~ "Session 1"
  end

  test "missions index links straight to org-scoped session pages", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, ~p"/sessions")

    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}"
  end

  describe "cloud mode /sessions visibility (issue #183)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    defp cloud_conn(user) do
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
    end

    test "lists only the viewer's accessible sessions, never other users'", %{} do
      user_a = ControlKeel.AccountsFixtures.user_fixture()
      user_b = ControlKeel.AccountsFixtures.user_fixture()

      {:ok, org_a} =
        Accounts.create_org_with_owner(user_a.id, %{name: "Vega Co", slug: "vega-co"})

      {:ok, org_b} =
        Accounts.create_org_with_owner(user_b.id, %{name: "Orion Co", slug: "orion-co"})

      ws_a = workspace_fixture(%{org_id: org_a.id, name: "Vega WS", slug: "vega-ws"})
      ws_b = workspace_fixture(%{org_id: org_b.id, name: "Orion WS", slug: "orion-ws"})

      session_fixture(%{workspace: ws_a, title: "Vega A Session"})
      session_fixture(%{workspace: ws_b, title: "Orion B Session"})

      {:ok, _view, html} = live(cloud_conn(user_a), ~p"/sessions")

      assert html =~ "Vega A Session"
      refute html =~ "Orion B Session"
    end

    test "user with an org but no workspaces sees the empty state, not everything", %{} do
      user = ControlKeel.AccountsFixtures.user_fixture()
      other = ControlKeel.AccountsFixtures.user_fixture()

      {:ok, _org} =
        Accounts.create_org_with_owner(user.id, %{name: "Empty Co", slug: "empty-co"})

      {:ok, org_b} =
        Accounts.create_org_with_owner(other.id, %{name: "Full Co", slug: "full-co"})

      ws_b = workspace_fixture(%{org_id: org_b.id, name: "Full WS", slug: "full-ws"})
      session_fixture(%{workspace: ws_b, title: "Someone Else Session"})

      {:ok, _view, html} = live(cloud_conn(user), ~p"/sessions")

      assert html =~ "No sessions yet."
      refute html =~ "Someone Else Session"
    end
  end
end
