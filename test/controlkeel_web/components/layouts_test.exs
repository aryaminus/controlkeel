defmodule ControlKeelWeb.LayoutsTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.Layouts

  test "sidebar renders collapsible Observability section toggle button and child navigation" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    assert html =~ "sidebar-toggle-observability"
    assert html =~ "sidebar-collapse-observability"
    assert html =~ "sidebar-chevron-observability"
    assert html =~ "aria-expanded=\"false\""
    assert html =~ "hidden"
    assert html =~ "Overview"
    assert html =~ "Learning loop"
  end

  test "sidebar renders Observability section expanded when current path matches" do
    html = render_component(&Layouts.sidebar/1, current_path: "/observability")

    assert html =~ "sidebar-toggle-observability"
    assert html =~ "aria-expanded=\"true\""
    assert html =~ "rotate-90"
    assert anchor_for(html, "/observability") =~ "aria-current=\"page\""
  end

  test "sidebar highlights the matching child on deep observability paths" do
    html = render_component(&Layouts.sidebar/1, current_path: "/observability/benchmarks/history")

    assert html =~ "aria-expanded=\"true\""
    assert anchor_for(html, "/observability/benchmarks/history") =~ "aria-current=\"page\""
    refute anchor_for(html, "/observability") =~ "aria-current=\"page\""
  end

  test "sidebar does not highlight the Overview child on session pages" do
    html = render_component(&Layouts.sidebar/1, current_path: "/observability/sessions/123")

    assert html =~ "aria-expanded=\"true\""
    refute anchor_for(html, "/observability") =~ "aria-current=\"page\""
  end

  test "top-level links carry aria-current on their own active page" do
    html = render_component(&Layouts.sidebar/1, current_path: "/benchmarks")

    assert anchor_for(html, "/benchmarks") =~ "aria-current=\"page\""
    refute anchor_for(html, "/dashboard") =~ "aria-current=\"page\""
  end

  test "observability toggle is hook-driven and exposes the hook target" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    assert html =~ ~s(id="sidebar-toggle-observability")
    assert html =~ "data-sidebar-toggle"
    refute html =~ ~r|id="sidebar-toggle-observability"[^>]*phx-click|
  end

  test "sidebar scopes nav to the session on session pages" do
    html =
      render_component(&Layouts.sidebar/1, current_path: "/sessions/123", session: %{id: 123})

    assert anchor_for(html, "/sessions/123") =~ "aria-current=\"page\""
    assert html =~ "Overview"
    refute html =~ "Policy Studio"
    refute html =~ "sidebar-toggle-observability"
  end

  test "session nav wins over the workspace nav when both contexts are set" do
    html =
      render_component(&Layouts.sidebar/1,
        current_path: "/sessions/123",
        session: %{id: 123},
        org: %{slug: "acme"},
        workspace: %{id: 9}
      )

    assert anchor_for(html, "/sessions/123") =~ "aria-current=\"page\""
    refute html =~ ~s(href="/organizations/acme/workspaces/9")
  end

  describe "org_switcher" do
    test "lists orgs with the current one checked" do
      use_local_mode()

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco"})
      {:ok, _other} = ControlKeel.Accounts.create_org(%{name: "Beta Labs", slug: "beta-labs"})

      html = render_component(&Layouts.org_switcher/1, current_user: nil, org: org)

      assert html =~ ~s(id="sidebar-org-switcher")
      assert switcher_button_title(html) == "Switchco"
      assert anchor_for(html, "/organizations/switchco") =~ "Switchco"
      assert anchor_for(html, "/organizations/beta-labs") =~ "Beta Labs"
      assert html =~ "hero-check"
    end

    test "hides the subtitle without a selected org" do
      use_local_mode()

      {:ok, _org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-fb"})

      html = render_component(&Layouts.org_switcher/1, current_user: nil)

      assert html =~ "ControlKeel"
      refute html =~ "Organizations"
    end

    test "renders branding without orgs" do
      html = render_component(&Layouts.org_switcher/1, current_user: nil)

      assert html =~ ~s(id="sidebar-org-switcher")
      assert html =~ "ControlKeel"
      refute html =~ "/organizations/"
    end
  end

  describe "workspace_switcher" do
    test "shows the workspace and sibling workspaces" do
      use_local_mode()

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-ws"})

      {:ok, ws} = workspace_fixture(org, "Core", "core-ws")
      {:ok, _other} = workspace_fixture(org, "Website", "website-ws")

      html =
        render_component(&Layouts.workspace_switcher/1,
          org: org,
          workspace: ws,
          current_path: "/organizations/switchco-ws/workspaces/#{ws.id}"
        )

      assert html =~ ~s(id="sidebar-workspace-switcher")
      assert switcher_button_title(html) == "Core"
      assert html =~ ~s(aria-label="Back to Switchco")
      assert anchor_for(html, "/organizations/switchco-ws") =~ "Back to Switchco"
      assert anchor_for(html, "/organizations/switchco-ws/workspaces/#{ws.id}") =~ "Core"
      assert html =~ "Website"
      assert html =~ "hero-check"
    end

    test "renders nothing without a workspace" do
      use_local_mode()

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-ws-no"})

      html = render_component(&Layouts.workspace_switcher/1, org: org)

      refute html =~ ~s(id="sidebar-workspace-switcher")
    end
  end

  describe "session_switcher" do
    test "shows the session and workspace sessions" do
      use_local_mode()

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-se"})
      {:ok, ws} = workspace_fixture(org, "Core", "core-se")

      {:ok, session} = session_fixture(ws, "Fix payments")

      {:ok, _other} =
        ControlKeel.Mission.create_session(%{
          title: "Add refunds",
          objective: "Trace failure",
          risk_tier: "low",
          status: "active",
          workspace_id: ws.id
        })

      session = ControlKeel.Repo.preload(session, workspace: :org)

      html =
        render_component(&Layouts.session_switcher/1,
          current_path: "/sessions/#{session.id}",
          org: org,
          workspace: ws,
          session: session
        )

      assert html =~ ~s(id="sidebar-session-switcher")
      assert switcher_button_title(html) == "Fix payments"
      assert html =~ ~s(aria-label="Back to Core")

      assert anchor_for(html, "/organizations/switchco-se/workspaces/#{ws.id}") =~
               "Back to Core"

      assert anchor_for(html, "/sessions/#{session.id}") =~ "Fix payments"
      assert html =~ "Add refunds"
      assert html =~ "hero-check"
    end

    test "renders nothing without a session" do
      use_local_mode()

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-se-no"})
      {:ok, ws} = workspace_fixture(org, "Core", "core-se-no")

      html =
        render_component(&Layouts.session_switcher/1,
          org: org,
          workspace: ws,
          current_path: "/dashboard"
        )

      refute html =~ ~s(id="sidebar-session-switcher")
    end
  end

  test "sidebar renders the session switcher (and no workspace switcher) in session scope" do
    use_local_mode()

    {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-side-se"})
    {:ok, ws} = workspace_fixture(org, "Core", "core-side-se")
    {:ok, session} = session_fixture(ws, "Fix payments")
    session = ControlKeel.Repo.preload(session, workspace: :org)

    html =
      render_component(&Layouts.sidebar/1,
        current_path: "/sessions/#{session.id}",
        org: org,
        workspace: ws,
        session: session
      )

    assert html =~ ~s(id="sidebar-session-switcher")
    refute html =~ ~s(id="sidebar-workspace-switcher")
  end

  test "sidebar renders the workspace switcher (and no session switcher) in workspace scope" do
    use_local_mode()

    {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-side-ws"})
    {:ok, ws} = workspace_fixture(org, "Core", "core-side-ws")
    ws = ControlKeel.Repo.preload(ws, :org)

    html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-side-ws/workspaces/#{ws.id}",
        org: org,
        workspace: ws
      )

    assert html =~ ~s(id="sidebar-workspace-switcher")
    refute html =~ ~s(id="sidebar-session-switcher")
  end

  test "sidebar renders no scoped switcher in org scope or without scope" do
    use_local_mode()

    {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-side-org"})

    org_html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-side-org",
        org: org
      )

    refute org_html =~ ~s(id="sidebar-workspace-switcher")
    refute org_html =~ ~s(id="sidebar-session-switcher")
    assert org_html =~ ~s(id="sidebar-org-switcher")

    main_html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    refute main_html =~ ~s(id="sidebar-workspace-switcher")
    refute main_html =~ ~s(id="sidebar-session-switcher")
    assert main_html =~ ~s(id="sidebar-org-switcher")
  end

  test "org sidebar shows Overview, Workspaces, and Members with tab-aware highlighting" do
    use_local_mode()

    {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-nav"})

    members_html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-nav",
        org: org,
        active_tab: :members
      )

    assert members_html =~ "Overview"
    assert members_html =~ "Workspaces"
    assert members_html =~ "Members"

    assert members_html =~
             ~r|href="/organizations/switchco-nav/members"[^>]*aria-current="page"|

    default_html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-nav",
        org: org
      )

    assert default_html =~
             ~r|href="/organizations/switchco-nav"[^>]*aria-current="page"|

    workspaces_html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-nav",
        org: org,
        active_tab: :workspaces
      )

    assert workspaces_html =~
             ~r|href="/organizations/switchco-nav/workspaces"[^>]*aria-current="page"|
  end

  test "org sidebar does not highlight Overview on the settings page" do
    use_local_mode()

    {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-set"})

    html =
      render_component(&Layouts.sidebar/1,
        current_path: "/organizations/switchco-set/settings",
        org: org,
        can_manage: true
      )

    assert html =~
             ~r|href="/organizations/switchco-set/settings"[^>]*aria-current="page"|

    refute html =~
             ~r|href="/organizations/switchco-set"[^>]*aria-current="page"|
  end

  test "dashboard header does not render the org switcher" do
    html = render_component(&Layouts.dashboard_header/1, current_path: "/dashboard")

    refute html =~ ~s(id="sidebar-org-switcher")
  end

  defp use_local_mode do
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :local)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)
  end

  defp workspace_fixture(org, name, slug) do
    ControlKeel.Mission.create_workspace(%{
      name: name,
      slug: slug,
      org_id: org.id,
      agent: "claude",
      industry: "web",
      compliance_profile: "general"
    })
  end

  defp session_fixture(workspace, title) do
    ControlKeel.Mission.create_session(%{
      title: title,
      objective: "Trace failure",
      risk_tier: "high",
      status: "active",
      workspace_id: workspace.id
    })
  end

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end

  defp switcher_button_title(html) do
    case Regex.run(
           ~r/<span class="(?:flex-1|block truncate text-sm text-muted-foreground|block truncate text-xs text-muted-foreground)">\s*([^<]+?)\s*<\/span>/s,
           html
         ) do
      nil -> ""
      [_, title] -> String.trim(title)
    end
  end
end
