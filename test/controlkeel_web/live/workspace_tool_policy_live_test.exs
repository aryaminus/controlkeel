defmodule ControlKeelWeb.WorkspaceToolPolicyLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp org_workspace! do
    owner = create_user!("tp-owner@example.com")

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "TpCo", slug: "tpco"})

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

  defp conn_for(user, _org) do
    build_conn()
    |> Plug.Test.init_test_session(%{
      "current_user_id" => user.id
    })
  end

  test "owner can view workspace tool policy under the org route" do
    {org, ws, owner} = org_workspace!()

    {:ok, _view, html} =
      live(conn_for(owner, org), ~p"/tpco/workspaces/#{ws.slug}/tool-policy")

    assert html =~ "Tool policy"
    assert html =~ "TpCo"
    # Sidebar shows workspace nav with the current page active.
    assert html =~ "sidebar-org-nav"
    assert html =~ ~s(href="/tpco/workspaces/core/repos")
    assert html =~ "aria-current=\"page\""
  end

  test "wrong org slug renders an in-place scope error" do
    {_org, ws, owner} = org_workspace!()
    org = %{id: -1, slug: "tpco"}

    {:ok, view, _html} = live(conn_for(owner, org), ~p"/other/workspaces/#{ws.slug}/tool-policy")

    assert has_element?(view, "[data-scope-error]")
  end

  test "unknown workspace slug renders an in-place scope error" do
    {org, _ws, owner} = org_workspace!()

    {:ok, view, _html} =
      live(conn_for(owner, org), ~p"/tpco/workspaces/no-such-ws/tool-policy")

    assert has_element?(view, "[data-scope-error]")
  end
end
