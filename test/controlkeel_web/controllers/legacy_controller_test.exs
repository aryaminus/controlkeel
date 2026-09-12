defmodule ControlKeelWeb.LegacyControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  defp create_workspace(org, name, slug) do
    {:ok, workspace} =
      Mission.create_workspace(%{
        name: name,
        slug: slug,
        industry: "web",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })

    workspace
  end

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme Corp", slug: "acme-corp"})
    workspace = create_workspace(org, "Platform", "platform")

    {:ok, org: org, workspace: workspace}
  end

  describe "legacy /organizations/:slug/workspaces/:id shapes" do
    test "detail redirects to the slug-based URL", %{conn: conn, org: org, workspace: ws} do
      conn = get(conn, ~p"/organizations/#{org.slug}/workspaces/#{ws.id}")

      assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}"
    end

    test "settings redirects to the slug-based settings URL", %{
      conn: conn,
      org: org,
      workspace: ws
    } do
      conn = get(conn, ~p"/organizations/#{org.slug}/workspaces/#{ws.id}/settings")

      assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}/settings"
    end

    test "a stale org slug still resolves via the workspace's org", %{
      conn: conn,
      org: org,
      workspace: ws
    } do
      conn = get(conn, "/organizations/stale-slug/workspaces/#{ws.id}")

      assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}"
    end
  end

  describe "legacy /workspaces/:id/* shapes" do
    test "each tab page redirects to its slug-based URL", %{
      conn: conn,
      org: org,
      workspace: ws
    } do
      for page <- ~w(repos service-accounts webhooks tool-policy) do
        conn = get(conn, "/workspaces/#{ws.id}/#{page}")

        assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}/#{page}"
      end
    end

    test "unknown ids 404", %{conn: conn} do
      assert get(conn, "/workspaces/999999/repos").status == 404
    end

    test "uncastable ids 404 instead of raising", %{conn: conn} do
      assert get(conn, "/workspaces/abc").status == 404
    end

    test "unknown subpaths 404", %{conn: conn, workspace: ws} do
      assert get(conn, "/workspaces/#{ws.id}/nope").status == 404
    end
  end
end
