defmodule ControlKeelWeb.ProofBrowserLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Repo
  alias ControlKeel.Accounts.Org

  test "proof browser filters and paginates proof bundles", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture(%{title: "Proof mission"})

    task = task_fixture(%{session: session, status: "done", title: "Ship proof"})
    proof = proof_bundle_fixture(%{task: task})

    {:ok, view, html} = live(conn, ~p"/proofs?#{%{q: "Ship", session_id: session.id}}")

    assert html =~ "Proof browser"
    assert html =~ "Ship proof"

    assert has_element?(
             view,
             "a[href=\"/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/proofs/#{proof.id}\"]",
             "View"
           )
  end

  test "proof detail renders under the session scope with task page title", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "done", title: "Detailed proof"})
    proof = proof_bundle_fixture(%{task: task})
    _memory = memory_record_fixture(%{session: session, task_id: task.id, title: "Proof memory"})

    path = "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/proofs/#{proof.id}"
    {:ok, _view, html} = live(conn, path)

    assert html =~ "Detailed proof"
    assert html =~ "Rollback instructions"
    assert html =~ "Related memory"
  end

  test "session proof detail enforces session boundary and rejects cross-session ids", %{
    conn: conn
  } do
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

    path_a = "/#{org_a.slug}/workspaces/#{workspace_a.slug}/sessions/#{session_a.id}"
    {:ok, _view, html} = live(conn, "#{path_a}/proofs/#{proof_a.id}")
    assert html =~ "Org A Task"
    refute html =~ "Org B Task"

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "#{path_a}/proofs/#{proof_b.id}")
  end

  test "malformed proof id under session scope is rejected generically", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(
               conn,
               "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/proofs/not-an-id"
             )
  end
end
