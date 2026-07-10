defmodule ControlKeelWeb.PageControllerTest do
  use ControlKeelWeb.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Turn team knowledge into"
    assert body =~ "Install ControlKeel"
    assert body =~ "Policy gates for agents"
    assert body =~ "Evidence, not vibes"
    assert body =~ "Host-agnostic control"
    assert body =~ "How it works"
    assert body =~ "Ready to govern"
  end

  test "GET /getting-started renders the guide with install channels", %{conn: conn} do
    conn = get(conn, ~p"/getting-started")
    body = html_response(conn, 200)

    assert body =~ "Install to first finding in five minutes"
    assert body =~ "controlkeel attach opencode"
    assert body =~ "controlkeel setup"
    assert body =~ "controlkeel attach doctor"
    assert body =~ "controlkeel provider doctor"
    assert body =~ "controlkeel status"
    assert body =~ "controlkeel findings"
    assert body =~ "Local stdio MCP exposes the full local tool set"
    assert body =~ "Quick start"
    assert body =~ "Available where"
    assert body =~ "How it governs"
    assert body =~ "Other supported agents"
    assert body =~ "Project rescue"
  end
end
