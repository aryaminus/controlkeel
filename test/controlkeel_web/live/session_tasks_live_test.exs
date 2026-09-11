defmodule ControlKeelWeb.SessionTasksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "renders current task context, task dependencies, and task checklist", %{conn: conn} do
    session = session_fixture(%{title: "Release v2.0"})

    _task1 =
      task_fixture(%{
        session: session,
        title: "Lock the architecture, data model, and deploy plan",
        status: "done",
        validation_gate: "Decision brief approved",
        rollback_boundary:
          "No rollback — architecture decisions; discuss with team before reverting.",
        confidence_score: 0.90,
        position: 1,
        metadata: %{"track" => "architecture"}
      })

    task2 =
      task_fixture(%{
        session: session,
        title: "validation",
        status: "in_progress",
        validation_gate: "Passing checks and proof bundle",
        rollback_boundary: "git revert HEAD~1 # reverts: validation",
        confidence_score: 0.75,
        position: 2,
        metadata: %{"track" => "feature"}
      })

    _task3 =
      task_fixture(%{
        session: session,
        title: "budgets",
        status: "queued",
        validation_gate: "Passing checks and proof bundle",
        rollback_boundary: "git revert HEAD~1 # reverts: budgets",
        confidence_score: 0.75,
        position: 3,
        metadata: %{"track" => "feature"}
      })

    _task4 =
      task_fixture(%{
        session: session,
        title: "release checks",
        status: "queued",
        validation_gate: "Passing checks and proof bundle",
        rollback_boundary: "git revert HEAD~1 # reverts: release checks",
        confidence_score: 0.75,
        position: 4,
        metadata: %{"track" => "feature"}
      })

    _task5 =
      task_fixture(%{
        session: session,
        title: "Run verification, proof bundle, and release checklist",
        status: "queued",
        validation_gate: "Tests, scans, and rollback notes complete",
        rollback_boundary: "No rollback — verification only; no code changed.",
        confidence_score: 0.85,
        position: 5,
        metadata: %{"track" => "release"}
      })

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}/tasks")

    # Current task context
    assert html =~ "Current task context"
    assert html =~ "validation"
    assert html =~ "in progress"
    assert html =~ "Passing checks and proof bundle"
    assert html =~ "Complete"
    assert html =~ "Generate proof"
    assert html =~ "Pause"

    # Task dependencies
    assert html =~ "Task dependencies"
    assert html =~ "Lock the architecture, data model, and deploy plan"
    assert html =~ "blocks"
    assert html =~ "soft_gate"
    assert html =~ "Ready (dependencies satisfied)"
    assert html =~ "validation"
    assert html =~ "budgets"
    assert html =~ "release checks"

    # Task checklist
    assert html =~ "Task checklist"
    assert html =~ "Lock the architecture, data model, and deploy plan"
    assert html =~ "done, unverified"
    assert html =~ "Decision brief approved"
    assert html =~ "No rollback — architecture decisions; discuss with team before reverting."
    assert html =~ "90% confidence"
    assert html =~ "needs verification evidence"

    assert html =~ "git revert HEAD~1 # reverts: validation"
    assert html =~ "git revert HEAD~1 # reverts: budgets"
    assert html =~ "git revert HEAD~1 # reverts: release checks"
    assert html =~ "No rollback — verification only; no code changed."
    assert html =~ "85% confidence"

    # Action events
    assert render_click(view, "pause_task", %{"id" => to_string(task2.id)}) =~ "Resume"
    assert render_click(view, "resume_task", %{"id" => to_string(task2.id)}) =~ "Pause"
  end

  test "redirects when session is not found", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, ~p"/sessions/999999/tasks")
  end

  test "renders review decision prompts on the task checklist", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Risky plan"})

    assert {:ok, _review} =
             ControlKeel.Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Large plan",
               "research_summary" => "Mapped modules.",
               "options_considered" => ["Patch", "Extract"],
               "selected_option" => "Patch",
               "implementation_steps" => ["Patch", "Test"],
               "scope_estimate" => %{
                 "files_touched_estimate" => 7,
                 "diff_size_estimate" => 400,
                 "architectural_scope" => true
               }
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/tasks")

    assert html =~ "Inversion:"
    assert html =~ "Evidence check:"
  end

  test "distinguishes verified tasks from done but unverified tasks", %{conn: conn} do
    session = session_fixture()

    _verified = task_fixture(%{session: session, status: "verified", title: "Verified task"})
    _done = task_fixture(%{session: session, position: 2, status: "done", title: "Done task"})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/tasks")

    assert html =~ "Verified task"
    assert html =~ "verified"
    assert html =~ "Done task"
    assert html =~ "done, unverified"
  end

  describe "complete task" do
    test "completes an eligible task and surfaces the new proof", %{conn: conn} do
      session = session_fixture(%{risk_tier: "low", title: "Complete success session"})
      task = task_fixture(%{session: session, status: "in_progress", title: "Do the work"})

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/tasks")
      assert has_element?(view, "#task-complete-#{task.id}")
      assert has_element?(view, "#current-task-complete-#{task.id}")

      updated_html =
        view
        |> element("#task-complete-#{task.id}")
        |> render_click()

      assert updated_html =~ "Task completed:"
      assert updated_html =~ "Do the work"

      assert ControlKeel.Mission.get_task!(task.id).status in ["done", "verified"]

      proof = ControlKeel.Mission.latest_proof_bundle_for_task(task.id)
      assert proof
      assert updated_html =~ "/proofs/#{proof.id}"
    end

    test "surfaces unresolved findings when completion is blocked", %{conn: conn} do
      session = session_fixture(%{risk_tier: "low"})
      task = task_fixture(%{session: session, status: "in_progress"})

      finding_fixture(%{session: session, status: "open", title: "Blocking finding"})

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/tasks")

      updated_html =
        view
        |> element("#task-complete-#{task.id}")
        |> render_click()

      assert updated_html =~ "unresolved finding"
      assert ControlKeel.Mission.get_task!(task.id).status == "blocked"
    end

    test "surfaces the proof-not-ready reason for high-risk sessions", %{conn: conn} do
      session = session_fixture(%{risk_tier: "high", title: "Proof gate session"})
      task = task_fixture(%{session: session, status: "in_progress"})

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/tasks")

      updated_html =
        view
        |> element("#task-complete-#{task.id}")
        |> render_click()

      assert updated_html =~ "not deploy-ready"
      assert ControlKeel.Mission.get_task!(task.id).status == "in_progress"
    end

    test "completed tasks do not show a Complete button", %{conn: conn} do
      session = session_fixture()
      done_task = task_fixture(%{session: session, status: "done", title: "Already done"})

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/tasks")

      refute has_element?(view, "#task-complete-#{done_task.id}")
    end
  end
end
