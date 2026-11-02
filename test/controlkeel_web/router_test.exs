defmodule ControlKeelWeb.RouterTest do
  use ExUnit.Case, async: true

  alias ControlKeelWeb.ApiController
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

  defp assert_route(path, controller, action) do
    assert %{plug: ^controller, plug_opts: ^action} =
             Phoenix.Router.route_info(Router, "GET", path, "localhost")
  end
end
