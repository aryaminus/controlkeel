defmodule ControlKeelWeb.MissionControlLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.IntentFixtures
  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

  test "mission control renders review decision prompts on the resume packet page", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()
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

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/resume-packet"))

    assert html =~ "Inversion:"
    assert html =~ "Evidence check:"
  end

  test "mission control renders persisted runtime findings and proxy endpoints", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    assert {:ok, _result} =
             CkValidate.call(%{
               "content" =>
                 ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
               "path" => "lib/query_builder.js",
               "kind" => "code",
               "session_id" => session.id
             })

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    assert html =~ "Build the first governed workflow"

    # Proxy endpoints have moved to the session connect page
    refute html =~ "/proxy/openai/"
    {:ok, _cview, chtml} = live(conn, org_session_path(org, ws, session, "/connect"))
    assert chtml =~ "/proxy/openai/"
    assert chtml =~ "/v1/completions"
    assert chtml =~ "/v1/embeddings"
    assert chtml =~ "/v1/models"

    # Findings feed has moved to session findings page
    refute html =~ "Findings feed"
    {:ok, _fview, fhtml} = live(conn, org_session_path(org, ws, session, "/findings"))
    assert fhtml =~ "Sql injection"
    assert fhtml =~ "blocked"
    assert fhtml =~ "View fix"
  end

  test "mission control shows the derived production boundary summary", %{conn: conn} do
    {org, ws, session} =
      org_bound_session_fixture(%{
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

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    assert html =~ "Production boundary"
    assert html =~ "Local-first deploy"
    assert html =~ "approval before production"
    assert html =~ "$40/month to start"
  end

  test "mission control drops the observability panel and bridges to the run page", %{
    conn: conn
  } do
    {org, ws, session} =
      org_bound_session_fixture(%{
        budget_cents: 2_000,
        daily_budget_cents: 2_000,
        spent_cents: 300
      })

    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Observation finding",
      severity: "high",
      status: "open"
    })

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    refute html =~ "mission-observability-panel"
    refute html =~ "Session run observability"
    assert html =~ "Observability"
    assert html =~ ~s(href="/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability")
  end

  test "mission control links to the session review queue page", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    review_fixture(%{session: session, submitted_by: "opencode"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "1 total"
    assert html =~ "1 pending"
    assert html =~ org_session_path(org, ws, session, "/reviews")
  end

  test "mission control denies mismatched slugs with a generic not-found", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}")
  end

  test "session page shows the attach banner only after a fresh launch (issue #183)", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, session, "?launched=1"))

    assert html =~ "ControlKeel is governing this session"
    assert html =~ "controlkeel attach opencode"

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    refute html =~ "ControlKeel is governing this session"
  end

  test "mission control refreshes when new findings and spend data appear", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture(%{spent_cents: 600, budget_cents: 5_000})
    task_fixture(%{session: session})

    {:ok, view, html} = live(conn, org_session_path(org, ws, session))
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

    assert refreshed_html =~ "9.0 / 50.0"
    assert refreshed_html =~ "Session metrics"
    assert refreshed_html =~ "Funnel stage"

    {:ok, _fview, fhtml} = live(conn, org_session_path(org, ws, session, "/findings"))
    assert fhtml =~ "Runtime review required"
  end

  test "mission control reaches session activity through the session sidebar", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    refute html =~ "Recent transcript"
    assert html =~ org_session_path(org, ws, session, "/activity")
  end
end
