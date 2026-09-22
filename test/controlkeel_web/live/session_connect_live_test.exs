defmodule ControlKeelWeb.SessionConnectLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "session connect shows proxy endpoints with copy actions", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/connect"))

    assert html =~ "Connect"
    assert html =~ "Proxy endpoints"
    assert html =~ "copy_endpoint"
    assert html =~ "OpenAI"
    assert html =~ "Responses"
    assert html =~ "Anthropic"
    assert html =~ "Messages"
    assert html =~ "Gemini"
    assert html =~ "Chat"
    assert html =~ "/proxy/openai/"
    assert html =~ "/v1/responses"
    assert html =~ "/v1/chat/completions"
    assert html =~ "/v1/completions"
    assert html =~ "/v1/embeddings"
    assert html =~ "/v1/models"
    assert html =~ "/v1/realtime"
    assert html =~ "/v1/messages"
    refute html =~ "Attach your agent"
  end

  test "session connect copies the endpoint URL to the clipboard", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/connect"))

    render_click(element(view, "button[phx-click=\"copy_endpoint\"]"))

    assert_push_event(view, "copy-to-clipboard", %{text: text})
    assert text =~ "/proxy/openai/"

    assert render(view) =~ "Endpoint copied to the clipboard."
  end

  test "session connect renders the session sidebar with Connect active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/connect"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Connect"
    refute html =~ "Service accounts"

    connect_href = org_session_path(org, ws, session, "/connect")
    assert html =~ ~s(href="#{connect_href}")
  end

  test "session connect refreshes without losing the endpoints", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/connect"))
    send(view.pid, :refresh)

    assert render(view) =~ "/proxy/openai/"
  end

  test "session connect redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/connect")
  end

  test "session connect redirects when the workspace slug disagrees", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/connect")
  end

  test "session connect redirects when the org slug disagrees", %{conn: conn} do
    {_org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/connect")
  end
end
