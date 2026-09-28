defmodule ControlKeelWeb.ObservabilityTrendsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "trends page renders and supports day window selection", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Trends page finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.trends"
    })

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/trends")

    assert html =~ "Trends"
    assert html =~ "controlkeel obs trends"
    assert has_element?(view, "#observability-trends")

    # Default window is 7 days
    assert has_element?(view, "#trends-days select option[value='7'][selected]")

    # Change to 30-day window via the select form
    view
    |> form("#trends-days", %{days: "30"})
    |> render_change()

    assert_patch(view, "/#{org.slug}/workspaces/#{ws.slug}/trends?days=30")
  end

  test "unknown workspace slug redirects instead of crashing", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/trends")
  end
end
