defmodule ControlKeelWeb.ProofBrowserLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "proof browser filters and paginates proof bundles", %{conn: conn} do
    session = session_fixture(%{title: "Proof mission"})
    task = task_fixture(%{session: session, status: "done", title: "Ship proof"})
    proof = proof_bundle_fixture(%{task: task})

    {:ok, view, html} = live(conn, ~p"/proofs?#{%{q: "Ship", session_id: session.id}}")

    assert html =~ "Proof browser"
    assert html =~ "Ship proof"
    assert has_element?(view, "a[href=\"/proofs/#{proof.id}\"]", "View proof")
  end

  test "proof browser detail renders immutable proof content and related memory", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done", title: "Detailed proof"})
    proof = proof_bundle_fixture(%{task: task})
    _memory = memory_record_fixture(%{session: session, task_id: task.id, title: "Proof memory"})

    {:ok, _view, html} = live(conn, ~p"/proofs/#{proof.id}")

    assert html =~ "Immutable proof snapshot"
    assert html =~ "Detailed proof"
    assert html =~ "Rollback instructions"
    assert html =~ "Related memory"
  end
end
