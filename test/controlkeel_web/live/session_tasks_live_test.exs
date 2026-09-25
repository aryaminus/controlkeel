defmodule ControlKeelWeb.SessionTasksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Repo

  test "session tasks shows dependencies when graph edges exist", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    _t1 =
      task_fixture(%{
        session: session,
        position: 1,
        status: "done",
        metadata: %{"track" => "architecture"},
        title: "Architecture lock"
      })

    _t2 =
      task_fixture(%{
        session: session,
        position: 2,
        status: "in_progress",
        metadata: %{"track" => "feature"},
        title: "Feature work"
      })

    _t3 =
      task_fixture(%{
        session: session,
        position: 3,
        status: "queued",
        metadata: %{"track" => "release"},
        title: "Release verify"
      })

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    assert html =~ "Dependencies"
    assert html =~ "Architecture lock"
    assert html =~ "Feature work"
    assert html =~ "Release verify"
    assert html =~ "mission-task-edges"
  end

  test "session tasks supports proof generation and pause/resume controls", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "in_progress"})

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    render_click(view, "generate_proof", %{"id" => task.id})
    assert render(view) =~ "Proof bundle generated."
    assert Mission.latest_proof_bundle_for_task(task.id)

    render_click(view, "pause_task", %{"id" => task.id})
    assert Mission.get_task!(task.id).status == "paused"

    render_click(view, "resume_task", %{"id" => task.id})
    assert Mission.get_task!(task.id).status == "in_progress"
  end

  test "session tasks distinguishes verified tasks from done but unverified tasks", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()

    _verified =
      task_fixture(%{
        session: session,
        status: "verified",
        title: "Verified task"
      })

    _done =
      task_fixture(%{
        session: session,
        position: 2,
        status: "done",
        title: "Done task"
      })

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    assert html =~ "Verified task"
    assert html =~ "verified"
    assert html =~ "Done task"
    assert html =~ "done, unverified"
  end

  test "session tasks shows an empty state when no tasks exist", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    assert html =~ "No tasks yet."
  end

  test "session tasks redirects when the session disappears on refresh", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    Repo.delete!(session)
    send(view.pid, :refresh)

    assert_redirect(view, "/")
  end

  test "session tasks redirects with generic not-found for a non-numeric id", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/abc/tasks")
  end

  test "session tasks rejects a task id from another session", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    {_other_org, _other_ws, other_session} = org_bound_session_fixture()
    foreign_task = task_fixture(%{session: other_session, status: "in_progress"})

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

    render_click(view, "pause_task", %{"id" => foreign_task.id})

    assert render(view) =~ "Could not pause task."
    assert Mission.get_task!(foreign_task.id).status == "in_progress"
  end

  describe "complete task" do
    test "completes an eligible task and surfaces the new proof", %{conn: conn} do
      {org, ws, session} =
        org_bound_session_fixture(%{risk_tier: "low", title: "Complete success session"})

      task = task_fixture(%{session: session, status: "in_progress", title: "Do the work"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

      updated_html = render_click(view, "complete_task", %{"id" => task.id})

      assert updated_html =~ "Task completed:"
      assert updated_html =~ "Do the work"

      assert ControlKeel.Mission.get_task!(task.id).status in ["done", "verified"]

      proof = ControlKeel.Mission.latest_proof_bundle_for_task(task.id)
      assert proof
      assert updated_html =~ "/proofs/#{proof.id}"
    end

    test "surfaces unresolved findings when completion is blocked", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture(%{risk_tier: "low"})
      task = task_fixture(%{session: session, status: "in_progress"})

      finding_fixture(%{session: session, status: "open", title: "Blocking finding"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

      updated_html = render_click(view, "complete_task", %{"id" => task.id})

      assert updated_html =~ "unresolved finding"
      assert ControlKeel.Mission.get_task!(task.id).status == "blocked"
    end

    test "surfaces the proof-not-ready reason for high-risk sessions", %{conn: conn} do
      {org, ws, session} =
        org_bound_session_fixture(%{risk_tier: "high", title: "Proof gate session"})

      task = task_fixture(%{session: session, status: "in_progress"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

      updated_html = render_click(view, "complete_task", %{"id" => task.id})

      assert updated_html =~ "not deploy-ready"
      assert ControlKeel.Mission.get_task!(task.id).status == "in_progress"
    end

    test "completed tasks do not show a Complete button", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()
      done_task = task_fixture(%{session: session, status: "done", title: "Already done"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/tasks"))

      refute has_element?(view, "#task-menu-#{done_task.id} button", "Complete")
    end
  end
end
