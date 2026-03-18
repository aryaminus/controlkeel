defmodule ControlKeelWeb.MissionControlLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

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
    assert html =~ "View fix"
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
end
