defmodule ControlKeelWeb.ObservabilityLoopLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ControlKeel.Memory.Record
  alias ControlKeel.Repo

  test "loop page renders read-only learning loop status", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Loop page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.loop_page"
    })

    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/loop")

    assert html =~ "Learning loop"
    assert html =~ "Safety boundary"
    assert html =~ "Automatic benchmark execution: false"
    assert html =~ "Automatic promotion: false"
    assert html =~ "controlkeel obs loop"
  end

  test "loop page renders loop diagnostics section with no detected runs", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/loop")

    assert html =~ "Loop diagnostics"
    assert html =~ "Repeated tool events"
    assert html =~ "Repeated invocations"
    assert html =~ "No repeated identical tool-event runs detected."
    assert html =~ "No repeated identical invocation runs detected."
  end

  test "capture performance snapshot persists a memory record and renders results", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/loop")

    assert html =~ "No performance snapshot captured yet."

    view |> element("#observability-perf-capture") |> render_click()

    rendered = render(view)

    assert rendered =~ "Performance snapshot"
    assert rendered =~ "Total wall time"
    assert rendered =~ "Ecto queries"
    assert rendered =~ "Payload"

    persisted =
      from(r in Record,
        where: r.source_type == "observability" and r.session_id == ^session.id,
        order_by: [desc: :id],
        limit: 1
      )
      |> Repo.one()

    assert persisted
    assert persisted.title == "Performance Snapshot"
    assert persisted.workspace_id == session.workspace_id
    assert persisted.metadata["total_wall_ms"] >= 0
  end
end
