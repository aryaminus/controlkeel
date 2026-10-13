defmodule ControlKeelWeb.SessionProofsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "session nav links to the session-scoped proofs route", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session))

    assert html =~ "Proofs"
    assert html =~ ~s(href="#{org_session_path(org, ws, session, "/proofs")}")
  end

  test "session proofs index lists only this session's bundles", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    other_session = session_fixture(%{workspace: ws, title: "Other mission"})
    task = task_fixture(%{session: session, status: "done", title: "Ship proof"})
    other_task = task_fixture(%{session: other_session, status: "done", title: "Harbor audit"})
    proof = proof_bundle_fixture(%{task: task})
    _other_proof = proof_bundle_fixture(%{task: other_task})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/proofs"))

    assert html =~ "Ship proof"
    assert html =~ ~s(href="#{org_session_path(org, ws, session, "/proofs/#{proof.id}")}")
    refute html =~ "Harbor audit"
  end

  test "session proofs index supports the q filter via query params", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "done", title: "Ship proof"})
    proof_bundle_fixture(%{task: task})

    base = org_session_path(org, ws, session, "/proofs")

    {:ok, view, html} = live(conn, base <> "?q=ship")
    assert html =~ "Ship proof"
    assert has_element?(view, "a", "Ship proof")

    {:ok, _view, html} = live(conn, base <> "?q=nomatch")
    assert html =~ "No proof bundles found."
  end

  test "pagination links preserve filters and change only the page", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    base = org_session_path(org, ws, session, "/proofs")

    for n <- 1..21 do
      task = task_fixture(%{session: session, status: "done", title: "Paged proof #{n}"})
      proof_bundle_fixture(%{task: task})
    end

    {:ok, view, html} = live(conn, base <> "?q=paged")
    assert html =~ "Page 1 of 2"

    next_href = "#{base}?page=2&q=paged"
    assert has_element?(view, "a[href=\"" <> next_href <> "\"]", "Next")

    {:ok, view, html} = live(conn, base <> "?q=paged&page=2")
    assert html =~ "Page 2 of 2"

    prev_href = "#{base}?page=1&q=paged"
    assert has_element?(view, "a[href=\"" <> prev_href <> "\"]", "Previous")

    # The session stays in the path — never leaked into the query string.
    refute html =~ "session_id"
  end

  test "proof detail renders immutable proof content and related memory", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, status: "done", title: "Detailed proof"})
    proof = proof_bundle_fixture(%{task: task})
    _memory = memory_record_fixture(%{session: session, task_id: task.id, title: "Proof memory"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/proofs/#{proof.id}"))

    assert html =~ "Detailed proof"
    assert html =~ "Rollback instructions"
    assert html =~ "Related memory"
    assert html =~ "Proof memory"
  end

  test "proof detail enforces the session boundary", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    other_session = session_fixture(%{workspace: ws, title: "Other mission"})
    other_task = task_fixture(%{session: other_session, status: "done", title: "Harbor audit"})
    other_proof = proof_bundle_fixture(%{task: other_task})

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, session, "/proofs/#{other_proof.id}"))

    assert html =~ "Proof not found"
    assert html =~ "No proof bundle exists with this identifier."
    refute html =~ "Harbor audit"
  end

  test "malformed proof id shows not-found inline", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/proofs/not-an-id"))

    assert html =~ "Proof not found"
    assert html =~ "No proof bundle exists with this identifier."
  end

  test "scope-mismatched org or workspace slugs redirect with not-found", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, "/#{org.slug}/workspaces/not-the-workspace/sessions/#{session.id}/proofs")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, "/not-the-org/workspaces/#{ws.slug}/sessions/#{session.id}/proofs")
  end

  describe "legacy /proofs redirects" do
    test "GET /proofs?session_id= redirects to the session-scoped route preserving params", %{
      conn: conn
    } do
      {org, ws, session} = org_bound_session_fixture()

      conn = get(conn, "/proofs?session_id=#{session.id}&q=Ship")

      assert redirected_to(conn) ==
               "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/proofs?q=Ship"
    end

    test "GET /proofs/:id redirects to the session-scoped proof detail", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()
      task = task_fixture(%{session: session, status: "done", title: "Redirected proof"})
      proof = proof_bundle_fixture(%{task: task})

      conn = get(conn, "/proofs/#{proof.id}")

      assert redirected_to(conn) ==
               "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/proofs/#{proof.id}"
    end

    test "GET /proofs without session_id falls back to the most recent session", %{conn: conn} do
      {org, ws, session} = org_bound_session_fixture()

      conn = get(conn, "/proofs")

      assert redirected_to(conn) == org_session_path(org, ws, session, "/proofs")
    end

    test "GET /proofs/:id with an unknown id returns 404", %{conn: conn} do
      conn = get(conn, "/proofs/999999")
      assert conn.status == 404
    end

    test "GET /proofs?session_id= with an unknown id returns 404", %{conn: conn} do
      conn = get(conn, "/proofs?session_id=999999")
      assert conn.status == 404
    end
  end
end
