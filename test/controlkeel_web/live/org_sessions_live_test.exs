defmodule ControlKeelWeb.OrgSessionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  # Session pages enforce membership access in cloud mode; local mode is
  # unrestricted. These tests exercise the permission-gated UI, so they run
  # in cloud mode.
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

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp add_active_membership(user_id, org_id, role) do
    %Membership{}
    |> Membership.changeset(%{user_id: user_id, org_id: org_id, role: role, status: "active"})
    |> Repo.insert!()
  end

  defp conn_for(user),
    do: build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

  defp create_workspace(org, name, slug) do
    {:ok, workspace} =
      Mission.create_workspace(%{
        name: name,
        slug: slug,
        industry: "general",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })

    workspace
  end

  defp create_session(workspace, title) do
    {:ok, session} =
      Mission.create_session(%{
        title: title,
        objective: "Ship the thing",
        risk_tier: "medium",
        status: "active",
        budget_cents: 0,
        daily_budget_cents: 0,
        spent_cents: 0,
        workspace_id: workspace.id
      })

    session
  end

  describe "org sessions index" do
    setup do
      owner = create_user!("sess-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Sessco", slug: "sessco"})

      ws_a = create_workspace(org, "Alpha", "alpha")
      ws_b = create_workspace(org, "Beta", "beta")

      {:ok, org: org, owner: owner, ws_a: ws_a, ws_b: ws_b}
    end

    test "lists every session across the org's workspaces with workspace names", %{
      owner: owner,
      ws_a: ws_a,
      ws_b: ws_b
    } do
      create_session(ws_a, "Alpha one")
      create_session(ws_b, "Beta one")

      {:ok, _view, html} = live(conn_for(owner), ~p"/sessco/sessions")

      assert html =~ "Sessions"
      assert html =~ "Alpha one"
      assert html =~ "Beta one"
      # The owning workspace shows in its own column.
      assert html =~ "Alpha"
      assert html =~ "Beta"
      # Rows link into the standard nested session route.
      assert html =~ ~s(/sessco/workspaces/alpha/sessions/)
      assert html =~ ~s(/sessco/workspaces/beta/sessions/)
    end

    test "renders the empty state when the org has no sessions", %{owner: owner} do
      {:ok, _view, html} = live(conn_for(owner), ~p"/sessco/sessions")

      assert html =~ "No sessions yet."
      assert html =~ "Start a session from any workspace to see it here."
    end

    test "any active member (viewer) can view the org's sessions", %{
      org: org,
      ws_a: ws_a
    } do
      viewer = create_user!("sess-viewer@example.com")
      add_active_membership(viewer.id, org.id, "viewer")
      create_session(ws_a, "Alpha one")

      {:ok, _view, html} = live(conn_for(viewer), ~p"/sessco/sessions")

      assert html =~ "Alpha one"
      # The owning workspace shows in its own column.
      assert html =~ "Alpha"
    end

    test "a user without any membership is bounced to /new/org by the auth hook", %{
      org: _org
    } do
      outsider = create_user!("outsider@example.com")

      assert {:error, {:redirect, %{to: "/new/org"}}} =
               live(conn_for(outsider), ~p"/sessco/sessions")
    end

    # Tenant isolation: a member of a different org must not see this org's
    # sessions — the shared in-place not-found panel renders instead, and
    # deliberately shares its copy with the genuinely-missing case.
    test "a member of another org sees this org's sessions (tenant isolation)", %{
      ws_a: ws_a
    } do
      create_session(ws_a, "Alpha one")

      other_owner = create_user!("other-sess-owner@example.com")

      {:ok, _other_org} =
        Accounts.create_org_with_owner(other_owner.id, %{name: "Otherco", slug: "otherco"})

      {:ok, _view, html} = live(conn_for(other_owner), ~p"/sessco/sessions")

      refute html =~ "Alpha one"
      assert html =~ "Organization not found"
      assert html =~ "No organization exists at this address"
    end

    # Membership revocation kills access at resolve time: a revoked member
    # (status no longer active) is treated like any non-member.
    test "a revoked member loses access to the org's sessions", %{
      org: org,
      owner: owner,
      ws_a: ws_a
    } do
      create_session(ws_a, "Alpha one")

      member = create_user!("sess-revoked@example.com")
      member_m = add_active_membership(member.id, org.id, "member")
      assert live(conn_for(member), ~p"/sessco/sessions") |> elem(2) =~ "Alpha one"

      member_m |> Membership.changeset(%{status: "revoked"}) |> Repo.update!()

      # The auth hook bounces a revoked member to the org picker, exactly
      # like a signed-in user with no membership.
      assert {:error, {:redirect, %{to: "/new/org"}}} =
               live(conn_for(member), ~p"/sessco/sessions")
    end

    # The index streams a bounded page (@page_size 50) and "Load more"
    # keyset-paginates; this also exercises the (inserted_at, id) tie-break
    # since all rows share the same second.
    test "streams a bounded first page and loads the remainder on demand", %{
      org: org,
      owner: owner
    } do
      ws = create_workspace(org, "Gamma", "gamma")

      for i <- 1..51 do
        title = "Session " <> String.pad_leading(Integer.to_string(i), 3, "0")
        create_session(ws, title)
      end

      {:ok, view, html} = live(conn_for(owner), ~p"/sessco/sessions")

      # First page: newest 50 rows, oldest session withheld.
      assert html =~ "Session 051"
      assert html =~ "Session 002"
      refute html =~ "Session 001"
      assert has_element?(view, "#org-sessions-load-more")

      view |> element("#org-sessions-load-more") |> render_click()

      html = render(view)
      # The oldest row streams in after the button; the keyset cursor makes
      # it land in its position (no re-fetch of rows already rendered).
      assert html =~ "Session 001"
      # One row left, fewer than the page size: no further page.
      refute has_element?(view, "#org-sessions-load-more")
    end
  end
end
