defmodule ControlKeelWeb.SessionFindingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "session findings renders and copies a guided fix for supported findings", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Unsafe HTML",
        rule_id: "security.xss_unsafe_html",
        severity: "high",
        category: "security",
        metadata: %{"path" => "assets/js/app.js", "matched_text_redacted" => "inner...HTML"}
      })

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

    detail_html = render_click(view, "view_fix", %{"id" => finding.id})

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "safe DOM API"

    render_click(view, "copy_fix_prompt", %{"id" => finding.id})

    assert_push_event(view, "copy-to-clipboard", %{text: _text})
  end

  test "session findings shows an empty state when no findings exist", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/findings"))

    assert html =~ "No findings yet."
  end

  test "session findings approves and rejects findings", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    approve_target = finding_fixture(%{session: session, status: "open", title: "Approve me"})
    reject_target = finding_fixture(%{session: session, status: "open", title: "Reject me"})

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

    approved_html = render_click(view, "approve_finding", %{"id" => approve_target.id})
    assert approved_html =~ "Finding approved."
    assert Mission.get_finding!(approve_target.id).status == "approved"

    rejected_html =
      render_click(view, "reject_finding", %{
        "id" => reject_target.id,
        "reason" => "false positive"
      })

    assert rejected_html =~ "Finding rejected."
    assert Mission.get_finding!(reject_target.id).status == "rejected"
  end

  test "session findings rejects a finding id from another session", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    {_other_org, _other_ws, other_session} = org_bound_session_fixture()
    foreign_finding = finding_fixture(%{session: other_session, status: "open"})

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

    rejected_html = render_click(view, "approve_finding", %{"id" => foreign_finding.id})

    assert rejected_html =~ "Could not approve finding."
    assert Mission.get_finding!(foreign_finding.id).status == "open"
  end
end
