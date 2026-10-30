defmodule ControlKeelWeb.RouterTest do
  use ExUnit.Case, async: true

  alias ControlKeelWeb.ApiController
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

    assert %{plug: Phoenix.LiveView.Plug} = info

    assert {OrganizationDetailLive, :index, _opts, _live_session} =
             info.metadata.phoenix_live_view
  end

  defp assert_route(path, controller, action) do
    assert %{plug: ^controller, plug_opts: ^action} =
             Phoenix.Router.route_info(Router, "GET", path, "localhost")
  end
end
