defmodule ControlKeelWeb.ObservabilityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission
  alias ControlKeel.Platform

  defp observability_path(org, ws, session), do: "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability"

  test "stacked observability page renders session run details", %{conn: conn} do
    {org, ws, session} =
      org_bound_session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})

    task = task_fixture(%{session: session, status: "in_progress", title: "Observe task"})

    finding_fixture(%{
      session: session,
      title: "Observable finding",
      severity: "high",
      status: "open",
      rule_id: "observability.test"
    })

    assert {:ok, _review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "review_type" => "plan",
               "title" => "Observation review",
               "submission_body" => "Review this run"
             })

    {:ok, view, html} = live(conn, observability_path(org, ws, session))

    assert html =~ "Session observability"
    assert has_element?(view, "#observability-run-page")
    assert has_element?(view, "#observability-health-card")
    assert has_element?(view, "#session-observability-timeline")
    assert has_element?(view, "#session-observability-memory")
    assert has_element?(view, "#observability-findings")
    assert has_element?(view, "#observability-gates")
    assert has_element?(view, "#observability-costs")
    assert has_element?(view, "#observability-tools")
    assert has_element?(view, "#observability-recommendations")
    assert has_element?(view, "#observability-telemetry-export")
    assert has_element?(view, "#observability-recent-findings")
    refute has_element?(view, "#observability-timeline")
    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/export.json"
    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/json"
    assert html =~ ~s(href="#session-observability-timeline")
    assert html =~ ~s(href="#session-observability-memory")
    assert html =~ "Observable finding"
  end

  test "observability page links the proofs card pre-filtered to the session", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, observability_path(org, ws, session))

    assert html =~ "/proofs?session_id=#{session.id}"
  end

  test "stacked observability page redirects missing sessions", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    # use a non-existent id
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/observability")
  end

  test "observability export route returns local telemetry envelope via new path", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/export.json")

    assert %{
             "schema_version" => "controlkeel.observability.v1",
             "session_run" => %{"session" => %{"id" => id}},
             "redaction" => %{"policy" => "summary_only"},
             "integrity" => %{"import_mutation_allowed" => false}
           } = json_response(conn, 200)

    assert id == session.id
  end

  test "observability export route still works via legacy path", %{conn: conn} do
    session = session_fixture()

    conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

    assert %{"session_run" => %{"session" => %{"id" => id}}} = json_response(conn, 200)
    assert id == session.id
  end

  test "observability export route returns not found for missing sessions", %{conn: conn} do
    {org, ws, _} = org_bound_session_fixture()
    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/observability/export.json")

    assert %{"error" => "session not found"} = json_response(conn, 404)
  end

  test "mission control session nav bridges to the stacked observability page", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}")

    assert html =~ "sidebar-org-nav"
    assert html =~ "Observability"
    assert html =~ ~s(href="/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability")
  end

  test "observability page renders audit log export controls and checksums", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    _finding = finding_fixture(%{session: session})

    {:ok, view, html} = live(conn, observability_path(org, ws, session))

    assert has_element?(view, "#observability-audit-log-export")
    assert has_element?(view, "#observability-audit-export-json")
    assert has_element?(view, "#observability-audit-export-csv")
    assert has_element?(view, "#observability-audit-export-pdf")
    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/json"
    assert html =~ "No audit exports recorded yet"

    assert {:ok, %{export: export}} = Platform.export_audit_log(session.id, "json")

    {:ok, _view, html} = live(conn, observability_path(org, ws, session))

    assert html =~ export.checksum
    assert html =~ export.format
    assert html =~ Calendar.strftime(export.generated_at, "%Y-%m-%d %H:%M:%S UTC")
    refute html =~ "unknown time"
  end

  test "session activity page shows audit log export controls and latest checksum", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/activity")

    assert has_element?(view, "#activity-audit-export-json")
    assert has_element?(view, "#activity-audit-export-csv")
    assert has_element?(view, "#activity-audit-export-pdf")
    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/csv"
    refute html =~ "Last export"

    assert {:ok, %{export: export}} = Platform.export_audit_log(session.id, "csv")

    {:ok, _view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/activity")

    assert html =~ "Last export (csv)"
    assert html =~ export.checksum
  end

  test "legacy observability page redirects to org-scoped observability", %{conn: conn} do
    session = session_fixture()
    # session has default org/ws
    conn = get(conn, ~p"/observability/sessions/#{session.id}")

    assert redirected_to(conn, 302) =~ "/observability"
    assert redirected_to(conn, 302) =~ "/sessions/#{session.id}/observability"
  end

  test "legacy timeline path redirects with anchor", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    conn = get(conn, ~p"/observability/sessions/#{session.id}/timeline")

    assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability#session-observability-timeline"
  end

  test "legacy memory path redirects with anchor", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    conn = get(conn, ~p"/observability/sessions/#{session.id}/memory")

    assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability#session-observability-memory"
  end
end
