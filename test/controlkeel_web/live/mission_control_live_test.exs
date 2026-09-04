defmodule ControlKeelWeb.MissionControlLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.IntentFixtures
  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures
  import Ecto.Query

  alias ControlKeel.Analytics
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  test "mission control shows task dependencies and checklist when graph edges exist", %{
    conn: conn
  } do
    session = session_fixture()

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

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Task dependencies"
    assert html =~ "Architecture lock"
    assert html =~ "Task checklist"
    assert html =~ "mission-task-checklist"
  end

  test "mission control renders review decision prompts", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Risky plan"})

    assert {:ok, _review} =
             Mission.submit_review(%{
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

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Inversion:"
    assert html =~ "Evidence check:"
  end

  test "mission control renders persisted runtime findings and proxy endpoints", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    assert {:ok, _result} =
             CkValidate.call(%{
               "content" =>
                 ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
               "path" => "lib/query_builder.js",
               "kind" => "code",
               "session_id" => session.id
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Build the first governed workflow"
    assert html =~ "Sql injection"
    assert html =~ "blocked"
    assert html =~ "/proxy/openai/"
    assert html =~ "/v1/completions"
    assert html =~ "/v1/embeddings"
    assert html =~ "/v1/models"
    assert html =~ "View fix"
  end

  test "mission control shows the derived production boundary summary", %{conn: conn} do
    session =
      session_fixture(%{
        execution_brief:
          execution_brief_fixture(
            compiler: %{
              "interview_answers" => %{
                "constraints" => "Local-first deploy, approval before production"
              }
            }
          )
          |> ControlKeel.Intent.to_brief_map()
      })

    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Production boundary"
    assert html =~ "Local-first deploy"
    assert html =~ "approval before production"
    assert html =~ "$40/month to start"
  end

  test "mission control renders compact observability panel", %{conn: conn} do
    session = session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Observation finding",
      severity: "high",
      status: "open"
    })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "mission-observability-panel"
    assert html =~ "Session run observability"
    assert html =~ "mission-observability-health"
    assert html =~ "mission-observability-budget"
    assert html =~ "mission-observability-findings"
    assert html =~ "mission-observability-recommendations"
  end

  test "mission control links to the session review queue page", %{conn: conn} do
    session = session_fixture()
    review_fixture(%{session: session, submitted_by: "opencode"})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "1 total review gates"
    assert html =~ "1 pending"
    assert html =~ "/sessions/#{session.id}/reviews"
    assert html =~ "View all"
  end

  test "mission control refreshes when new findings and spend data appear", %{conn: conn} do
    session = session_fixture(%{spent_cents: 600, budget_cents: 5_000})
    task_fixture(%{session: session})

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}")
    assert html =~ "6.0 / 50.0"

    assert {:ok, _} =
             Analytics.record(%{
               event: "project_initialized",
               source: "test",
               session_id: session.id,
               workspace_id: session.workspace_id
             })

    Mission.update_session(session, %{spent_cents: 900})

    Mission.create_finding(%{
      title: "Runtime review required",
      severity: "medium",
      category: "review",
      rule_id: "review.runtime",
      plain_message: "A new human review is required before release.",
      status: "open",
      auto_resolved: false,
      metadata: %{},
      session_id: session.id
    })

    send(view.pid, :refresh)
    refreshed_html = render(view)

    assert refreshed_html =~ "Runtime review required"
    assert refreshed_html =~ "9.0 / 50.0"
    assert refreshed_html =~ "Session metrics"
    assert refreshed_html =~ "Current funnel stage"
  end

  test "mission control renders and copies a guided fix for supported findings", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Unsafe HTML",
        rule_id: "security.xss_unsafe_html",
        severity: "high",
        category: "security",
        metadata: %{"path" => "assets/js/app.js", "matched_text_redacted" => "inner...HTML"}
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")

    detail_html =
      render_click(
        element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{finding.id}\"]")
      )

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "safe DOM API"

    render_click(
      element(view, "button[phx-click=\"copy_fix_prompt\"][phx-value-id=\"#{finding.id}\"]")
    )

    assert_push_event(view, "copy-to-clipboard", %{text: _text})
  end

  test "mission control supports proof generation and pause/resume controls", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "in_progress"})

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Workspace context"
    assert html =~ "Recent transcript"

    render_click(element(view, "#current-task-generate-proof-#{task.id}"))
    assert render(view) =~ "Proof bundle generated."
    assert Mission.latest_proof_bundle_for_task(task.id)

    render_click(element(view, "#current-task-pause-#{task.id}"))
    assert Mission.get_task!(task.id).status == "paused"
    assert render(view) =~ "Resume packet"

    render_click(element(view, "#current-task-resume-#{task.id}"))
    assert Mission.get_task!(task.id).status == "in_progress"
  end

  test "mission control distinguishes verified tasks from done but unverified tasks", %{
    conn: conn
  } do
    session = session_fixture()

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

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Verified task"
    assert html =~ "verified"
    assert html =~ "Done task"
    assert html =~ "done, unverified"
  end

  test "ship readiness section surfaces session-specific posture and a verdict", %{conn: conn} do
    session = session_fixture(%{title: "Ship verdict session"})
    task = task_fixture(%{session: session, status: "done"})

    finding_fixture(%{session: session, status: "blocked", title: "Blocked ship finding"})
    {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Ship readiness"
    # Blocked finding forces a Blocked verdict.
    assert html =~ "Blocked"
    # Session-specific posture metrics migrated from /ship.
    assert html =~ "Proof-backed tasks"
    assert html =~ "Deploy-ready rate"
    assert html =~ "Autonomy posture"
    assert html =~ "Outcome alignment"
    assert html =~ "Ship verdict session"
  end

  describe "release readiness gate" do
    defp approved_done_task_with_proof(session) do
      task = task_fixture(%{session: session, status: "done", title: "Release candidate work"})

      assert {:ok, plan_review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Reviewed the release-readiness and proof flow.",
                 "codebase_findings" => ["Governance reads the latest proof bundle."],
                 "alignment_context" => [
                   "Release managers require smoke evidence and provenance before calling work ready."
                 ],
                 "options_considered" => ["Reuse proof bundles", "Add release-only state"],
                 "selected_option" => "Reuse proof bundles",
                 "rejected_options" => ["Add release-only state"],
                 "implementation_steps" => ["Generate proof", "Require smoke and provenance"],
                 "validation_plan" => ["mix test", "mix precommit"],
                 "submission_body" => "Implementation-ready release readiness plan"
               })

      assert {:ok, _approved} =
               Mission.respond_review(plan_review, %{
                 "decision" => "approved",
                 "feedback_notes" => "Approved plan"
               })

      proof = proof_bundle_fixture(%{task: task})
      assert proof.deploy_ready
      %{task: task, proof: proof}
    end

    defp release_readiness_event_count(session_id) do
      Repo.aggregate(
        from(e in Analytics.Event,
          where: e.session_id == ^session_id and e.event == "release_readiness_checked"
        ),
        :count
      )
    end

    test "renders the gate with every unmet condition before any evidence is submitted", %{
      conn: conn
    } do
      session = session_fixture()
      approved_done_task_with_proof(session)

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "mission-release-readiness"
      assert html =~ "release-readiness-status"
      assert html =~ "needs review"
      assert html =~ "release-readiness-reasons"
      assert html =~ "Release smoke evidence is missing or not green."
      assert html =~ "Artifact provenance is missing or unverified."
    end

    test "submitting smoke and provenance evidence flips the verdict to ready in place", %{
      conn: conn
    } do
      session = session_fixture()
      %{proof: proof} = approved_done_task_with_proof(session)

      {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}")
      assert html =~ "needs review"

      updated_html =
        view
        |> element("#release-readiness-form")
        |> render_submit(%{
          "release" => %{
            "smoke_status" => "success",
            "smoke_run" => "https://ci.example.com/run/1",
            "artifact_source" => "github-actions",
            "sha" => "abc123def",
            "provenance_verified" => "true"
          }
        })

      assert updated_html =~ "Release readiness checked."
      assert updated_html =~ "Release is backed by proof, smoke, and provenance evidence."
      assert updated_html =~ ~s(/proofs/#{proof.id})

      status_html = view |> element("#release-readiness-status") |> render()
      assert status_html =~ "ready"
    end

    test "blocked verdict renders every applicable reason alongside green evidence", %{conn: conn} do
      session = session_fixture()
      approved_done_task_with_proof(session)

      finding_fixture(%{
        session: session,
        title: "Blocking release finding",
        severity: "high",
        status: "open"
      })

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")

      updated_html =
        view
        |> element("#release-readiness-form")
        |> render_submit(%{
          "release" => %{
            "smoke_status" => "success",
            "smoke_run" => "https://ci.example.com/run/2",
            "artifact_source" => "github-actions",
            "provenance_verified" => "true"
          }
        })

      status_html = view |> element("#release-readiness-status") |> render()
      assert status_html =~ "blocked"

      assert updated_html =~ "1 blocking finding(s) remain unresolved."
      assert updated_html =~ "findings?session_id=#{session.id}&amp;status=open"
    end

    test "records telemetry only for explicit checks, not mount or auto-refresh", %{conn: conn} do
      session = session_fixture()
      approved_done_task_with_proof(session)

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")
      assert release_readiness_event_count(session.id) == 0

      send(view.pid, :refresh)
      _ = render(view)
      assert release_readiness_event_count(session.id) == 0

      view
      |> element("#release-readiness-form")
      |> render_submit(%{
        "release" => %{"smoke_status" => "success", "provenance_verified" => "true"}
      })

      assert release_readiness_event_count(session.id) == 1
    end

    test "auto-refresh keeps the cached verdict and explicit check re-evaluates it", %{
      conn: conn
    } do
      session = session_fixture()
      approved_done_task_with_proof(session)

      {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}")
      assert html =~ "needs review"

      finding_fixture(%{
        session: session,
        title: "Late-breaking blocking finding",
        severity: "high",
        status: "open"
      })

      send(view.pid, :refresh)
      refreshed_html = render(view)
      refute refreshed_html =~ "1 blocking finding(s) remain unresolved."

      updated_html =
        view
        |> element("#release-readiness-form")
        |> render_submit(%{
          "release" => %{
            "smoke_status" => "success",
            "smoke_run" => "https://ci.example.com/run/3",
            "artifact_source" => "github-actions",
            "provenance_verified" => "true"
          }
        })

      assert updated_html =~ "1 blocking finding(s) remain unresolved."

      status_html = view |> element("#release-readiness-status") |> render()
      assert status_html =~ "blocked"
    end

    test "shows a neutral empty state when no proof bundle exists", %{conn: conn} do
      session = session_fixture()
      task_fixture(%{session: session, status: "in_progress"})

      {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

      assert html =~ "No proof bundle is available for release review yet."
      assert html =~ "needs review"
    end
  end

  describe "complete task" do
    test "completes an eligible task and surfaces the new proof", %{conn: conn} do
      session = session_fixture(%{risk_tier: "low", title: "Complete success session"})
      task = task_fixture(%{session: session, status: "in_progress", title: "Do the work"})

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")
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

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")

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

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")

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

      {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}")

      refute has_element?(view, "#task-complete-#{done_task.id}")
    end
  end
end
