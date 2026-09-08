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
    refute html =~ "phx-click"
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

  describe "sidebar_context_switcher" do
    import ControlKeel.AccountsFixtures

    test "renders orgs, workspaces, and sessions with current context highlighted" do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)
      on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco"})

      {:ok, ws} =
        ControlKeel.Mission.create_workspace(%{
          name: "Core",
          slug: "core",
          org_id: org.id,
          agent: "claude",
          industry: "web",
          compliance_profile: "general"
        })

      {:ok, session} =
        ControlKeel.Mission.create_session(%{
          title: "Fix payments",
          objective: "Trace failure",
          risk_tier: "high",
          status: "active",
          workspace_id: ws.id
        })

      html =
        render_component(&Layouts.sidebar_context_switcher/1,
          current_path: "/sessions/#{session.id}",
          org: org,
          workspace: ws
        )

      assert html =~ ~s(id="sidebar-context-switcher")
      assert html =~ "Switchco"
      assert html =~ ~s(href="/organizations/switchco")
      assert html =~ ~s(id="switcher-org-#{org.id}-workspaces")
      assert html =~ "Core"
      assert html =~ ~s(id="switcher-ws-#{ws.id}-sessions")
      assert html =~ ~s(href="/sessions/#{session.id}")
      assert html =~ "Fix payments"
      # Current org and workspace render with the highlight class.
      assert html =~ "font-semibold text-primary"
      # Button shows the deepest context (workspace) only.
      assert switcher_button_title(html) == "Core"
    end

    test "shows only the org name when no workspace or session is set" do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)
      on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-org"})

      html =
        render_component(&Layouts.sidebar_context_switcher/1,
          current_path: "/organizations/switchco-org",
          org: org
        )

      assert switcher_button_title(html) == "Switchco"
    end

    test "shows the generic label without a count when no context is set" do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)
      on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)

      {:ok, _org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-none"})

      html =
        render_component(&Layouts.sidebar_context_switcher/1,
          current_path: "/dashboard"
        )

      assert switcher_button_title(html) == "Organizations"
      refute html =~ ~r/\d+\s+organizations?/
    end

    test "shows only the session title when a session is set" do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)
      on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)

      {:ok, org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-sess"})

      {:ok, ws} =
        ControlKeel.Mission.create_workspace(%{
          name: "Core",
          slug: "core-sess",
          org_id: org.id,
          agent: "claude",
          industry: "web",
          compliance_profile: "general"
        })

      {:ok, session} =
        ControlKeel.Mission.create_session(%{
          title: "Fix payments",
          objective: "Trace failure",
          risk_tier: "high",
          status: "active",
          workspace_id: ws.id
        })

      html =
        render_component(&Layouts.sidebar_context_switcher/1,
          current_path: "/sessions/#{session.id}",
          org: org,
          workspace: ws,
          session: session
        )

      assert switcher_button_title(html) == "Fix payments"
    end

    test "renders nothing without orgs" do
      html = render_component(&Layouts.sidebar_context_switcher/1, current_path: "/dashboard")

      refute html =~ ~s(id="sidebar-context-switcher")
    end
  end

  test "sidebar keeps the context switcher with the ContextSwitcher hook" do
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :local)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)

    {:ok, _org} = ControlKeel.Accounts.create_org(%{name: "Switchco", slug: "switchco-side"})

    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    assert html =~ ~s(id="sidebar-context-switcher")
    assert html =~ ~s(phx-hook="ContextSwitcher")
    assert html =~ ~s(data-context-switcher-popover)
  end

  test "dashboard header does not render the context switcher" do
    html = render_component(&Layouts.dashboard_header/1, current_path: "/dashboard")

    refute html =~ ~s(id="sidebar-context-switcher")
  end

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end

  defp switcher_button_title(html) do
    case Regex.run(
           ~r|class="block truncate text-sm font-semibold text-foreground">\s*([^<]+?)\s*<|s,
           html
         ) do
      nil -> ""
      [_, title] -> String.trim(title)
    end
  end
end
