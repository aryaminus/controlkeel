defmodule ControlKeelWeb.SessionResumePacketLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "session resume packet shows the current task packet with blockers and runs", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    _task = task_fixture(%{session: session, status: "in_progress", title: "Resume me"})
    finding = finding_fixture(%{session: session, title: "Resume blocker"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/resume-packet"))

    assert html =~ "Resume packet"
    assert html =~ "Resume me"
    assert html =~ "Resume blocker"
    assert html =~ finding.rule_id
    assert html =~ "In progress"
    assert html =~ "Unresolved findings"
    assert html =~ "Latest runs"
    assert html =~ "Relevant memory"
    assert html =~ "Checkpoint history"
    assert html =~ org_session_path(org, ws, session, "/tasks")
    assert html =~ org_session_path(org, ws, session, "/findings")
  end

  test "session resume packet records checkpoint history after pause and resume", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "in_progress"})

    assert {:ok, _} = Mission.pause_task(task.id, "test-observer")
    assert {:ok, _} = Mission.resume_task(task.id, "test-observer")

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/resume-packet"))

    assert html =~ "pause"
    assert html =~ "resume"
    assert html =~ "test-observer"
  end

  test "session resume packet shows an empty state when no task is active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/resume-packet"))

    assert html =~ "No active task"
    assert html =~ "No checkpoints recorded yet."
  end

  test "session resume packet renders the session sidebar with Resume active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/resume-packet"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Resume packet"
    refute html =~ "Service accounts"

    resume_href = org_session_path(org, ws, session, "/resume-packet")
    assert html =~ ~s(href="#{resume_href}")
  end

  test "session resume packet shows an in-place error when the session does not exist", %{
    conn: conn
  } do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/resume-packet")

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "h1", "Can't find the page")
    refute_redirected(view)
  end

  test "session resume packet shows an in-place error when the workspace slug disagrees", %{
    conn: conn
  } do
    {org, _ws, session} = org_bound_session_fixture()

    {:ok, view, _html} =
      live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/resume-packet")

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "h1", "Can't find the page")
    refute_redirected(view)
  end

  test "session resume packet shows an in-place error when the org slug disagrees", %{
    conn: conn
  } do
    {_org, ws, session} = org_bound_session_fixture()

    {:ok, view, _html} =
      live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/resume-packet")

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, "h1", "Organization not found")
    refute_redirected(view)
  end
end
