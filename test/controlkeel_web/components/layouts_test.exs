defmodule ControlKeelWeb.LayoutsTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.Layouts

  test "sidebar links carry expected keyboard focus styles" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    assert html =~ "focus-visible:ring-offset-2"
    assert html =~ "focus-visible:ring-offset-background"
  end

  test "top-level links carry aria-current on their own active page" do
    html = render_component(&Layouts.sidebar/1, current_path: "/benchmarks")

    assert anchor_for(html, "/benchmarks") =~ "aria-current=\"page\""
  end

  test "global organization and session index links are absent" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    refute html =~ ~s(href="/organizations")
    refute html =~ ~s(href="/sessions")
    refute html =~ ">Organizations<"
    refute html =~ ">Sessions<"
  end

  defp anchor_for(html, href) do
    case Regex.run(~r|<a\b[^>]*href="#{href}"[^>]*>.*?</a>|s, html) do
      nil -> ""
      [match] -> match
    end
  end
end
