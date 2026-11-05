defmodule ControlKeelWeb.RouterTest do
  use ExUnit.Case, async: true

  alias ControlKeelWeb.ApiController
  alias ControlKeelWeb.BenchmarksLive
  alias ControlKeelWeb.OrganizationDetailLive
  alias ControlKeelWeb.ObservabilityController
  alias ControlKeelWeb.Router

  test "organization catch-all does not shadow API or export routes" do
    assert_route("/api/v1/sessions", ApiController, :list_sessions)

    assert_route(
      "/observability/sessions/123/export.json",
      ObservabilityController,
      :export_session
    )

    assert_route(
      "/acme/workspaces/default/sessions/123/observability/export.json",
      ObservabilityController,
      :export_session
    )
  end

  test "retired /dashboard falls through to the org overview catch-all" do
    # DashboardLive is deleted and "dashboard" is a reserved org slug, so the
    # request must match "/:org_slug" and render the invalid-org panel — never
    # a dead route and never an org-owned page (docs/retire-dashboard-issue.md).
    info = Phoenix.Router.route_info(Router, "GET", "/dashboard", "localhost")

    assert %{
             plug: Phoenix.LiveView.Plug,
             route: "/:org_slug",
             plug_opts: :index
           } = info

    assert {OrganizationDetailLive, :index, _opts, _live_session} =
             info.phoenix_live_view
  end

  test "benchmarks index lives in the workspace scope" do
    info =
      Phoenix.Router.route_info(Router, "GET", "/acme/workspaces/default/benchmarks", "localhost")

    assert %{plug: Phoenix.LiveView.Plug, plug_opts: :index} = info

    assert {BenchmarksLive, :index, _opts, %{name: :organization}} =
             info.phoenix_live_view
  end

  test "benchmarks run detail lives in the workspace scope" do
    info =
      Phoenix.Router.route_info(
        Router,
        "GET",
        "/acme/workspaces/default/benchmarks/runs/99",
        "localhost"
      )

    assert %{plug: Phoenix.LiveView.Plug, plug_opts: :show} = info

    assert {BenchmarksLive, :show, _opts, %{name: :organization}} =
             info.phoenix_live_view
  end

  test "retired /benchmarks/runs/:id falls through to the invalid-org panel" do
    # BenchmarksLive run detail moved to the workspace scope and no redirect
    # was kept (owner decision): "/benchmarks/runs/..." matches the
    # "/:org_slug/*rest" wide catch under the reserved "benchmarks" org slug
    # and renders the invalid-org panel — never a dead route and never an
    # org-owned page.
    info = Phoenix.Router.route_info(Router, "GET", "/benchmarks/runs/99", "localhost")

    assert %{
             plug: Phoenix.LiveView.Plug,
             route: "/:org_slug/*rest",
             plug_opts: :not_found,
             path_params: %{"org_slug" => "benchmarks", "rest" => ["runs", "99"]}
           } = info

    assert {ControlKeelWeb.OrgCatchAllLive, :not_found, _opts, %{name: :organization}} =
             info.phoenix_live_view
  end

  test "retired /benchmarks falls through to the org overview catch-all" do
    # BenchmarksLive index moved to the workspace scope and "benchmarks" is a
    # reserved org slug, so the request must match "/:org_slug" and render the
    # invalid-org panel — never a dead route and never an org-owned page
    # (docs/benchmark-issue.md).
    info = Phoenix.Router.route_info(Router, "GET", "/benchmarks", "localhost")

    assert %{
             plug: Phoenix.LiveView.Plug,
             route: "/:org_slug",
             plug_opts: :index
           } = info

    assert {OrganizationDetailLive, :index, _opts, _live_session} =
             info.phoenix_live_view
  end

  defp assert_route(path, controller, action) do
    assert %{plug: ^controller, plug_opts: ^action} =
             Phoenix.Router.route_info(Router, "GET", path, "localhost")
  end
end
