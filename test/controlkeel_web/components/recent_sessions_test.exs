defmodule ControlKeelWeb.RecentSessionsTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.RecentSessions

  test "renders empty state when no runs" do
    html = render_component(&RecentSessions.session_observability_section/1, runs: [])
    assert html =~ "Recent session runs"
    assert html =~ "No sessions available yet."
  end

  test "renders session list with health pills" do
    runs = [
      %{
        id: 1,
        title: "Session A",
        health: "red",
        active_findings: 3,
        blocked_findings: 1,
        budget_spent_cents: 1250,
        budget_limit_cents: 10_000,
        memory_records: 7,
        proof_bundles: 3
      },
      %{
        id: 2,
        title: "Session B",
        health: "green",
        active_findings: 0,
        blocked_findings: 0,
        budget_spent_cents: 0,
        budget_limit_cents: 5000,
        memory_records: 2,
        proof_bundles: 0
      }
    ]

    html = render_component(&RecentSessions.session_observability_section/1, runs: runs)
    assert html =~ "Session A"
    assert html =~ "Session B"
    assert html =~ "/observability/sessions/1"
    assert html =~ "/observability/sessions/2"
    assert html =~ "3 active"
    assert html =~ "1 blocked"
    assert html =~ "3 bundles"
    assert html =~ "No proofs yet"
    assert html =~ "7 records"
    refute html =~ "No sessions available yet."
  end

  test "proof count is nil-safe for legacy runs" do
    runs = [
      %{
        id: 3,
        title: "Legacy session",
        health: "green",
        active_findings: 0,
        blocked_findings: 0,
        budget_spent_cents: 0,
        budget_limit_cents: 5000,
        memory_records: 1
      }
    ]

    html = render_component(&RecentSessions.session_observability_section/1, runs: runs)
    assert html =~ "Legacy session"
    assert html =~ "No proofs yet"
  end
end
