defmodule ControlKeelWeb.PageControllerTest do
  use ControlKeelWeb.ConnCase

  test "GET / renders the controlkeel landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Turn vibe coding into production engineering"
    assert body =~ "Start a mission"
    assert body =~ "Open ship dashboard"
    assert body =~ "View ship metrics"
    assert body =~ "Open getting-started guide"
  end

  test "GET /getting-started renders the install guide", %{conn: conn} do
    conn = get(conn, ~p"/getting-started")
    body = html_response(conn, 200)

    assert body =~ "Go from install to first finding in five minutes"
    assert body =~ "controlkeel init"
  end
end
