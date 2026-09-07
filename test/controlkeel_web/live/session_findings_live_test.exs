defmodule ControlKeelWeb.SessionFindingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

  test "renders persisted runtime findings in a table with detail links", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _result} =
             CkValidate.call(%{
               "content" =>
                 ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --),
               "path" => "lib/query_builder.js",
               "kind" => "code",
               "session_id" => session.id
             })

    finding_id =
      session.id
      |> Mission.get_session_context()
      |> Map.get(:findings)
      |> List.first()
      |> Map.get(:id)

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}/findings")

    assert html =~ "Sql injection"
    assert html =~ "blocked"
    assert has_element?(view, "#session-findings-table")

    refute has_element?(view, "#finding-menu-#{finding_id}")

    render_click(element(view, "#finding-menu-button-#{finding_id}"))

    assert has_element?(view, "#finding-menu-#{finding_id}")
    assert has_element?(view, "#finding-menu-#{finding_id} a", "View details")
    refute has_element?(view, "#finding-menu-#{finding_id} a", "Open in browser")

    assert has_element?(view, "#finding-menu-#{finding_id} button", "Approve")
    assert has_element?(view, "#finding-menu-#{finding_id} button", "Reject")

    expected_path = ~p"/sessions/#{session.id}/findings/#{finding_id}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             render_click(element(view, "#finding-title-cell-#{finding_id}"))
  end

  test "renders an empty state when no findings exist", %{conn: conn} do
    session = session_fixture()

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/findings")

    assert html =~ "No findings yet."
    assert html =~ "ControlKeel is monitoring every agent action."
  end

  test "kebab menu actions approve and reject in place", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Approve me",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings")

    view |> element("#finding-menu-button-#{finding.id}") |> render_click()

    updated_html =
      view
      |> element("#finding-menu-#{finding.id} button", "Approve")
      |> render_click()

    assert updated_html =~ "Finding approved."
    assert Mission.get_finding!(finding.id).status == "approved"

    blocked =
      finding_fixture(%{
        session: session,
        title: "Reject me",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review",
        status: "blocked"
      })

    send(view.pid, :refresh)

    view |> element("#finding-menu-button-#{blocked.id}") |> render_click()

    updated_html =
      view
      |> element("#finding-menu-#{blocked.id} button", "Reject")
      |> render_click()

    assert updated_html =~ "Finding rejected."
    assert Mission.get_finding!(blocked.id).status == "rejected"
  end

  test "resolved findings hide approve and reject menu actions", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Already approved",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review",
        status: "approved"
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings")

    view |> element("#finding-menu-button-#{finding.id}") |> render_click()

    refute has_element?(view, "#finding-menu-#{finding.id} button", "Approve")
    refute has_element?(view, "#finding-menu-#{finding.id} button", "Reject")
  end

  test "refreshes when new findings appear", %{conn: conn} do
    session = session_fixture()

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}/findings")
    assert html =~ "No findings yet."

    Analytics.record(%{
      event: "project_initialized",
      source: "test",
      session_id: session.id,
      workspace_id: session.workspace_id
    })

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
  end

  test "redirects when session is not found", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, ~p"/sessions/999999/findings")
  end
end
