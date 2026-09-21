defmodule ControlKeelWeb.ProofBrowserLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Repo
  alias ControlKeel.Accounts.Org

  test "proof browser filters and paginates proof bundles", %{conn: conn} do
    session = session_fixture(%{title: "Proof mission"})
    task = task_fixture(%{session: session, status: "done", title: "Ship proof"})
    proof = proof_bundle_fixture(%{task: task})

    {:ok, view, html} = live(conn, ~p"/proofs?#{%{q: "Ship", session_id: session.id}}")

    assert html =~ "Proof browser"
    assert html =~ "Ship proof"
    assert has_element?(view, "a[href=\"/proofs/#{proof.id}\"]", "View")
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

  test "detail view enforces org workspace boundary", %{conn: conn} do
    {:ok, org_a} =
      %Org{}
      |> Org.changeset(%{name: "Proof Org A", slug: "proof-org-a", status: "active"})
      |> Repo.insert()

    {:ok, org_b} =
      %Org{}
      |> Org.changeset(%{name: "Proof Org B", slug: "proof-org-b", status: "active"})
      |> Repo.insert()

    workspace_a = workspace_fixture(%{name: "Org A Workspace", org_id: org_a.id})
    workspace_b = workspace_fixture(%{name: "Org B Workspace", org_id: org_b.id})

    session_a = session_fixture(%{workspace: workspace_a, title: "Org A Session"})
    session_b = session_fixture(%{workspace: workspace_b, title: "Org B Session"})

    task_a = task_fixture(%{session: session_a, status: "done", title: "Org A Task"})
    task_b = task_fixture(%{session: session_b, status: "done", title: "Org B Task"})

    proof_a = proof_bundle_fixture(%{task: task_a})
    proof_b = proof_bundle_fixture(%{task: task_b})

    conn_a = Plug.Test.init_test_session(conn, %{"current_org_id" => org_a.id})

    {:ok, _view, html} = live(conn_a, ~p"/proofs/#{proof_a.id}")
    assert html =~ "Immutable proof snapshot"
    assert html =~ "Org A Task"
    refute html =~ "Org B Task"

    {:ok, _view, html_unauth} = live(conn_a, ~p"/proofs/#{proof_b.id}")
    assert html_unauth =~ "Proof not found"
    assert html_unauth =~ "No proof bundle exists with this identifier."
    refute html_unauth =~ "Immutable proof snapshot"
    refute html_unauth =~ "Org B Task"
  end

  test "malformed proof id shows not-found inline", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/proofs/not-an-id")
    assert html =~ "Proof not found"
    assert html =~ "No proof bundle exists with this identifier."
  end
end
