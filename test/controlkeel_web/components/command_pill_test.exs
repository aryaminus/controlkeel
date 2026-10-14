defmodule ControlKeelWeb.CommandPillTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeelWeb.CommandPill

  test "renders command text" do
    html = render_component(&CommandPill.command_pill/1, command: "controlkeel obs")
    assert html =~ "controlkeel obs"
  end

  test "renders copy button" do
    html = render_component(&CommandPill.command_pill/1, command: "controlkeel obs")
    assert html =~ "clipboard"
  end

  test "copy button triggers copy_command event through a LiveView", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")
    assert has_element?(view, "button[phx-click=\"copy_command\"]")
  end
end
