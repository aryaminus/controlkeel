defmodule ControlKeelWeb.SessionFindingLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "renders guided fix details for the finding", %{conn: conn} do
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

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    assert html =~ "Guided fix"
    assert html =~ "Unsafe HTML"
    assert html =~ "safe DOM API"
  end

  test "renders an empty-state message when no fix details exist", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Manual finding",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review"
      })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    assert html =~ "Manual finding"
    assert html =~ "open"
  end

  test "opens the action menu beside the verification badge", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    assert has_element?(view, "#finding-actions-menu-button")

    refute has_element?(view, "#finding-actions-menu")

    render_click(element(view, "#finding-actions-menu-button"))

    assert has_element?(view, "#finding-actions-menu")
    assert has_element?(view, "#finding-actions-menu button", "Approve")
    assert has_element?(view, "#finding-actions-menu button", "Reject")
    assert has_element?(view, "#finding-actions-menu button", "Escalate")
    assert has_element?(view, "#finding-actions-menu button", "Copy fix prompt")
  end

  test "copies the fix prompt to the clipboard", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    render_click(element(view, "#finding-actions-menu-button"))
    render_click(element(view, "button[phx-click=\"copy_fix_prompt\"]"))

    assert_push_event(view, "copy-to-clipboard", %{text: _text})
  end

  test "approves the finding from the detail page", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    render_click(element(view, "#finding-actions-menu-button"))

    updated_html =
      view
      |> element("button[phx-click=\"approve_finding\"]")
      |> render_click()

    assert updated_html =~ "Finding approved."
    assert Mission.get_finding!(finding.id).status == "approved"
  end

  test "rejects the finding with a reason", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Reject me",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    render_click(element(view, "#finding-actions-menu-button"))
    view |> element("button[phx-click=\"reject_finding\"]") |> render_click()

    assert has_element?(view, "#finding-reject-reason")

    view
    |> element("#finding-reject-reason")
    |> render_keyup(%{"value" => "Not applicable to this session."})

    updated_html = view |> element("button", "Confirm") |> render_click()

    assert updated_html =~ "Finding rejected."
    assert Mission.get_finding!(finding.id).status == "rejected"

    assert Mission.get_finding!(finding.id).metadata["rejection_reason"] ==
             "Not applicable to this session."
  end

  test "escalates the finding from the detail page", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Escalate me",
        rule_id: "review.runtime",
        severity: "medium",
        category: "review",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")

    render_click(element(view, "#finding-actions-menu-button"))

    updated_html =
      view
      |> element("button[phx-click=\"escalate_finding\"]")
      |> render_click()

    assert updated_html =~ "Finding escalated."
    assert Mission.get_finding!(finding.id).status == "escalated"
  end

  test "redirects when the finding belongs to another session", %{conn: conn} do
    session = session_fixture()
    other = session_fixture()
    finding = finding_fixture(%{session: other})

    findings_path = ~p"/sessions/#{session.id}/findings"

    assert {:error, {:live_redirect, %{to: ^findings_path}}} =
             live(conn, ~p"/sessions/#{session.id}/findings/#{finding.id}")
  end

  test "redirects when the finding does not exist", %{conn: conn} do
    session = session_fixture()

    findings_path = ~p"/sessions/#{session.id}/findings"

    assert {:error, {:live_redirect, %{to: ^findings_path}}} =
             live(conn, ~p"/sessions/#{session.id}/findings/999999")
  end

  test "redirects when session is not found", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/sessions/999999/findings/1")
  end
end
