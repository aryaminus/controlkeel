defmodule ControlKeelWeb.LayoutsTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.Layouts

  # The global nav is empty since Benchmarks moved to the workspace scope, so
  # the remaining focusable sidebar control is the user menu (renders in cloud
  # mode with a signed-in user).
  test "sidebar controls carry expected keyboard focus styles" do
    html =
      render_component(&Layouts.sidebar/1, %{
        current_path: "/dashboard",
        mode: :cloud,
        current_user: %{id: 1, name: "Test User", email: "test@example.com"}
      })

    assert html =~ "focus-visible:ring-offset-2"
    assert html =~ "focus-visible:ring-offset-background"
  end

  # The global sidebar is intentionally empty since Benchmarks moved to the
  # workspace scope (/:org_slug/workspaces/:ws_slug/benchmarks).
  test "global index links are absent" do
    html = render_component(&Layouts.sidebar/1, current_path: "/dashboard")

    refute html =~ ~s(href="/organizations")
    refute html =~ ~s(href="/sessions")
    refute html =~ ~s(href="/benchmarks")
    refute html =~ ">Organizations<"
    refute html =~ ">Sessions<"
    refute html =~ ">Benchmarks<"
  end
end
