defmodule ControlKeelWeb.SessionFindingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo

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

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/findings"))

    # rule_id renders under the title so overview problem groups
    # (keyed by rule_id) can be correlated with session findings.
    assert html =~ "Unsafe HTML"
    assert html =~ "security.xss_unsafe_html"
    # Category glyph renders tone-matched (high severity → destructive).
    assert html =~ "hero-shield-exclamation"

    # Accordion: details and actions reveal on toggle, fix computed lazily.
    detail_html = render_click(view, "toggle_finding", %{"id" => finding.id})

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "safe DOM API"
    assert detail_html =~ "Approve"
    assert detail_html =~ "Reject"

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

    # Acting on a finding must not relocate its row: newest-first order
    # ("Reject me" is newer) holds before and after disposition.
    {reject_pos, _} = :binary.match(approved_html, "Reject me")
    {approve_pos, _} = :binary.match(approved_html, "Approve me")
    assert reject_pos < approve_pos

    rejected_html =
      view
      |> render_click("reject_finding", %{"id" => reject_target.id})
      |> then(fn dialog_html ->
        # Reject opens a dialog with the finding context and a reason input.
        assert dialog_html =~ "Reject finding"
        assert dialog_html =~ "Reject me"
        assert dialog_html =~ "reject-reason-form"

        render_click(view, "set_reject_reason", %{"reject_reason" => "false positive"})
      end)
      |> then(fn _ -> render_click(view, "confirm_reject_finding") end)

    assert rejected_html =~ "Finding rejected."
    assert Mission.get_finding!(reject_target.id).status == "rejected"

    # The modal reason persists on the finding and renders in its detail.
    assert Mission.get_finding!(reject_target.id).metadata["rejection_reason"] == "false positive"

    expanded_html = render_click(view, "toggle_finding", %{"id" => reject_target.id})
    assert expanded_html =~ "Rejection reason"
    assert expanded_html =~ "false positive"
  end

  test "session findings meta row separates only present values", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    # Fixture default metadata has no path: rule · category · time.
    finding_fixture(%{session: session, status: "open", title: "No path finding"})

    finding_fixture(%{
      session: session,
      status: "open",
      title: "Pathed finding",
      metadata: %{"path" => "lib/foo.ex"}
    })

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/findings"))

    # 2 separators + 3 separators, and no text-dash separators remain.
    assert length(:binary.matches(html, "size-1 shrink-0 rounded-full bg-secondary")) == 5
    refute html =~ ">-</span>"
    refute html =~ ">·</span>"
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

  describe "finding mutations require admin (cloud mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    defp member_for(org, role, prefix) do
      suffix = System.unique_integer([:positive])
      {:ok, user} = Accounts.create_user(%{email: "#{prefix}-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: "active"
      })
      |> Repo.insert!()

      user
    end

    test "post-mutation refresh redirects when the session leaves scope", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()
      admin = member_for(org, "admin", "findings-scope-admin")
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      finding = finding_fixture(%{session: session, status: "open", title: "Scope move target"})
      other_ws = workspace_fixture(%{org_id: org.id})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

      # Session moves workspaces mid-view: the stale socket still authorizes
      # the mutation, but the post-mutation refetch must not render the
      # out-of-scope session.
      {:ok, _} = Mission.update_session(session, %{workspace_id: other_ws.id})

      render_click(view, "approve_finding", %{"id" => finding.id})

      assert_redirect(view, "/")
    end

    test "viewers can read but cannot approve, escalate, or reject", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()
      viewer = member_for(org, "viewer", "findings-viewer")
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      finding = finding_fixture(%{session: session, status: "open", title: "Viewer target"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

      # Action buttons stay hidden for viewers.
      detail_html = render_click(view, "toggle_finding", %{"id" => finding.id})
      refute detail_html =~ "approve_finding"
      refute detail_html =~ "escalate_finding"
      refute detail_html =~ "reject_finding"

      denied_html = render_click(view, "approve_finding", %{"id" => finding.id})
      assert denied_html =~ "Admin or owner role required."
      assert Mission.get_finding!(finding.id).status == "open"

      escalated_html = render_click(view, "escalate_finding", %{"id" => finding.id})
      assert escalated_html =~ "Admin or owner role required."
      assert Mission.get_finding!(finding.id).status == "open"

      reject_html = render_click(view, "reject_finding", %{"id" => finding.id})
      assert reject_html =~ "Admin or owner role required."
      refute reject_html =~ "reject-reason-form"
      assert Mission.get_finding!(finding.id).status == "open"

      confirm_html = render_click(view, "confirm_reject_finding")
      assert confirm_html =~ "Admin or owner role required."
      assert Mission.get_finding!(finding.id).status == "open"
    end

    test "admins keep full approve, escalate, and reject access", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()
      admin = member_for(org, "admin", "findings-admin")
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      approve_target =
        finding_fixture(%{session: session, status: "open", title: "Admin approve"})

      escalate_target =
        finding_fixture(%{session: session, status: "open", title: "Admin escalate"})

      reject_target = finding_fixture(%{session: session, status: "open", title: "Admin reject"})

      {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/findings"))

      detail_html = render_click(view, "toggle_finding", %{"id" => approve_target.id})
      assert detail_html =~ "approve_finding"

      approved_html = render_click(view, "approve_finding", %{"id" => approve_target.id})
      assert approved_html =~ "Finding approved."
      assert Mission.get_finding!(approve_target.id).status == "approved"

      escalated_html = render_click(view, "escalate_finding", %{"id" => escalate_target.id})
      assert escalated_html =~ "Finding escalated."
      assert Mission.get_finding!(escalate_target.id).status == "escalated"

      render_click(view, "reject_finding", %{"id" => reject_target.id})
      render_click(view, "set_reject_reason", %{"reject_reason" => "false positive"})
      rejected_html = render_click(view, "confirm_reject_finding")
      assert rejected_html =~ "Finding rejected."
      assert Mission.get_finding!(reject_target.id).status == "rejected"
    end
  end
end
