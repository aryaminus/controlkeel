defmodule ControlKeelWeb.ObservabilityTimelineLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "timeline links task-completion events to their proof bundle", %{conn: conn} do
    session = session_fixture(%{risk_tier: "low", title: "Timeline proof session"})
    task = task_fixture(%{session: session, status: "in_progress", title: "Shippable task"})

    assert {:ok, _completed} = Mission.complete_task(task.id)
    proof = Mission.latest_proof_bundle_for_task(task.id)
    assert proof

    {:ok, _view, html} = live(conn, ~p"/observability/sessions/#{session.id}/timeline")

    assert html =~ "Timeline"
    assert html =~ "task.completed"
    assert html =~ "Proof ##{proof.id}"
    assert html =~ ~s(href="/proofs/#{proof.id}")
  end

  test "timeline renders events without proof ids without a proof link", %{conn: conn} do
    session = session_fixture()

    {:ok, _view, html} = live(conn, ~p"/observability/sessions/#{session.id}/timeline")

    assert html =~ "Timeline"
    refute html =~ "Proof #"
  end
end
