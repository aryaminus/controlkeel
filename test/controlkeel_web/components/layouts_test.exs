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
    assert html =~ "aria-label=\"Toggle Observability menu\""
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

  test "sidebar links carry expected focus-visible styles" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    assert html =~ "focus-visible:ring-offset-2"
    assert html =~ "focus-visible:ring-offset-background"
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

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end
end
