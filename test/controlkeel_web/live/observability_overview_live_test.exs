defmodule ControlKeelWeb.ObservabilityOverviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "overview page renders workspace observability cockpit", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture(%{budget_cents: 2_000, spent_cents: 450})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview grouped finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    base = "/#{org.slug}/workspaces/#{ws.slug}/observability"
    {:ok, view, html} = live(conn, base)

    assert html =~ "Observability"
    assert has_element?(view, "#observability-overview-page")
    assert has_element?(view, "#observability-overview-run-list")
    # Problems page removed: no route link, and the Top findings rows deep
    # link into the respective session's findings for per-finding detail.
    refute html =~ "#{base}/problems"
    assert html =~ "1 group"
    assert html =~ "Overview grouped finding"
    assert html =~ "security.overview"
    assert html =~ "Inspect findings in this session"
    assert html =~ "/sessions/#{session.id}/findings"
    assert html =~ "#{base}/loop"
    assert html =~ "#{base}/promotions"
    assert html =~ "#{base}/compare"
    assert html =~ "#{base}/imports"
    assert html =~ "#{base}/memory-quality"
    assert html =~ "#{base}/trends"
    assert html =~ "#{base}/evals"
    # Benchmark depth pages consolidated into the global benchmark page
    refute html =~ "/observability/benchmarks/drafts"
    refute html =~ "/observability/benchmarks/scenarios"
    refute html =~ "/observability/benchmarks/history"
    refute html =~ "/observability/regressions"
  end

  test "overview page scopes recent runs to the visited workspace", %{conn: conn} do
    {org, ws_one, _session_one} =
      org_bound_session_fixture(%{budget_cents: 2_000, spent_cents: 450})

    ws_two = workspace_fixture(%{org_id: org.id})
    session_fixture(%{workspace: ws_two, budget_cents: 2_000, spent_cents: 450})

    {:ok, _view, html_one} = live(conn, "/#{org.slug}/workspaces/#{ws_one.slug}/observability")
    {:ok, _view, html_two} = live(conn, "/#{org.slug}/workspaces/#{ws_two.slug}/observability")

    assert html_one =~ "1 recent"
    assert html_two =~ "1 recent"
  end
end
