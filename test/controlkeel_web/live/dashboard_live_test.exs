defmodule ControlKeelWeb.DashboardLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "renders the controlkeel dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Dashboard"
    assert html =~ "Benchmark Catch Rate"
    assert html =~ "Proof Coverage"
    assert html =~ "Deploy Ready Rate"
    assert html =~ "Delivery Funnel"
    assert html =~ "Recent Sessions"
    assert html =~ "Provider and Autonomy"
    assert html =~ "Provider and bootstrap status"
    assert html =~ "ACP registry cache"
    assert html =~ "skills-provider-status"
    assert html =~ "skills-registry-status"
    assert html =~ "Signal Preview"
    assert html =~ "Docs"
    assert html =~ "GitHub"
  end

  test "shows at most four recent sessions", %{conn: conn} do
    workspace = workspace_fixture(%{name: "Dashboard sessions"})

    for number <- 1..5 do
      session_fixture(%{workspace: workspace, title: "Dashboard session #{number}"})
    end

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert Enum.count(1..5, &String.contains?(html, "Dashboard session #{&1}")) == 4
  end
end
