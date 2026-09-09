defmodule ControlKeelWeb.OrganizationDetailLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  # The overview page only enforces membership access in cloud mode;
  # local mode is unrestricted. These tests run in cloud mode.
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

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end

  describe "org settings page" do
    setup do
      owner = create_user!("owner-set@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Setco", slug: "setco"})

      admin = create_user!("admin-set@example.com")
      add_active_membership(admin.id, org.id, "admin")

      member = create_user!("member-set@example.com")
      add_active_membership(member.id, org.id, "member")

      {:ok, org: org, owner: owner, admin: admin, member: member}
    end

    test "settings link appears in the org sidebar and navigates to settings page", %{
      owner: owner
    } do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/setco")

      assert render(view) =~ "Settings"
      assert render(view) =~ ~s(href="/organizations/setco/settings")

      {:ok, settings_view, _html} = live(conn_for(owner), ~p"/organizations/setco/settings")
      assert render(settings_view) =~ "Organization settings"
      assert render(settings_view) =~ "Organization name"
    end

    test "owner can save the org name via settings page", %{org: org, owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/setco/settings")

      assert render(view) =~ "Organization settings"
      assert render(view) =~ "Organization name"

      view
      |> element("#org-settings-form")
      |> render_submit(%{
        "settings" => %{"name" => "Setco Renamed", "status" => "active", "budget_cents" => "0"}
      })

      assert render(view) =~ "Settings saved."
      assert Accounts.get_org(org.id).name == "Setco Renamed"
    end

    test "admin can view the settings page but status and budget are owner-locked", %{
      admin: admin
    } do
      {:ok, view, _html} = live(conn_for(admin), ~p"/organizations/setco/settings")

      html = render(view)

      assert html =~ "Organization settings"
      assert html =~ "Only owners can change status."
      assert html =~ "Only owners can change budget."
    end

    test "non-admin members do not see the settings link", %{member: member} do
      {:ok, _view, html} = live(conn_for(member), ~p"/organizations/setco")

      refute html =~ "/organizations/setco/settings"
    end

    test "non-admin member cannot save settings via a forged event", %{
      org: org,
      member: member
    } do
      # Members can mount the settings LiveView; the inputs are locked, but the
      # server must still reject a forged `save_settings` event so they cannot
      # rename the org or touch owner-only fields.
      {:ok, view, _html} = live(conn_for(member), ~p"/organizations/setco/settings")

      html =
        view
        |> render_click("save_settings", %{
          "settings" => %{"name" => "Hacked", "status" => "disabled", "budget_cents" => "999"}
        })

      refute html =~ "Settings saved."
      assert html =~ "have permission to change organization settings"
      reloaded = Accounts.get_org(org.id)
      assert reloaded.name == "Setco"
      assert reloaded.status == "active"
    end
  end

  describe "organization overview route" do
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

    test "overview shows only overview data", %{
      owner: owner
    } do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/tabco")

      assert html =~ "Tabco"
      assert html =~ "Workspaces"
      assert html =~ "/members"
      # Neither the workspaces list nor member management renders here.
      refute render(view) =~ "core-workspace"
      refute render(view) =~ ~s(id="role-form-")
      refute render(view) =~ "No members yet."
    end

    test "overview shows stats, recent sessions, top workspaces, and actions", %{
      owner: owner,
      workspace: ws
    } do
      {:ok, session} =
        ControlKeel.Mission.create_session(%{
          title: "Fix payments",
          objective: "Trace failure",
          risk_tier: "high",
          status: "active",
          workspace_id: ws.id
        })

      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/tabco")

      # Stat cards.
      assert html =~ "Recent sessions"
      assert html =~ "Top workspaces"
      # Recent session links to its page with the workspace name.
      assert anchor_for(html, "/sessions/#{session.id}") =~ "Fix payments"
      assert html =~ "Core Workspace"
      # Quick actions link to the scoped routes.
      assert html =~ ~s(href="/organizations/tabco/workspaces")
      assert html =~ ~s(href="/organizations/tabco/members")
      # Members snapshot links out.
      assert render(view) =~ "Manage members"
    end

    test "unknown tab value falls back to overview", %{owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco?tab=wat")
      html = render(view)
      assert html =~ "Tabco"
      refute html =~ "core-workspace"
    end

    test "legacy tab URLs redirect to their canonical routes", %{owner: owner} do
      assert {:error, {:live_redirect, %{to: "/organizations/tabco/members"}}} =
               live(conn_for(owner), ~p"/organizations/tabco?tab=members")
    end
  end

  describe "local mode overview" do
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

    test "overview renders without the members notice", %{org: _org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-org")
      assert render(view) =~ "Workspaces"
      refute render(view) =~ "Member management is not available in local mode."
    end
  end
end
