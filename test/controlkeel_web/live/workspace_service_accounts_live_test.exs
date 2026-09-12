defmodule ControlKeelWeb.WorkspaceServiceAccountsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp org_workspace! do
    owner = create_user!("sa-owner@example.com")

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "SaCo", slug: "saco"})

    {:ok, ws} =
      Mission.create_workspace(%{
        "name" => "Core",
        "slug" => "core",
        "agent" => "claude",
        "industry" => "web",
        "compliance_profile" => "general",
        "status" => "active",
        "org_id" => org.id
      })

    {org, ws, owner}
  end

  defp conn_for(user, org) do
    build_conn()
    |> Plug.Test.init_test_session(%{
      "current_user_id" => user.id,
      "current_org_id" => org.id
    })
  end

  test "owner can view workspace service accounts under the org route" do
    {org, ws, owner} = org_workspace!()

    {:ok, _view, html} =
      live(conn_for(owner, org), ~p"/saco/workspaces/#{ws.slug}/service-accounts")

    assert html =~ "Service accounts"
    assert html =~ "SaCo"
    # Sidebar shows workspace nav with the current page active.
    assert html =~ "sidebar-org-nav"
    assert html =~ ~s(href="/saco/workspaces/core/webhooks")
    assert html =~ "aria-current=\"page\""
  end

  test "wrong org slug redirects to organizations" do
    {_org, ws, owner} = org_workspace!()
    org = %{id: -1, slug: "saco"}

    assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
             live(conn_for(owner, org), ~p"/other/workspaces/#{ws.slug}/service-accounts")

    assert msg =~ "does not belong to this organization"
  end

  test "unknown workspace slug redirects to organizations" do
    {org, _ws, owner} = org_workspace!()

    assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
             live(conn_for(owner, org), ~p"/saco/workspaces/no-such-ws/service-accounts")

    assert msg =~ "Workspace not found."
  end
end
