defmodule ControlKeelWeb.ObservabilityImportsLiveTest do
  # The standalone Imports page is folded into Overview (`#imports` section,
  # next to the trace-export card). These tests cover the merged content on
  # the overview plus the `/imports` redirects (workspace + legacy global).
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry

  defp persist_import_fixture(session, workspace_id) do
    {:ok, envelope} =
      ObservabilityTelemetry.export_session(session.id,
        exported_at: ~U[2026-04-29 04:00:00Z]
      )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-imports-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    {:ok, _result} =
      ObservabilityTelemetry.import_persist(path,
        workspace_id: workspace_id,
        session_id: session.id,
        imported_at: ~U[2026-04-29 05:00:00Z]
      )

    :ok
  end

  test "overview renders folded imports section when empty", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

    assert html =~ "Imported snapshots"
    assert html =~ "controlkeel obs imports"
    assert has_element?(view, "#imports")
    assert has_element?(view, "#observability-imports-count")
    assert html =~ "No persisted observability imports yet."
  end

  test "overview renders persisted imports in the folded section", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    persist_import_fixture(session, ws.id)

    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

    assert html =~ "1 persisted"
    assert html =~ "Recent imports"
    assert html =~ "verified"
  end

  test "workspace imports path redirects to the overview imports section", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/imports")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/observability#imports"
  end

  test "workspace imports redirect preserves the query string", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/imports?limit=10")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/observability#imports?limit=10"
  end

  test "legacy global imports path redirects to the workspace overview section", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/observability/imports")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/observability#imports"
  end

  test "unknown workspace slug redirects instead of crashing", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/observability")
  end
end
