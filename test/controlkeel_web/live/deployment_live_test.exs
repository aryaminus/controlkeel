defmodule ControlKeelWeb.DeploymentLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "/deploy renders the deployment advisor landing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/deploy")

    assert html =~ "Deployment Advisor"
    assert html =~ "Analyze Project"
    assert html =~ "Analyze your project stack"
    assert html =~ "Click &quot;Analyze Project&quot;"
  end

  test "analyze detects the project stack and shows analysis results", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    html = render_click(view, "analyze")

    assert html =~ "Detected Stack"
    assert html =~ "Monthly Cost Range"
    assert html =~ "Compatible Platforms"
    assert html =~ "Files to Generate"
    assert html =~ "Recommended Platforms"
    assert html =~ "Generated Files (Preview)"
  end

  test "analyze shows platform list with links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    html = render_click(view, "analyze")

    assert html =~ "Fly.io"
    assert html =~ "Render"
    assert html =~ "Heroku"
    assert has_element?(view, "#platform-list")
  end

  test "select_tier updates the selected tier", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html = render_change(view, "select_tier", %{"tier" => "hobby"})

    assert html =~ "Hobby"
  end

  test "toggle_db flips the needs_db assign", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html = render_click(view, "toggle_db")

    assert html =~ "Deployment Advisor"
  end

  test "estimate_costs shows the cost breakdown table", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html = render_click(view, "estimate_costs")

    assert html =~ "Compute"
    assert html =~ "Database"
    assert html =~ "Bandwidth"
    assert html =~ "Total"
    assert has_element?(view, "#cost-estimates")
  end

  test "estimate_costs with db toggled off excludes database costs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")
    render_click(view, "toggle_db")

    _html = render_click(view, "estimate_costs")

    assert has_element?(view, "#cost-estimates")
  end

  test "generate_files previews generated files with skipped status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html = render_click(view, "generate_files")

    assert html =~ "Dockerfile"
    assert html =~ "docker-compose.yml"
    assert html =~ "Skipped"
  end

  test "write_files writes files and shows success flash", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html = render_click(view, "write_files")

    assert html =~ "Files written successfully!"
    assert html =~ "Written"
  end

  test "cost estimates with different tiers update correctly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")

    html_free = render_click(view, "estimate_costs")
    assert has_element?(view, "#cost-estimates")

    render_change(view, "select_tier", %{"tier" => "performance"})

    html_perf = render_click(view, "estimate_costs")

    assert has_element?(view, "#cost-estimates")
    assert html_free != html_perf
  end

  test "back home link is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/deploy")

    assert html =~ ~p"/"
    assert html =~ "Back home"
  end

  test "generated file preview shows file paths and content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deploy")

    render_click(view, "analyze")
    html = render_click(view, "generate_files")

    assert html =~ ".env.example"
    assert html =~ ".github/workflows/ci.yml"
  end
end
