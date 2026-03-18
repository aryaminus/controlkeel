defmodule ControlKeelWeb.ShipLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics

  test "/ship renders funnel metrics and recent session rows", %{conn: conn} do
    session = session_fixture(%{title: "Ship session"})
    finding_fixture(%{session: session, status: "blocked", title: "Blocked finding"})

    for event <- ~w(project_initialized agent_attached mission_created first_finding_recorded) do
      assert {:ok, _} =
               Analytics.record(%{
                 event: event,
                 source: "test",
                 session_id: session.id,
                 workspace_id: session.workspace_id
               })
    end

    {:ok, _view, html} = live(conn, ~p"/ship")

    assert html =~ "Track install-to-first-finding momentum"
    assert html =~ "Ship session"
    assert html =~ "First finding recorded"
    assert html =~ "1 blocked"
  end
end
