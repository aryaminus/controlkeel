defmodule ControlKeelWeb.SessionActivityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "session activity toggles event details by clicking the event card", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session, title: "Toggle task"})

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    refute html =~ "View event details"
    # The task event body ("Brief approved") stays hidden until the card is expanded.
    refute html =~ "Brief approved"

    [event] =
      session.id
      |> Mission.list_session_events()
      |> Enum.filter(&(&1["event_type"] == "task.created"))

    expanded_html = render_click(element(view, "#transcript-event-#{event["id"]}"))

    assert expanded_html =~ "Brief approved"
    assert expanded_html =~ "transcript-event-details-#{event["id"]}"

    collapsed_html = render_click(element(view, "#transcript-event-#{event["id"]}"))
    refute collapsed_html =~ "Brief approved"
  end

  test "session activity lists events newest first with types and actors", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session, title: "Wire the timeline"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ "Activity"
    assert html =~ "Session created: ControlKeel Session"
    assert html =~ "Task created: Wire the timeline"
    assert html =~ "task.created"
    assert html =~ "system"

    # Newest first: the later task event renders before the session bootstrap event.
    [_before, after_session] = String.split(html, "Session created: ControlKeel Session")
    refute after_session =~ "Task created: Wire the timeline"
  end

  test "session activity links events to session-scoped task and finding pages", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session, title: "Linked task"})
    finding_fixture(%{session: session, title: "Linked finding"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ org_session_path(org, ws, session, "/tasks")
    assert html =~ org_session_path(org, ws, session, "/findings")
    assert html =~ "Finding created: Linked finding"
  end

  test "session activity links to the run observability timeline", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability"
    assert html =~ "#session-observability-timeline"
  end

  test "session activity renders the session sidebar with Transcript active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Activity"
    refute html =~ "Service accounts"

    transcript_href = org_session_path(org, ws, session, "/activity")
    assert html =~ ~s(href="#{transcript_href}")
  end

  test "session activity refreshes as new events are recorded", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/activity"))
    refute html =~ "Task created: Refresh task"

    task_fixture(%{session: session, title: "Refresh task"})
    send(view.pid, :refresh)

    assert render(view) =~ "Task created: Refresh task"
  end

  test "session activity keeps the recorded-event count in view", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ "Showing 2 of 2 recorded events."
    assert html =~ "session · 1"
    assert html =~ "task · 1"
  end

  test "session activity exposes audit export downloads", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/activity"))

    assert html =~ "Audit exports"
    assert html =~ ~s(id="activity-audit-export-json")
    assert html =~ ~s(id="activity-audit-export-csv")
    assert html =~ ~s(id="activity-audit-export-pdf")

    assert html =~
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/json"
  end

  test "session activity redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/activity")
  end

  test "session activity redirects when the workspace slug disagrees", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/activity")
  end

  test "session activity redirects when the org slug disagrees", %{conn: conn} do
    {_org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/activity")
  end
end
