defmodule ControlKeelWeb.ObservabilityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission
  alias ControlKeel.Platform

  test "dedicated observability page renders session run details", %{conn: conn} do
    session = session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})
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

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert html =~ "Session run observability"
    assert has_element?(view, "#observability-run-page")
    assert has_element?(view, "#observability-health-card")
    assert has_element?(view, "#observability-timeline")
    assert has_element?(view, "#observability-findings")
    assert has_element?(view, "#observability-gates")
    assert has_element?(view, "#observability-costs")
    assert has_element?(view, "#observability-tools")
    assert has_element?(view, "#observability-recommendations")
    assert has_element?(view, "#observability-export-json")
    assert has_element?(view, "#observability-open-timeline")
    assert has_element?(view, "#observability-open-memory")
    assert has_element?(view, "#observability-telemetry-export")
    assert html =~ "/observability/sessions/#{session.id}/export.json"
    assert html =~ "/observability/sessions/#{session.id}/timeline"
    assert html =~ "/observability/sessions/#{session.id}/memory"
    assert html =~ "Observable finding"
    assert html =~ "Observation review"
  end

  test "observability page links the proofs card pre-filtered to the session", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert html =~ "/proofs?session_id=#{session.id}"
  end

  test "dedicated observability page redirects missing sessions", %{conn: conn} do
    assert {:error,
            {:live_redirect, %{to: "/", flash: %{"error" => "Session observability not found."}}}} =
             live(conn, ~p"/observability/sessions/999999")
  end

  test "observability export route returns local telemetry envelope", %{conn: conn} do
    session = session_fixture()

    conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

    assert %{
             "schema_version" => "controlkeel.observability.v1",
             "session_run" => %{"session" => %{"id" => id}},
             "redaction" => %{"policy" => "summary_only"},
             "integrity" => %{"import_mutation_allowed" => false}
           } = json_response(conn, 200)

    assert id == session.id
  end

  test "observability export route returns not found for missing sessions", %{conn: conn} do
    conn = get(conn, ~p"/observability/sessions/999999/export.json")

    assert %{"error" => "session not found"} = json_response(conn, 404)
  end

  test "mission control links to dedicated observability page", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "mission-observability-open"
    assert html =~ "Open run observability"
    assert html =~ "/observability/sessions/#{session.id}"
  end

  test "observability page renders audit log export controls and checksums", %{conn: conn} do
    session = session_fixture()
    _finding = finding_fixture(%{session: session})

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert has_element?(view, "#observability-audit-log-export")
    assert has_element?(view, "#observability-audit-export-json")
    assert has_element?(view, "#observability-audit-export-csv")
    assert has_element?(view, "#observability-audit-export-pdf")
    assert html =~ "/observability/sessions/#{session.id}/audit-log/json"
    assert html =~ "No audit exports recorded yet"

    assert {:ok, %{export: export}} = Platform.export_audit_log(session.id, "json")

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert html =~ export.checksum
    assert html =~ export.format
    assert html =~ Calendar.strftime(export.generated_at, "%Y-%m-%d %H:%M:%S UTC")
    refute html =~ "unknown time"
  end

  test "mission control header shows audit log export controls and latest checksum", %{
    conn: conn
  } do
    session = session_fixture()

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert has_element?(view, "#mission-audit-export-json")
    assert has_element?(view, "#mission-audit-export-csv")
    assert has_element?(view, "#mission-audit-export-pdf")
    assert html =~ "/observability/sessions/#{session.id}/audit-log/csv"
    refute html =~ "Last export"

    assert {:ok, %{export: export}} = Platform.export_audit_log(session.id, "csv")

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Last export (csv)"
    assert html =~ export.checksum
  end
end
