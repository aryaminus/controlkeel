defmodule ControlKeelWeb.MissionControlLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.IntentFixtures
  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures
  import Ecto.Query

  alias ControlKeel.Analytics
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  test "mission control renders proxy endpoints", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}")

    assert html =~ "Build the first governed workflow"
    assert html =~ "/proxy/openai/"
    assert html =~ "/v1/completions"
    assert html =~ "/v1/embeddings"
    assert html =~ "/v1/models"
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

  test "mission control refreshes when new spend data and metrics appear", %{conn: conn} do
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

    send(view.pid, :refresh)
    refreshed_html = render(view)

    assert refreshed_html =~ "9.0 / 50.0"
    assert refreshed_html =~ "Session metrics"
    assert refreshed_html =~ "Current funnel stage"
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
end
