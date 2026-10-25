defmodule ControlKeelWeb.OrgCatchAllLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

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

  defp scope_fixture do
    suffix = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "catch-all-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(user.id, %{
        name: "Catch All #{suffix}",
        slug: "catch-all-#{suffix}"
      })

    {:ok, workspace} =
      Mission.create_workspace(%{
        name: "Workspace #{suffix}",
        slug: "catch-ws-#{suffix}",
        agent: "claude",
        industry: "web",
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })

    {:ok, session} =
      Mission.create_session(%{
        title: "Catch-all session",
        objective: "Resolve unmatched route scope",
        risk_tier: "low",
        status: "active",
        budget_cents: 1_000,
        spent_cents: 0,
        workspace_id: workspace.id
      })

    {org, workspace, session, user}
  end

  defp conn_for(user) do
    build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  test "unmatched routes retain their deepest accessible scope" do
    {org, workspace, session, user} = scope_fixture()
    org_path = "/#{org.slug}"
    workspace_path = "#{org_path}/workspaces/#{workspace.slug}"
    session_path = "#{workspace_path}/sessions/#{session.id}"

    routes = [
      {"/#{org.slug}/invalid-or-typo", org_path, "#{workspace_path}/sessions/#{session.id}"},
      {"#{workspace_path}/invalid-or-typo", workspace_path, session_path},
      {"#{session_path}/invalid-or-typo", session_path, workspace_path}
    ]

    for {path, expected_sidebar_path, forbidden_sidebar_path} <- routes do
      {:ok, view, _html} = live(conn_for(user), path)

      assert has_element?(view, "[data-scope-error]")
      assert has_element?(view, "h1", "Can't find the page")
      assert has_element?(view, ~s(#app-sidebar a[href="#{expected_sidebar_path}"]))
      refute has_element?(view, ~s(#app-sidebar a[href="#{forbidden_sidebar_path}"]))
      refute_redirected(view)
    end
  end

  test "an invalid session below a valid workspace retains workspace navigation" do
    {org, workspace, _session, user} = scope_fixture()
    org_path = "/#{org.slug}"
    workspace_path = "#{org_path}/workspaces/#{workspace.slug}"
    path = "#{workspace_path}/sessions/invalid-session-id/unknown-child"

    {:ok, view, _html} = live(conn_for(user), path)

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, ~s(#app-sidebar a[href="#{workspace_path}"]))
    refute has_element?(view, ~s(#app-sidebar a[href^="#{workspace_path}/sessions/"]))
    refute_redirected(view)
  end

  test "an invalid workspace route retains only organization navigation" do
    {org, _workspace, _session, user} = scope_fixture()
    org_path = "/#{org.slug}"
    path = "#{org_path}/workspaces/invalidd-ws-slug"

    {:ok, view, _html} = live(conn_for(user), path)

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, ~s(#app-sidebar a[href="#{org_path}"]))
    refute has_element?(view, ~s(#app-sidebar a[href="#{path}"]))
    refute_redirected(view)
  end

  test "local mode retains session navigation for an unknown child route" do
    Application.put_env(:controlkeel, :runtime_mode, :local)
    {org, workspace, session, _user} = scope_fixture()
    session_path = "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
    path = "#{session_path}/invalid-or-typo"

    {:ok, view, _html} = live(build_conn(), path)

    assert has_element?(view, "[data-scope-error]")
    assert has_element?(view, ~s(#app-sidebar a[href="#{session_path}"]))
    refute_redirected(view)
  end
end
