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

  test "session_sidebar renders back link to sessions, title, id, risk tier, Overview, Tasks, and Deploy review" do
    html =
      render_component(&Layouts.session_sidebar/1,
        current_path: "/sessions/42",
        session_id: "42",
        session_title: "Refactor auth engine",
        session_risk: "high"
      )

    assert html =~ ~s(href="/sessions")
    assert html =~ "Sessions"
    assert html =~ "Refactor auth engine"
    assert html =~ "#42"
    assert html =~ "high"
    assert anchor_for(html, "/sessions/42") =~ "aria-current=\"page\""
    assert html =~ "Overview"
    assert anchor_for(html, "/sessions/42/tasks") != ""
    refute anchor_for(html, "/sessions/42/tasks") =~ "aria-current=\"page\""
    assert html =~ "Tasks"
    assert anchor_for(html, "/sessions/42/deploy-review") != ""
    refute anchor_for(html, "/sessions/42/deploy-review") =~ "aria-current=\"page\""
    assert html =~ "Deploy review"
    refute html =~ ~s(href="/findings)
    refute html =~ ~s(href="/proofs)
    refute html =~ ~s(href="/sessions/42/reviews")
  end

  test "session_sidebar highlights Tasks when on /sessions/:id/tasks" do
    html =
      render_component(&Layouts.session_sidebar/1,
        current_path: "/sessions/42/tasks",
        session_id: "42",
        session_title: "Refactor auth engine",
        session_risk: "high"
      )

    assert anchor_for(html, "/sessions/42/tasks") =~ "aria-current=\"page\""
    refute anchor_for(html, "/sessions/42") =~ "aria-current=\"page\""
  end

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end
end
