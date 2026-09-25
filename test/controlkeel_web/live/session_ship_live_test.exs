defmodule ControlKeelWeb.SessionShipLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "ship readiness section surfaces session-specific posture and a verdict", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture(%{title: "Ship verdict session"})
    task = task_fixture(%{session: session, status: "done"})

    finding_fixture(%{session: session, status: "blocked", title: "Blocked ship finding"})
    {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/ship"))

    assert html =~ "Ship readiness"
    # Blocked finding forces a Blocked verdict.
    assert html =~ "Blocked"
    assert html =~ "Proof-backed tasks"
    assert html =~ "Deploy-ready rate"
    assert html =~ "Autonomy posture"
    assert html =~ "Outcome alignment"
    assert html =~ "Ship verdict session"
  end

  test "ship readiness refreshes the verdict as the session changes", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session, status: "in_progress", title: "Ship refresh task"})

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/ship"))
    assert html =~ "Ship readiness"

    finding_fixture(%{session: session, status: "blocked", title: "Late blocker"})
    send(view.pid, :refresh)

    assert render(view) =~ "Blocked"
  end

  test "session ship renders the session sidebar with Ship active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/ship"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Ship"
    refute html =~ "Service accounts"

    ship_href = org_session_path(org, ws, session, "/ship")
    assert html =~ ~s(href="#{ship_href}")
  end

  test "session ship redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/ship")
  end

  test "session ship redirects when the workspace slug disagrees", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/ship")
  end

  test "session ship redirects when the org slug disagrees", %{conn: conn} do
    {_org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/ship")
  end
end
