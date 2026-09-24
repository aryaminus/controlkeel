defmodule ControlKeelWeb.SessionObservabilityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  defp observability_path(org, ws, session),
    do: "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability"

  test "stacked observability page renders session run details", %{conn: conn} do
    {org, ws, session} =
      org_bound_session_fixture(%{
        budget_cents: 2_000,
        daily_budget_cents: 2_000,
        spent_cents: 300
      })

    task = task_fixture(%{session: session, status: "in_progress", title: "Observe task"})

    finding_fixture(%{
      session: session,
      title: "Observable finding",
      severity: "high",
      status: "open",
      rule_id: "observability.test"
    })

    assert {:ok, _review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "review_type" => "plan",
               "title" => "Observation review",
               "submission_body" => "Review this run"
             })

    {:ok, view, html} = live(conn, observability_path(org, ws, session))

    assert html =~ "Session observability"
    assert has_element?(view, "#observability-run-page")
    refute has_element?(view, "#observability-health-card")
    assert has_element?(view, "#session-observability-timeline")
    assert has_element?(view, "#observability-timeline-summary")
    refute has_element?(view, "#observability-timeline-events")
    assert has_element?(view, "#session-observability-memory")
    refute has_element?(view, "#observability-findings")
    refute has_element?(view, "#observability-gates")
    assert has_element?(view, "#observability-costs")
    assert has_element?(view, "#observability-tools")
    assert has_element?(view, "#observability-recommendations")
    assert has_element?(view, "#observability-telemetry-export")
    refute has_element?(view, "#observability-recent-findings")
    refute has_element?(view, "#observability-timeline")

    assert html =~
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/export.json"

    refute html =~
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/json"
  end

  test "observability page no longer links proofs from overview (moved to dedicated tab)", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    {:ok, view, _html} = live(conn, observability_path(org, ws, session))

    # Overview memory-proof card no longer has Jump/Open links; proofs lives in sidebar nav
    refute has_element?(
             view,
             "#observability-memory-proof a[href=\"#session-observability-memory\"]"
           )

    refute has_element?(view, "#observability-memory-proof a[href*=\"/proofs?session_id=\"]")
    assert has_element?(view, "#observability-memory-proof")
  end

  test "stacked observability page redirects missing sessions", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    # use a non-existent id
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/observability")
  end

  test "observability export route returns local telemetry envelope via new path", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    conn =
      get(
        conn,
        "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/export.json"
      )

    assert %{
             "schema_version" => "controlkeel.observability.v1",
             "session_run" => %{"session" => %{"id" => id}},
             "redaction" => %{"policy" => "summary_only"},
             "integrity" => %{"import_mutation_allowed" => false}
           } = json_response(conn, 200)

    assert id == session.id
  end

  test "observability export route still works via legacy path", %{conn: conn} do
    session = session_fixture()

    conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

    assert %{"session_run" => %{"session" => %{"id" => id}}} = json_response(conn, 200)
    assert id == session.id
  end

  test "observability export route returns not found for missing sessions", %{conn: conn} do
    {org, ws, _} = org_bound_session_fixture()

    conn =
      get(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/observability/export.json")

    assert %{"error" => "session not found"} = json_response(conn, 404)
  end

  test "mission control session nav bridges to the stacked observability page", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}")

    assert html =~ "sidebar-org-nav"
    assert html =~ "Observability"

    assert html =~
             ~s(href="/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability")
  end

  test "observability page no longer renders audit log export (moved to activity)", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    _finding = finding_fixture(%{session: session})

    {:ok, view, _html} = live(conn, observability_path(org, ws, session))

    refute has_element?(view, "#observability-audit-log-export")
    refute has_element?(view, "#observability-audit-export-json")
  end

  test "session activity page shows audit log export controls and latest checksum", %{
    conn: conn
  } do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/activity")

    assert has_element?(view, "#activity-audit-export-json")
    assert has_element?(view, "#activity-audit-export-csv")
    assert has_element?(view, "#activity-audit-export-pdf")

    assert html =~
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/csv"

    refute html =~ "Last export"

    assert {:ok, %{export: export}} = Platform.export_audit_log(session.id, "csv")

    {:ok, _view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/activity")

    assert html =~ "Last export (csv)"
    assert html =~ export.checksum
  end

  test "legacy observability page redirects to org-scoped observability", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    conn = get(conn, ~p"/observability/sessions/#{session.id}")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability"
  end

  test "legacy observability redirects 404 for unknown sessions", %{conn: conn} do
    for path <- [
          "/observability/sessions/999999",
          "/observability/sessions/999999/timeline",
          "/observability/sessions/999999/memory"
        ] do
      conn = get(conn, path)
      assert response(conn, 404) =~ "404"
    end
  end

  test "legacy observability redirects 404 for uncastable ids", %{conn: conn} do
    for path <- [
          "/observability/sessions/abc",
          "/observability/sessions/abc/timeline",
          "/observability/sessions/abc/memory"
        ] do
      conn = get(conn, path)
      assert response(conn, 404) =~ "404"
    end
  end

  test "stacked observability page redirects for scope-mismatched slugs", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/sessions/#{session.id}/observability")

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/sessions/#{session.id}/observability")
  end

  test "stacked observability page redirects for non-numeric ids", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/abc/observability")
  end

  test "audit-log export works via new org-scoped path", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    conn =
      get(
        conn,
        "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability/audit-log/json"
      )

    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    assert get_resp_header(conn, "content-disposition") |> hd() ==
             "attachment; filename=\"audit-log-#{session.id}.json\""

    assert response(conn, 200) =~ "\"audit_log\""
  end

  test "audit-log export still works via legacy path", %{conn: conn} do
    session = session_fixture()

    conn = get(conn, ~p"/observability/sessions/#{session.id}/audit-log/json")

    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    assert response(conn, 200) =~ "\"audit_log\""
  end

  test "audit-log export returns not found for missing sessions via new path", %{conn: conn} do
    {org, ws, _} = org_bound_session_fixture()

    conn =
      get(conn, "/#{org.slug}/workspaces/#{ws.slug}/sessions/999999/observability/audit-log/json")

    assert %{"error" => "session not found"} = json_response(conn, 404)
  end

  test "legacy timeline path redirects to activity (canonical feed)", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    conn = get(conn, ~p"/observability/sessions/#{session.id}/timeline")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/activity"
  end

  test "legacy memory path redirects with anchor", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    conn = get(conn, ~p"/observability/sessions/#{session.id}/memory")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability#session-observability-memory"
  end

  describe "legacy observability redirects (cloud mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    setup %{conn: conn} do
      {:ok, org} =
        Accounts.create_org(%{name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})

      {:ok, user} =
        Accounts.create_user(%{email: "acme-#{System.unique_integer([:positive])}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})

      {:ok, conn: conn, org: org, user: user, workspace: workspace, session: session}
    end

    test "unauthenticated callers learn nothing: 401 for valid and unknown ids", %{
      session: session
    } do
      for path <- [
            "/observability/sessions/#{session.id}",
            "/observability/sessions/#{session.id}/timeline",
            "/observability/sessions/#{session.id}/memory",
            "/observability/sessions/999999",
            "/observability/sessions/999999/timeline"
          ] do
        conn = get(build_conn(), path)
        assert json_response(conn, :unauthorized) == %{"error" => "sign in required"}
      end
    end

    test "members of another org get 404 without a redirect", %{conn: conn} do
      {:ok, outsider_org} =
        Accounts.create_org(%{
          name: "Outsider",
          slug: "outsider-#{System.unique_integer([:positive])}"
        })

      outsider_workspace = workspace_fixture(%{org_id: outsider_org.id})
      outsider_session = session_fixture(%{workspace: outsider_workspace})

      for path <- [
            "/observability/sessions/#{outsider_session.id}",
            "/observability/sessions/#{outsider_session.id}/timeline",
            "/observability/sessions/#{outsider_session.id}/memory"
          ] do
        conn = get(conn, path)
        assert json_response(conn, :not_found) == %{"error" => "session not found"}
      end
    end

    test "members still get the org-scoped redirect", %{
      conn: conn,
      org: org,
      workspace: ws,
      session: session
    } do
      conn = get(conn, ~p"/observability/sessions/#{session.id}")

      assert redirected_to(conn, 302) ==
               "/#{org.slug}/workspaces/#{ws.slug}/sessions/#{session.id}/observability"
    end
  end
end
