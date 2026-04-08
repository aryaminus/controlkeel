defmodule ControlKeelWeb.ShipLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Mission

  test "/ship renders stewardship evidence, benchmark evidence, and recent session rows", %{
    conn: conn
  } do
    session = session_fixture(%{title: "Ship session"})
    task = task_fixture(%{session: session, status: "done"})

    finding_fixture(%{session: session, status: "blocked", title: "Blocked finding"})

    {:ok, _proof} = Mission.generate_proof_bundle(task.id)

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

    assert html =~ "Track governed momentum and delivery evidence"
    assert html =~ "Proof and deploy-readiness"
    assert html =~ "Funnel speed"
    assert html =~ "Governance effectiveness"
    assert html =~ "Benchmark evidence"
    assert html =~ "Autonomy and outcomes"
    assert html =~ "Recommended focus"
    assert html =~ "Proof-backed done tasks"
    assert html =~ "Task completion by agent"
    assert html =~ "Proof console loop"
    assert html =~ "Ship session"
    assert html =~ "First finding recorded"
    assert html =~ "1 blocked"
  end
end
