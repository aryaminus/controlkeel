defmodule ControlKeelWeb.ObservabilityOverviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "overview page renders workspace observability cockpit", %{conn: conn} do
    {org, ws, session} =
      org_bound_session_fixture(%{budget_cents: 2_000, spent_cents: 450})

    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview grouped finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

    assert html =~ "Observability"
    assert has_element?(view, "#observability-overview-page")
    assert has_element?(view, "#observability-overview-run-list")
    assert html =~ "/#{ws.slug}/problems"
    assert html =~ "/#{ws.slug}/promotions"
    assert html =~ "/#{ws.slug}/costs"
    assert html =~ "/#{ws.slug}/imports"
    assert html =~ "/#{ws.slug}/memory-quality"
    assert html =~ "/#{ws.slug}/trends"
    # Benchmark depth pages consolidated into the workspace benchmark page
    refute html =~ "/observability/benchmarks/drafts"
    refute html =~ "/observability/benchmarks/scenarios"
    refute html =~ "/observability/benchmarks/history"
    refute html =~ "/observability/regressions"
  end

  test "overview page scopes recent runs to the URL workspace", %{conn: conn} do
    {org_one, ws_one, _session_one} = org_bound_session_fixture()
    {_org_two, _ws_two, _session_two} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, "/#{org_one.slug}/workspaces/#{ws_one.slug}/observability")

    assert html =~ "1 recent"
  end
end
