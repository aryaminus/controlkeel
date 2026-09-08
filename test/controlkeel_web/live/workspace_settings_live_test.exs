defmodule ControlKeelWeb.WorkspaceSettingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp create_workspace(attrs) do
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()
      |> Map.merge(%{
        "agent" => "claude",
        "industry" => "web",
        "compliance_profile" => "general",
        "status" => "active"
      })

    {:ok, ws} = Mission.create_workspace(attrs)
    ws
  end

  defp org_workspace do
    {:ok, org} = Accounts.create_org(%{name: "Settings Org", slug: "settings-org"})
    ws = create_workspace(%{name: "Core", slug: "core", industry: "web", org_id: org.id})
    {org, ws}
  end

  defp policy_set_fixture!(name) do
    {:ok, set} =
      Platform.create_policy_set(%{
        "name" => name,
        "description" => "Block destructive deletes",
        "rules" => [
          %{
            "id" => "shell.destructive_rm_rf",
            "category" => "security",
            "severity" => "critical",
            "action" => "block",
            "plain_message" => "Recursive force-delete commands are blocked.",
            "matcher" => %{"type" => "regex", "patterns" => ["rm -rf"]}
          }
        ]
      })

    set
  end

  defp submit_apply(view, params) do
    view
    |> element("#workspace-policy-apply-form")
    |> render_submit(%{"assignment" => params})
  end

  describe "local mode" do
    test "renders the policies tab by default" do
      {org, ws} = org_workspace()

      {:ok, view, html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      assert html =~ "Workspace settings"
      assert has_element?(view, "#workspace-policy-apply-form")
      refute has_element?(view, "#workspace-tool-policy-form")
    end

    test "sidebar is scoped to the workspace" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      sidebar = view |> element("#sidebar-nav") |> render()

      assert sidebar =~ "Overview"
      assert sidebar =~ ~s(href="/organizations/#{org.slug}/workspaces/#{ws.id}")
      assert sidebar =~ ~s(href="/organizations/#{org.slug}/workspaces/#{ws.id}/settings")
      refute sidebar =~ "Policy Studio"
    end

    test "unknown tab params fall back to the policies tab" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(
          build_conn(),
          ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=nonsense"
        )

      assert has_element?(view, "#workspace-policy-apply-form")
    end

    test "agent_tools tab renders via query param" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(
          build_conn(),
          ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=agent_tools"
        )

      assert has_element?(view, "#workspace-tool-policy-form")
      refute has_element?(view, "#workspace-policy-apply-form")
    end

    test "set_tab patches the URL and switches panels" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      view
      |> element("button[phx-value-tab='agent_tools']")
      |> render_click()

      assert_patch(
        view,
        ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=agent_tools"
      )

      assert has_element?(view, "#workspace-tool-policy-form")

      view
      |> element("button[phx-value-tab='policies']")
      |> render_click()

      assert_patch(view, ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=policies")
      assert has_element?(view, "#workspace-policy-apply-form")
    end

    test "applies a policy set to the workspace" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("no-rm-rf")

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html = submit_apply(view, %{"policy_set_id" => "#{set.id}", "precedence" => "10"})

      assert html =~ "Policy set applied."
      assert html =~ "no-rm-rf"
      assert html =~ "precedence 10"
      # Applied set leaves the available dropdown.
      refute has_element?(view, "#policy-set-select option[value='#{set.id}']")

      assert [%{policy_set_id: set_id, precedence: 10}] =
               Platform.list_workspace_policy_sets(ws.id)

      assert set_id == set.id
    end

    test "re-applying via upsert updates precedence" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("upsert-me")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 10})

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      # The set is already applied so it is not in the dropdown; remove then
      # re-apply with a new precedence through the form.
      render_click(view, "remove_policy_set", %{"policy-set-id" => "#{set.id}"})
      submit_apply(view, %{"policy_set_id" => "#{set.id}", "precedence" => "42"})

      assert [%{precedence: 42}] = Platform.list_workspace_policy_sets(ws.id)
    end

    test "apply with a non-numeric precedence flashes an error" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("bad-prec")

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html = submit_apply(view, %{"policy_set_id" => "#{set.id}", "precedence" => "abc"})

      assert html =~ "Choose a policy set and a non-negative precedence."
      assert Platform.list_workspace_policy_sets(ws.id) == []
    end

    test "apply with an out-of-range precedence flashes an error instead of crashing" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("huge-prec")

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html =
        submit_apply(view, %{
          "policy_set_id" => "#{set.id}",
          "precedence" => "99999999999999999999"
        })

      assert html =~ "precedence"
      assert html =~ "less than or equal to"
      assert Platform.list_workspace_policy_sets(ws.id) == []
      # The view survived the failed insert.
      assert render(view) =~ "Workspace settings"
    end

    test "removes an applied policy set" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("remove-me")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 5})

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html = render_click(view, "remove_policy_set", %{"policy-set-id" => "#{set.id}"})

      assert html =~ "Policy set removed."
      assert Platform.list_workspace_policy_assignments(ws.id) == []
      # Back in the dropdown once removed.
      assert has_element?(view, "#policy-set-select option[value='#{set.id}']")
    end

    test "disabled assignments are listed with a marker and kept out of the dropdown" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("paused-set")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{"enabled" => false})

      {:ok, view, html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      assert html =~ "paused-set"
      assert html =~ "precedence 100"
      assert html =~ ", disabled"
      # The disabled row still occupies the assignment slot: re-applying via
      # the dropdown would silently flip it to enabled, so it is not offered.
      refute has_element?(view, "#policy-set-select option[value='#{set.id}']")
      # Removing the disabled assignment works without an enabled re-apply.
      html = render_click(view, "remove_policy_set", %{"policy-set-id" => "#{set.id}"})
      assert html =~ "Policy set removed."
      assert Platform.list_workspace_policy_assignments(ws.id) == []
    end

    test "toggle_assignment disables an enabled assignment and stops rule evaluation" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("toggle-off")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 25})

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html =
        render_click(
          view,
          "toggle_assignment",
          %{"policy-set-id" => "#{set.id}"}
        )

      assert html =~ "Policy set disabled."
      assert html =~ ", disabled"

      assert [%{enabled: false, precedence: 25}] =
               Platform.list_workspace_policy_assignments(ws.id)

      # Disabled assignments no longer participate in rule evaluation.
      assert Platform.list_workspace_policy_sets(ws.id) == []
    end

    test "toggle_assignment re-enables a disabled assignment preserving precedence" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("toggle-on")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 15, enabled: false})

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      assert has_element?(
               view,
               "button[phx-click='toggle_assignment'][phx-value-policy-set-id='#{set.id}']",
               "Enable"
             )

      html =
        render_click(
          view,
          "toggle_assignment",
          %{"policy-set-id" => "#{set.id}"}
        )

      assert html =~ "Policy set enabled."
      refute html =~ ", disabled"

      assert [%{enabled: true, precedence: 15}] =
               Platform.list_workspace_policy_assignments(ws.id)

      assert [%{policy_set_id: set_id}] = Platform.list_workspace_policy_sets(ws.id)
      assert set_id == set.id
    end

    test "toggle_assignment with an unknown policy set id flashes an error" do
      {org, ws} = org_workspace()
      set = policy_set_fixture!("not-toggled")
      {:ok, _} = Platform.apply_policy_set(ws.id, set.id, %{precedence: 1})

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html = render_click(view, "toggle_assignment", %{"policy-set-id" => "999999"})

      assert html =~ "Policy set assignment not found."
      assert [%{enabled: true}] = Platform.list_workspace_policy_assignments(ws.id)
    end

    test "remove with an invalid policy set id flashes an error" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      html = render_click(view, "remove_policy_set", %{"policy-set-id" => "abc"})

      assert html =~ "Invalid policy set id."
    end

    test "tool picker adds and removes selected tools" do
      {org, ws} = org_workspace()

      {:ok, view, html} =
        live(
          build_conn(),
          ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=agent_tools"
        )

      assert html =~ "No tools selected."

      # Fresh workspaces inherit, which disables the picker; pick a mode first.
      view
      |> element("#tool-policy-mode")
      |> render_change(%{"policy" => %{"mode" => "allowlist"}})

      view
      |> element("#tool-policy-picker")
      |> render_change(%{"tool_picker" => "ck_validate"})

      assert has_element?(view, "button[phx-value-tool='ck_validate']")
      # Picked tool leaves the picker options.
      refute has_element?(view, "#tool-policy-picker option[value='ck_validate']")
      # Duplicate picks are ignored.
      view
      |> element("#tool-policy-picker")
      |> render_change(%{"tool_picker" => "ck_validate"})

      chip_count =
        (render(view) |> String.split("phx-value-tool=\"ck_validate\"") |> length()) - 1

      assert chip_count == 1

      render_click(view, "remove_tool", %{"tool" => "ck_validate"})

      refute has_element?(view, "button[phx-value-tool='ck_validate']")
    end

    test "submit persists an allowlist policy with the picked tools" do
      {org, ws} = org_workspace()

      {:ok, view, _html} =
        live(
          build_conn(),
          ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=agent_tools"
        )

      view
      |> element("#tool-policy-mode")
      |> render_change(%{"policy" => %{"mode" => "allowlist"}})

      view
      |> element("#tool-policy-picker")
      |> render_change(%{"tool_picker" => "ck_validate"})

      html =
        view
        |> element("#workspace-tool-policy-form")
        |> render_submit(%{"policy" => %{"mode" => "allowlist"}})

      assert html =~ "Agent tools policy saved (allowlist)."

      policy = Accounts.get_workspace_tool_policy(ws.id)
      assert policy.mode == "allowlist"
      assert WorkspaceToolPolicy.decode_tools(policy) == ["ck_validate"]
    end

    test "submitting inherit clears previously stored tools" do
      {org, ws} = org_workspace()
      Accounts.set_workspace_tool_policy(ws.id, "allowlist", ["ck_validate"])

      {:ok, view, _html} =
        live(
          build_conn(),
          ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings?tab=agent_tools"
        )

      # Stored tools are shown as chips on mount.
      assert has_element?(view, "button[phx-value-tool='ck_validate']")

      view
      |> element("#tool-policy-mode")
      |> render_change(%{"policy" => %{"mode" => "inherit"}})

      html =
        view
        |> element("#workspace-tool-policy-form")
        |> render_submit(%{"policy" => %{"mode" => "inherit"}})

      assert html =~ "Agent tools policy saved (inherit)."

      policy = Accounts.get_workspace_tool_policy(ws.id)
      assert policy.mode == "inherit"
      # Inherit never keeps stale selections around.
      assert WorkspaceToolPolicy.decode_tools(policy) == []
    end

    test "redirects for an unknown workspace id" do
      {:ok, _org} = Accounts.create_org(%{name: "None", slug: "none"})

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(build_conn(), ~p"/organizations/none/workspaces/999999/settings")

      assert msg =~ "Workspace not found."
    end

    test "redirects when the workspace belongs to a different org slug" do
      {_org_a, ws} = org_workspace()

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(build_conn(), ~p"/organizations/other-org/workspaces/#{ws.id}/settings")

      assert msg =~ "does not belong to this organization"
    end
  end

  describe "cloud mode org scoping" do
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

    defp add_active_membership(user_id, org_id, role) do
      %Membership{}
      |> Membership.changeset(%{user_id: user_id, org_id: org_id, role: role, status: "active"})
      |> Repo.insert!()
    end

    test "an org admin can open workspace settings" do
      owner = create_user!("settings-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "AdminCo", slug: "adminco"})
      ws = create_workspace(%{name: "AdminWs", slug: "adminws", industry: "web", org_id: org.id})

      admin = create_user!("settings-admin@example.com")
      add_active_membership(admin.id, org.id, "admin")

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_user_id" => admin.id,
          "current_org_id" => org.id
        })

      {:ok, _view, html} = live(conn, ~p"/organizations/adminco/workspaces/#{ws.id}/settings")

      assert html =~ "Workspace settings"
    end

    test "a viewer role member is refused access" do
      owner = create_user!("settings-view-owner@example.com")

      {:ok, org} =
        Accounts.create_org_with_owner(owner.id, %{name: "ViewerCo", slug: "viewerco"})

      ws =
        create_workspace(%{name: "ViewerWs", slug: "viewerws", industry: "web", org_id: org.id})

      viewer = create_user!("settings-viewer@example.com")
      add_active_membership(viewer.id, org.id, "viewer")

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_user_id" => viewer.id,
          "current_org_id" => org.id
        })

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(conn, ~p"/organizations/viewerco/workspaces/#{ws.id}/settings")

      assert msg =~ "Admin or owner role required."
    end

    test "a user outside the org is refused access" do
      owner_a = create_user!("settings-a@example.com")
      {:ok, org_a} = Accounts.create_org_with_owner(owner_a.id, %{name: "SetA", slug: "seta"})

      ws_a =
        create_workspace(%{name: "Secret", slug: "secret", industry: "web", org_id: org_a.id})

      outsider = create_user!("settings-b@example.com")
      {:ok, org_b} = Accounts.create_org_with_owner(outsider.id, %{name: "SetB", slug: "setb"})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_user_id" => outsider.id,
          "current_org_id" => org_b.id
        })

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(conn, ~p"/organizations/seta/workspaces/#{ws_a.id}/settings")

      assert msg =~ "Workspace belongs to a different organization."
    end
  end
end
