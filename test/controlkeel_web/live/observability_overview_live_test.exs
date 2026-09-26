defmodule ControlKeelWeb.ObservabilityOverviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "overview page renders workspace observability cockpit", %{conn: conn} do
    session = session_fixture(%{budget_cents: 2_000, spent_cents: 450})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview grouped finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    {:ok, view, html} = live(conn, ~p"/observability")

    assert html =~ "Observability"
    assert has_element?(view, "#observability-overview-page")
    assert has_element?(view, "#observability-overview-run-list")
    assert html =~ "/observability/problems"
    assert html =~ "/observability/loop"
    assert html =~ "/observability/promotions"
    assert html =~ "/observability/compare"
    assert html =~ "/observability/imports"
    assert html =~ "/observability/memory-quality"
    assert html =~ "/observability/trends"
    assert html =~ "/observability/evals"
    # Benchmark depth pages consolidated into the workspace benchmark page
    refute html =~ "/observability/benchmarks/drafts"
    refute html =~ "/observability/benchmarks/scenarios"
    refute html =~ "/observability/benchmarks/history"
    refute html =~ "/observability/regressions"
  end

  test "overview page scopes recent runs to the latest workspace", %{conn: conn} do
    workspace_one = workspace_fixture()
    workspace_two = workspace_fixture()

    session_fixture(%{workspace: workspace_one, budget_cents: 2_000, spent_cents: 450})
    session_fixture(%{workspace: workspace_two, budget_cents: 2_000, spent_cents: 450})

    {:ok, _view, html} = live(conn, ~p"/observability")

    assert html =~ "1 recent"
  end
end
