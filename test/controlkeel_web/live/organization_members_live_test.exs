defmodule ControlKeelWeb.OrganizationMembersLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  # Member management enforces membership access in cloud mode;
  # local mode is unrestricted. These tests exercise the permission-gated UI,
  # so they run in cloud mode.
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

  describe "admin viewer role controls" do
    setup do
      owner = create_user!("owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Acme", slug: "acme"})

      admin = create_user!("admin@example.com")
      add_active_membership(admin.id, org.id, "admin")

      member = create_user!("member@example.com")
      member_m = add_active_membership(member.id, org.id, "member")

      viewer = create_user!("viewer@example.com")
      viewer_m = add_active_membership(viewer.id, org.id, "viewer")

      owner_m = Accounts.get_active_membership(owner.id, org.id)
      admin_m = Accounts.get_active_membership(admin.id, org.id)

      {:ok,
       memberships: %{owner: owner_m, admin: admin_m, member: member_m, viewer: viewer_m},
       conn: conn_for(admin)}
    end

    test "owner row is locked (disabled)", %{conn: conn, memberships: ms} do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      form = element(view, "#role-form-#{ms.owner.id}") |> render()
      assert form =~ "disabled"
      assert form =~ ~s(value="owner")
      # An admin cannot reassign an owner to any other role.
      refute form =~ ~s(value="admin")
    end

    test "admin's own row allows self-demotion only (admin/member/viewer, no owner)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      form = element(view, "#role-form-#{ms.admin.id}") |> render()
      refute form =~ "disabled"
      # Current role stays visible; owner promotion is withheld.
      assert form =~ ~s(value="admin")
      refute form =~ ~s(value="owner")
      assert form =~ ~s(value="member")
      assert form =~ ~s(value="viewer")
    end

    test "admin can self-demit to viewer", %{conn: conn, memberships: ms} do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      view
      |> element("#role-form-#{ms.admin.id}")
      |> render_change(role: "viewer")

      assert render(view) =~ "Role updated."
      # Persisted as a demotion (admin -> viewer).
      assert Accounts.get_active_membership(ms.admin.user_id, ms.admin.org_id).role == "viewer"
    end

    test "member and viewer rows offer only member/viewer (no owner/admin)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      for target <- [:member, :viewer] do
        form = element(view, "#role-form-#{ms[target].id}") |> render()
        refute form =~ "disabled"
        refute form =~ ~s(value="owner")
        refute form =~ ~s(value="admin")
        assert form =~ ~s(value="member")
        assert form =~ ~s(value="viewer")
      end
    end

    test "admin self-demotion to viewer drops management UI immediately (no reload)", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      # Sanity: admin can manage before the change.
      assert render(view) =~ ~s(id="role-form-#{ms.member.id}")

      view
      |> element("#role-form-#{ms.admin.id}")
      |> render_change(role: "viewer")

      html_after = render(view)
      assert html_after =~ "Role updated."

      # Demoted to viewer -> no longer admin+: all management controls gone.
      refute html_after =~ "role-form-"
      refute html_after =~ "open_invite"
      refute html_after =~ "confirm_revoke"

      assert Accounts.get_active_membership(ms.admin.user_id, ms.admin.org_id).role == "viewer"
    end

    test "changing another member's role updates that row immediately", %{
      conn: conn,
      memberships: ms
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme/members")

      view
      |> element("#role-form-#{ms.member.id}")
      |> render_change(role: "viewer")

      assert render(view) =~ "Role updated."
      assert Accounts.get_active_membership(ms.member.user_id, ms.member.org_id).role == "viewer"
    end
  end

  describe "owner viewer role controls" do
    setup do
      owner = create_user!("owner-a@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Omega", slug: "omega"})

      member = create_user!("member-a@example.com")
      add_active_membership(member.id, org.id, "member")

      owner_m = Accounts.get_active_membership(owner.id, org.id)

      {:ok, owner_m: owner_m, conn: conn_for(owner)}
    end

    test "sole owner cannot change their own role (locked)", %{conn: conn, owner_m: owner_m} do
      {:ok, view, _html} = live(conn, ~p"/organizations/omega/members")

      form = element(view, "#role-form-#{owner_m.id}") |> render()
      assert form =~ "disabled"
      assert form =~ ~s(value="owner")
    end

    test "owner with another owner can change their own role", %{conn: conn, owner_m: owner_m} do
      # Add a second active owner via direct membership insert.
      org_id = owner_m.org_id
      second = create_user!("owner-b@example.com")
      add_active_membership(second.id, org_id, "owner")

      {:ok, view, _html} = live(conn, ~p"/organizations/omega/members")

      form = element(view, "#role-form-#{owner_m.id}") |> render()
      refute form =~ "disabled"
      assert form =~ ~s(value="owner")
      assert form =~ ~s(value="admin")
      assert form =~ ~s(value="viewer")
    end

    test "owner self-demotion to member drops management UI immediately (no reload)", %{
      conn: conn,
      owner_m: owner_m
    } do
      # Need another owner so self-demotion isn't last-owner-protected.
      second = create_user!("owner-c@example.com")
      add_active_membership(second.id, owner_m.org_id, "owner")

      {:ok, view, _html} = live(conn, ~p"/organizations/omega/members")

      # Sanity: management controls present before the change.
      html_before = render(view)
      assert html_before =~ ~s(id="role-form-#{owner_m.id}")
      assert html_before =~ "open_invite"
      assert html_before =~ "confirm_revoke"

      view
      |> element("#role-form-#{owner_m.id}")
      |> render_change(role: "member")

      html_after = render(view)
      assert html_after =~ "Role updated."

      # Demoted to member -> no longer admin+: role selects, invite and revoke
      # controls all disappear from the same LiveView (no reload).
      refute html_after =~ "role-form-"
      refute html_after =~ "open_invite"
      refute html_after =~ "confirm_revoke"

      # Persisted.
      assert Accounts.get_active_membership(owner_m.user_id, owner_m.org_id).role == "member"
    end
  end

  describe "members route" do
    setup do
      owner = create_user!("tab-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Tabco", slug: "tabco"})

      {:ok, _ws} =
        ControlKeel.Mission.create_workspace(%{
          name: "Core Workspace",
          slug: "core-workspace",
          industry: "web",
          agent: "claude",
          budget_cents: 12_345,
          compliance_profile: "general",
          status: "active",
          org_id: org.id
        })

      {:ok, org: org, owner: owner}
    end

    test "members route lists memberships", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco/members")

      html = render(view)
      assert html =~ "tab-owner@example.com"
      refute html =~ "core-workspace"
    end

    test "clicking the Members nav item switches content", %{owner: owner} do
      conn = conn_for(owner)
      {:ok, view, _html} = live(conn, ~p"/organizations/tabco/workspaces")
      assert render(view) =~ "core-workspace"

      {:ok, _view, html} =
        view
        |> element("a[href=\"/organizations/tabco/members\"]")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "tab-owner@example.com"
      refute html =~ "core-workspace"
    end
  end

  describe "local mode members page" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      {:ok, org} = Accounts.create_org(%{name: "Local Org", slug: "local-org"})
      {:ok, org: org}
    end

    test "members route shows the local-mode notice", %{org: _org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-org/members")
      html = render(view)

      assert html =~ "Member management is not available in local mode."
      assert html =~ "Switch to cloud or self-hosted mode to invite teammates and manage roles."
    end
  end
end
