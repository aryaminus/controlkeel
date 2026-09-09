defmodule ControlKeelWeb.OrganizationDetailLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  # The member-management page only enforces membership access in cloud mode;
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
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

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
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

      form = element(view, "#role-form-#{ms.admin.id}") |> render()
      refute form =~ "disabled"
      # Current role stays visible; owner promotion is withheld.
      assert form =~ ~s(value="admin")
      refute form =~ ~s(value="owner")
      assert form =~ ~s(value="member")
      assert form =~ ~s(value="viewer")
    end

    test "admin can self-demit to viewer", %{conn: conn, memberships: ms} do
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

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
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

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
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

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
      {:ok, view, _html} = live(conn, ~p"/organizations/acme?tab=members")

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
      {:ok, view, _html} = live(conn, ~p"/organizations/omega?tab=members")

      form = element(view, "#role-form-#{owner_m.id}") |> render()
      assert form =~ "disabled"
      assert form =~ ~s(value="owner")
    end

    test "owner with another owner can change their own role", %{conn: conn, owner_m: owner_m} do
      # Add a second active owner via direct membership insert.
      org_id = owner_m.org_id
      second = create_user!("owner-b@example.com")
      add_active_membership(second.id, org_id, "owner")

      {:ok, view, _html} = live(conn, ~p"/organizations/omega?tab=members")

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

      {:ok, view, _html} = live(conn, ~p"/organizations/omega?tab=members")

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

  describe "org settings modal" do
    setup do
      owner = create_user!("owner-set@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Setco", slug: "setco"})

      admin = create_user!("admin-set@example.com")
      add_active_membership(admin.id, org.id, "admin")

      member = create_user!("member-set@example.com")
      add_active_membership(member.id, org.id, "member")

      {:ok, org: org, owner: owner, admin: admin, member: member}
    end

    test "settings action appears in the dashboard header and opens the modal", %{owner: owner} do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/setco?tab=members")

      refute html =~ "org-settings-modal"
      assert render(view) =~ ~s(id="dashboard-page-action")
      assert render(view) =~ "phx-click=\"open_settings\""

      view |> render_click("open_settings")
      assert render(view) =~ "org-settings-modal"
      assert render(view) =~ "Organization name"
    end

    test "owner opens the modal and saves the org name", %{org: org, owner: owner} do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/setco?tab=members")

      # Modal is absent until opened.
      refute html =~ "org-settings-modal"

      view |> render_click("open_settings")
      assert render(view) =~ "org-settings-modal"
      assert render(view) =~ "Organization name"

      view
      |> element("#org-settings-form")
      |> render_submit(%{
        "settings" => %{"name" => "Setco Renamed", "status" => "active", "budget_cents" => "0"}
      })

      assert render(view) =~ "Settings saved."
      assert Accounts.get_org(org.id).name == "Setco Renamed"
    end

    test "admin can open the modal but status and budget are owner-locked", %{admin: admin} do
      {:ok, view, _html} = live(conn_for(admin), ~p"/organizations/setco?tab=members")

      view |> render_click("open_settings")
      html = render(view)

      assert html =~ "org-settings-modal"
      assert html =~ "Only owners can change status."
      assert html =~ "Only owners can change budget."
    end

    test "non-admin members do not see the settings button", %{member: member} do
      {:ok, _view, html} = live(conn_for(member), ~p"/organizations/setco?tab=members")

      refute html =~ "open_settings"
    end

    test "non-admin member cannot save settings via a forged event", %{
      org: org,
      member: member
    } do
      # Members can mount the org detail LiveView; the button is hidden, but the
      # server must still reject a forged `save_settings` event so they cannot
      # rename the org or touch owner-only fields.
      {:ok, view, _html} = live(conn_for(member), ~p"/organizations/setco?tab=members")

      view
      |> render_click("save_settings", %{
        "settings" => %{"name" => "Hacked", "status" => "disabled", "budget_cents" => "999"}
      })

      refute render(view) =~ "Settings saved."
      reloaded = Accounts.get_org(org.id)
      assert reloaded.name == "Setco"
      assert reloaded.status == "active"
    end
  end

  describe "workspaces and members tabs" do
    setup do
      owner = create_user!("tab-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Tabco", slug: "tabco"})

      {:ok, ws} =
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

      {:ok, org: org, owner: owner, workspace: ws}
    end

    test "workspaces is the default tab and lists the org's workspaces", %{
      owner: owner,
      workspace: ws
    } do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/tabco")

      assert html =~ "Workspaces"
      assert html =~ "?tab=members"
      assert render(view) =~ "core-workspace"
      # The workspace card links to its nested detail route.
      assert render(view) =~ ~s(href="/organizations/tabco/workspaces/#{ws.id}")
      # Workspaces table shows budget and status.
      assert render(view) =~ "$123.45"
      assert render(view) =~ "active"
      # Member management UI is not rendered on the default tab.
      refute render(view) =~ ~s(id="role-form-")
      refute render(view) =~ "No members yet."
    end

    test "members tab lists memberships", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco?tab=members")

      html = render(view)
      assert html =~ "tab-owner@example.com"
      refute html =~ "core-workspace"
    end

    test "clicking the Members tab switches content", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco")
      assert render(view) =~ "core-workspace"

      view
      |> element("a[href=\"/organizations/tabco?tab=members\"]")
      |> render_click()

      html = render(view)
      assert html =~ "tab-owner@example.com"
      refute html =~ "core-workspace"
    end

    test "unknown tab value falls back to workspaces", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco?tab=wat")
      assert render(view) =~ "core-workspace"
    end
  end

  describe "new workspace modal" do
    setup do
      owner = create_user!("ws-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Wsco", slug: "wsco"})

      {:ok, org: org, owner: owner}
    end

    test "cloud mode opens the create form", %{owner: owner} do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/wsco")

      refute html =~ "new-workspace-modal"

      view |> render_click("new_workspace")
      modal = render(view)

      assert modal =~ "new-workspace-modal"
      assert modal =~ "Workspace name"
      assert modal =~ "Monthly budget"
      refute modal =~ "Only the default workspace is available in local mode."
    end

    test "cloud mode creates a workspace and lists it", %{org: org, owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco")

      view |> render_click("new_workspace")

      view
      |> element("#new-workspace-form")
      |> render_submit(%{
        "workspace" => %{
          "name" => "Data Pipeline",
          "slug" => "data-pipeline",
          "industry" => "web",
          "budget_cents" => "5000"
        }
      })

      html = render(view)
      assert html =~ "Workspace Data Pipeline created."
      assert html =~ "data-pipeline"

      workspace = ControlKeel.Mission.get_workspace_by_slug("data-pipeline")
      assert workspace.org_id == org.id
      assert workspace.status == "active"
    end

    test "blank slug is auto-generated from the name", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco")

      view |> render_click("new_workspace")

      view
      |> element("#new-workspace-form")
      |> render_submit(%{
        "workspace" => %{
          "name" => "Payments Core",
          "slug" => "",
          "industry" => "finance",
          "budget_cents" => "0"
        }
      })

      assert render(view) =~ "payments-core"
      assert ControlKeel.Mission.get_workspace_by_slug("payments-core")
    end

    test "slug collision surfaces a validation error", %{owner: owner, org: org} do
      {:ok, _ws} =
        ControlKeel.Mission.create_workspace(%{
          name: "Existing",
          slug: "taken",
          industry: "web",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: org.id
        })

      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco")

      view |> render_click("new_workspace")

      view
      |> element("#new-workspace-form")
      |> render_submit(%{
        "workspace" => %{
          "name" => "Other",
          "slug" => "taken",
          "industry" => "web",
          "budget_cents" => "0"
        }
      })

      assert render(view) =~ "has already been taken"
      refute render(view) =~ "Workspace Other created."
    end
  end

  describe "new workspace modal in local mode" do
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

      {:ok, org} = Accounts.create_org(%{name: "Local WS Org", slug: "local-ws-org"})
      {:ok, org: org}
    end

    test "modal shows the local-mode notice instead of the form", %{org: _org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-ws-org")

      view |> render_click("new_workspace")
      modal = render(view)

      assert modal =~ "new-workspace-modal"
      assert modal =~ "Only the default workspace is available in local mode."
      assert modal =~ "Upgrade to cloud mode to create additional workspaces."
      refute modal =~ "new-workspace-form"
    end

    test "forged save_workspace event is rejected in local mode", %{org: org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-ws-org")

      view
      |> render_click("save_workspace", %{
        "workspace" => %{
          "name" => "Sneaky",
          "slug" => "sneaky",
          "industry" => "web",
          "budget_cents" => "0"
        }
      })

      refute render(view) =~ "Workspace Sneaky created."
      assert ControlKeel.Mission.list_workspaces_for_org(org.id) == []
    end
  end

  describe "local mode members tab" do
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

    test "workspaces is the default tab and members shows the local-mode notice", %{org: _org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-org")
      assert render(view) =~ "Workspaces"
      refute render(view) =~ "Member management is not available in local mode."

      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-org?tab=members")
      html = render(view)

      assert html =~ "Member management is not available in local mode."
      assert html =~ "Switch to cloud or self-hosted mode to invite teammates and manage roles."
    end
  end
end
