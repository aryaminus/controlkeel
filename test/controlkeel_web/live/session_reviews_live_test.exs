defmodule ControlKeelWeb.SessionReviewsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Repo

  test "session reviews redirects when the session disappears on refresh", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    Repo.delete!(session)
    send(view.pid, :refresh)

    assert_redirect(view, "/")
  end

  test "session reviews lists the reviews for the session", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    review = review_fixture(%{session: session, submitted_by: "opencode"})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "Review queue"
    assert html =~ review.title
    assert html =~ org_session_path(org, ws, session, "/reviews/#{review.id}")
    assert html =~ "plan"
    assert html =~ "pending"
    assert html =~ "opencode"
    assert html =~ "1 total"
    assert html =~ "1 pending"
  end

  test "session reviews render the session sidebar with Reviews active", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "sidebar-org-nav"
    assert html =~ "Deploy review"
    refute html =~ "Service accounts"

    reviews_href = org_session_path(org, ws, session, "/reviews")
    assert html =~ ~s(href="#{reviews_href}")
  end

  test "session reviews shows the task that a review is scoped to", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task = task_fixture(%{session: session, title: "Risky plan task"})
    review_fixture(%{session: session, task: task})

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "Risky plan task"
  end

  test "session reviews shows an empty state", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "Review queue"
    assert html =~ "No reviews yet."
    assert html =~ "0 total"
    assert html =~ "0 pending"
  end

  test "session reviews updates pending counts after a review is decided", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    review = review_fixture(%{session: session})

    {:ok, view, html} = live(conn, org_session_path(org, ws, session, "/reviews"))
    assert html =~ "1 pending"
    assert html =~ "pending"

    assert {:ok, _updated} = Mission.respond_review(review, %{"decision" => "approved"})
    send(view.pid, :refresh)

    refreshed_html = render(view)

    assert refreshed_html =~ "0 pending"
    assert refreshed_html =~ "1 resolved"
    assert refreshed_html =~ "approved"
  end

  test "session reviews redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/acme/workspaces/core/sessions/999999/reviews")
  end

  test "session reviews redirects when the workspace slug disagrees", %{conn: conn} do
    {org, _ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/reviews")
  end

  test "session breadcrumb offers a switcher with sibling sessions", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    other = session_fixture(%{workspace: ws, title: "Second session"})

    {:ok, _view, html} =
      live(conn, org_session_path(org, ws, session, "/reviews"))

    assert html =~ "breadcrumb-session-switcher-button"
    assert html =~ "Second session"

    assert html =~
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{other.id}/reviews"
  end
end
