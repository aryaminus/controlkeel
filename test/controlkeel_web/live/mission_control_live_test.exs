defmodule ControlKeelWeb.MissionControlLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.IntentFixtures
  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

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

    {:ok, _view, html} = live(conn, ~p"/missions/#{session.id}")

    assert html =~ "Task dependencies"
    assert html =~ "Architecture lock"
    assert html =~ "Task checklist"
    assert html =~ "mission-task-checklist"
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

    {:ok, _view, html} = live(conn, ~p"/missions/#{session.id}")

    assert html =~ "Mission control"
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

    {:ok, _view, html} = live(conn, ~p"/missions/#{session.id}")

    assert html =~ "Production boundary"
    assert html =~ "Local-first deploy"
    assert html =~ "approval before production"
    assert html =~ "$40/month to start"
  end

  test "mission control refreshes when new findings and spend data appear", %{conn: conn} do
    session = session_fixture(%{spent_cents: 600, budget_cents: 5_000})
    task_fixture(%{session: session})

    {:ok, view, html} = live(conn, ~p"/missions/#{session.id}")
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

    {:ok, view, _html} = live(conn, ~p"/missions/#{session.id}")

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

    {:ok, view, _html} = live(conn, ~p"/missions/#{session.id}")

    render_click(element(view, "#current-task-generate-proof-#{task.id}"))
    assert render(view) =~ "Proof bundle generated."
    assert Mission.latest_proof_bundle_for_task(task.id)

    render_click(element(view, "#current-task-pause-#{task.id}"))
    assert Mission.get_task!(task.id).status == "paused"
    assert render(view) =~ "Resume packet"

    render_click(element(view, "#current-task-resume-#{task.id}"))
    assert Mission.get_task!(task.id).status == "in_progress"
  end
end
