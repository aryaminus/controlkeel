defmodule ControlKeelWeb.DashboardLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the controlkeel dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Dashboard"
    assert html =~ "Benchmark Catch Rate"
    assert html =~ "Proof Coverage"
    assert html =~ "Deploy Ready Rate"
    assert html =~ "Delivery Funnel"
    refute html =~ "Recent Sessions"
    assert html =~ "Provider and Autonomy"
    assert html =~ "Provider and bootstrap status"
    assert html =~ "ACP registry cache"
    assert html =~ "skills-provider-status"
    assert html =~ "skills-registry-status"
    assert html =~ "Signal Preview"
    assert html =~ "Docs"
    assert html =~ "GitHub"
    refute has_element?(view, ~s(a[href="/sessions"]))
    refute has_element?(view, "a", "View all")
  end
end
