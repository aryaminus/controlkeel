defmodule ControlKeelWeb.PageControllerTest do
  use ControlKeelWeb.ConnCase

  test "GET / renders the controlkeel landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Turn agent-generated work into production-ready delivery"
    assert body =~ "agent-generated work into secure, scoped, validated"
    assert body =~ "ControlKeel turns agent output into production engineering"
    assert body =~ "production-ready delivery"
    assert body =~ "Start a mission"
    assert body =~ "What it is not"
    assert body =~ "Proof console loop"
    assert body =~ "Governed delivery lifecycle"
    assert body =~ "Occupation-first onboarding"
    assert body =~ "Governed autonomy"
    assert body =~ "Open ship dashboard"
    assert body =~ "Open benchmarks"
    assert body =~ "View benchmark matrix"
    assert body =~ "View ship metrics"
    assert body =~ "Open getting-started guide"
    assert body =~ "Open skills studio"
  end

  test "GET /getting-started renders the install guide", %{conn: conn} do
    conn = get(conn, ~p"/getting-started")
    body = html_response(conn, 200)

    assert body =~ "Go from install to first finding in five minutes"
    assert body =~ "agent-generated work into secure, scoped, validated"
    assert body =~ "ControlKeel turns agent output into production engineering"
    assert body =~ "controlkeel attach opencode"
    assert body =~ "controlkeel bootstrap"
    assert body =~ "controlkeel attach codex-cli"
    assert body =~ "Occupation-first onboarding"
    assert body =~ "Operating modes"
    assert body =~ "Governed delivery lifecycle"
  end
end
