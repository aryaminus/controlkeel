defmodule ControlKeelWeb.SessionReleaseLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.IntentFixtures
  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures
  import Ecto.Query

  alias ControlKeel.Analytics
  alias ControlKeel.Mission
  alias ControlKeel.Repo

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
    {org, ws, session} = org_bound_session_fixture()
    approved_done_task_with_proof(session)

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/release"))

    assert html =~ "Release readiness"
    assert html =~ "mission-release-readiness"
    assert html =~ "needs review"
    assert html =~ "release-readiness-reasons"
    assert html =~ "Release smoke evidence is missing or not green."
    assert html =~ "Artifact provenance is missing or unverified."
  end

  test "submitting smoke and provenance evidence flips the verdict to ready in place", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()
    %{proof: proof} = approved_done_task_with_proof(session)

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/release"))
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
  end

  test "blocked verdict renders every applicable reason alongside green evidence", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    approved_done_task_with_proof(session)

    finding_fixture(%{
      session: session,
      title: "Blocking release finding",
      severity: "high",
      status: "open"
    })

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/release"))

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

    assert updated_html =~ "1 blocking finding(s) remain unresolved."
    assert updated_html =~ org_session_path(org, ws, session, "/findings")
  end

  test "records telemetry only for explicit checks, not mount or auto-refresh", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    approved_done_task_with_proof(session)

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/release"))
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
    {org, ws, session} = org_bound_session_fixture()
    approved_done_task_with_proof(session)

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/release"))
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
  end

  test "shows a neutral empty state when no proof bundle exists", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session, status: "in_progress"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/release"))

    assert html =~ "No proof bundle is available for release review yet."
    assert html =~ "needs review"
  end

  test "session release renders the session sidebar with Release active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/release"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Release"
    refute html =~ "Service accounts"

    release_href = org_session_path(org, ws, session, "/release")
    assert html =~ ~s(href="#{release_href}")
  end

  test "session release redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/release")
  end

  test "session release redirects when the workspace slug disagrees", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/release")
  end

  test "session release redirects when the org slug disagrees", %{conn: conn} do
    {_org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/release")
  end
end
