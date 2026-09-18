defmodule ControlKeelWeb.OrganizationSessionNavTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.OrganizationLayouts

  defp nav_assigns(current_path) do
    %{
      current_user: nil,
      current_path: current_path,
      current_query: nil,
      nav_org: %{id: 1, slug: "acme", name: "Acme"},
      nav_workspace: %{slug: "core"},
      nav_session: %{id: 42, title: "ControlKeel Session"}
    }
  end

  defp header_assigns(current_path, breadcrumbs, sibling_sessions) do
    %{
      current_user: nil,
      current_path: current_path,
      current_query: nil,
      page_action: nil,
      breadcrumbs: breadcrumbs,
      nav_org: %{id: 1, slug: "acme", name: "Acme"},
      nav_workspace: %{id: 2, slug: "core", name: "Core"},
      nav_session: %{id: 42, title: "Session A"},
      sibling_workspaces: [],
      sibling_sessions: sibling_sessions
    }
  end

  defp session_crumbs(session_id, session_title, subpage) do
    session_to =
      if subpage, do: "/acme/workspaces/core/sessions/#{session_id}", else: nil

    base = [
      %{label: "Acme", to: "/acme"},
      %{label: "Core", to: "/acme/workspaces/core"},
      %{label: session_title, to: session_to}
    ]

    if subpage, do: base ++ [%{label: subpage, to: nil}], else: base
  end

  test "session pages render session nav instead of workspace nav" do
    html =
      render_component(
        &OrganizationLayouts.organization_sidebar/1,
        nav_assigns("/acme/workspaces/core/sessions/42")
      )

    assert html =~ "sidebar-org-nav"
    assert html =~ "Deploy review"
    assert html =~ "/acme/workspaces/core/sessions/42/reviews"
    assert html =~ "/acme/workspaces/core/sessions/42/deploy-review"
    refute html =~ "Service accounts"
    refute html =~ "Tool policy"
    refute html =~ "Repositories"
  end

  test "session overview is active on the session page" do
    html =
      render_component(
        &OrganizationLayouts.organization_sidebar/1,
        nav_assigns("/acme/workspaces/core/sessions/42")
      )

    assert anchor_for(html, "/acme/workspaces/core/sessions/42") =~ "aria-current=\"page\""
    refute anchor_for(html, "/acme/workspaces/core/sessions/42/reviews") =~ "aria-current"
  end

  test "reviews stays active on a review detail page" do
    html =
      render_component(
        &OrganizationLayouts.organization_sidebar/1,
        nav_assigns("/acme/workspaces/core/sessions/42/reviews/7")
      )

    assert anchor_for(html, "/acme/workspaces/core/sessions/42/reviews") =~
             "aria-current=\"page\""

    refute anchor_for(html, "/acme/workspaces/core/sessions/42") =~ "aria-current"
  end

  test "workspace pages still render workspace nav when no session is set" do
    assigns = nav_assigns("/acme/workspaces/core") |> Map.put(:nav_session, nil)

    html = render_component(&OrganizationLayouts.organization_sidebar/1, assigns)

    assert html =~ "Service accounts"
    refute html =~ "Deploy review"
  end

  test "session crumb renders a switcher listing sibling sessions" do
    siblings = [%{id: 42, title: "Session A"}, %{id: 43, title: "Session B"}]

    html =
      render_component(
        &OrganizationLayouts.breadcrumbs_header/1,
        header_assigns(
          "/acme/workspaces/core/sessions/42/reviews",
          session_crumbs(42, "Session A", "Reviews"),
          siblings
        )
      )

    assert html =~ "breadcrumb-session-switcher-button"
    assert html =~ "Session B"
    # Switching keeps the subpage.
    assert html =~ "/acme/workspaces/core/sessions/43/reviews"
    # Current session is marked active.
    assert html =~ "Session A"
  end

  test "session switcher renders on the session overview page" do
    siblings = [%{id: 42, title: "Session A"}, %{id: 43, title: "Session B"}]

    html =
      render_component(
        &OrganizationLayouts.breadcrumbs_header/1,
        header_assigns(
          "/acme/workspaces/core/sessions/42",
          session_crumbs(42, "Session A", nil),
          siblings
        )
      )

    assert html =~ "breadcrumb-session-switcher-button"
    assert html =~ "/acme/workspaces/core/sessions/43"
  end

  test "no session switcher when there is a single session" do
    html =
      render_component(
        &OrganizationLayouts.breadcrumbs_header/1,
        header_assigns(
          "/acme/workspaces/core/sessions/42/reviews",
          session_crumbs(42, "Session A", "Reviews"),
          [%{id: 42, title: "Session A"}]
        )
      )

    refute html =~ "breadcrumb-session-switcher-button"
  end

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end
end
