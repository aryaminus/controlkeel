defmodule ControlKeelWeb.MissionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

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
end
