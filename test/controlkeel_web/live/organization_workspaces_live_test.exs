defmodule ControlKeelWeb.OrganizationWorkspacesLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts

  # The workspaces page only enforces membership access in cloud mode;
  # local mode is unrestricted. These tests run in cloud mode unless
  # a describe block switches to local.
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

  defp conn_for(user),
    do: build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

  describe "workspaces route" do
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

    test "workspaces route lists the org's workspaces", %{
      owner: owner,
      workspace: ws
    } do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/tabco/workspaces")

      assert render(view) =~ "core-workspace"
      # The workspace card links to its nested detail route.
      assert render(view) =~ ~s(href="/organizations/tabco/workspaces/#{ws.id}")
      # Workspaces table shows budget and status.
      assert render(view) =~ "$123.45"
      assert render(view) =~ "active"
      # Member management UI is not rendered on the workspaces route.
      refute render(view) =~ ~s(id="role-form-")
      refute render(view) =~ "No members yet."
    end
  end

  describe "new workspace modal" do
    setup do
      owner = create_user!("ws-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Wsco", slug: "wsco"})

      {:ok, org: org, owner: owner}
    end

    test "cloud mode opens the create form", %{owner: owner} do
      {:ok, view, html} = live(conn_for(owner), ~p"/organizations/wsco/workspaces")

      refute html =~ "new-workspace-modal"

      view |> render_click("new_workspace")
      modal = render(view)

      assert modal =~ "new-workspace-modal"
      assert modal =~ "Workspace name"
      assert modal =~ "Monthly budget"
      refute modal =~ "Only the default workspace is available in local mode."
    end

    test "cloud mode creates a workspace and lists it", %{org: org, owner: owner} do
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco/workspaces")

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
      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco/workspaces")

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

      {:ok, view, _html} = live(conn_for(owner), ~p"/organizations/wsco/workspaces")

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
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-ws-org/workspaces")

      view |> render_click("new_workspace")
      modal = render(view)

      assert modal =~ "new-workspace-modal"
      assert modal =~ "Only the default workspace is available in local mode."
      assert modal =~ "Upgrade to cloud mode to create additional workspaces."
      refute modal =~ "new-workspace-form"
    end

    test "forged save_workspace event is rejected in local mode", %{org: org} do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations/local-ws-org/workspaces")

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
end
