defmodule ControlKeelWeb.ObservabilityBenchmarkLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Observability
  alias ControlKeel.Repo

  defp benchmark_path(org, ws), do: "/#{org.slug}/workspaces/#{ws.slug}/observability/benchmark"

  defp draft_fixture(workspace, session) do
    finding_fixture(%{
      session: session,
      title: "Benchmark draft finding",
      severity: "high",
      status: "blocked",
      category: "security",
      rule_id: "security.benchmark"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: workspace.id)

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: workspace.id)

    draft_id
  end

  test "workspace benchmark page stacks drafts, scenarios, history, and regressions", %{
    conn: conn
  } do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, benchmark_path(org, ws))

    assert html =~ "Benchmark"
    assert has_element?(view, "#observability-benchmark-page")
    assert has_element?(view, "#benchmarks-drafts")
    assert has_element?(view, "#benchmarks-scenarios")
    assert has_element?(view, "#benchmarks-history")
    assert has_element?(view, "#benchmarks-regressions")
    assert has_element?(view, "#observability-benchmark-drafts-list")
    assert has_element?(view, "#observability-benchmark-scenarios-list")
    assert has_element?(view, "#observability-benchmark-history-runs")
    assert has_element?(view, "#observability-regressions-runs")

    assert html =~ "No benchmark drafts yet."
    assert html =~ "No benchmark tests yet."
    assert html =~ "No observability benchmark runs yet."
  end

  test "draft approve event refreshes all sections with one flash", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    draft_id = draft_fixture(ws, session)

    {:ok, view, _html} = live(conn, benchmark_path(org, ws))

    assert has_element?(view, "#observability-benchmark-draft-#{draft_id}")

    html =
      view
      |> element("#observability-benchmark-draft-approve-#{draft_id}")
      |> render_click()

    assert html =~ "Approved and created"
    assert html =~ "approved"
  end

  test "draft reject and archive events update status with flashes", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    draft_id = draft_fixture(ws, session)

    {:ok, view, _html} = live(conn, benchmark_path(org, ws))

    reject_html =
      view
      |> element("#observability-benchmark-draft-reject-#{draft_id}")
      |> render_click()

    assert reject_html =~ "Rejected draft"

    archive_html =
      view
      |> element("#observability-benchmark-draft-archive-#{draft_id}")
      |> render_click()

    assert archive_html =~ "Archived draft"
  end

  test "generate-drafts event reports when no candidates exist", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, view, _html} = live(conn, benchmark_path(org, ws))

    html =
      view
      |> element("#observability-benchmark-drafts-generate")
      |> render_click()

    assert html =~ "No open saved eval candidates"
  end

  test "legacy benchmark sub-routes redirect to the workspace benchmark page", %{conn: conn} do
    base =
      "/#{LocalDefaults.default_org_slug()}/workspaces/#{LocalDefaults.default_workspace_slug()}/observability/benchmark"

    for path <- [
          "/observability/benchmarks/drafts",
          "/observability/benchmarks/scenarios",
          "/observability/benchmarks/history",
          "/observability/regressions"
        ] do
      conn = get(conn, path)
      assert redirected_to(conn, 302) == base
    end

    conn = get(conn, "/observability/benchmarks/drafts?suite=x")
    assert redirected_to(conn, 302) == "#{base}?suite=x"
  end

  describe "benchmark access and resolvers (cloud mode)" do
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
      suffix = System.unique_integer([:positive])

      {:ok, org} =
        Accounts.create_org(%{name: "BenchCo #{suffix}", slug: "benchco-#{suffix}"})

      {:ok, admin} =
        Accounts.create_user(%{email: "bench-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} =
        Accounts.create_user(%{email: "bench-viewer-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: viewer.id,
        org_id: org.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})

      {:ok, conn: conn, org: org, workspace: workspace, admin: admin, viewer: viewer}
    end

    test "legacy sub-routes redirect to the workspace benchmark page", %{
      conn: conn,
      org: org,
      workspace: workspace,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})
      session_fixture(%{workspace: workspace})

      base = "/#{org.slug}/workspaces/#{workspace.slug}/observability/benchmark"

      for path <- [
            "/observability/benchmarks/drafts",
            "/observability/regressions"
          ] do
        conn = get(conn, path)
        assert redirected_to(conn, 302) == base
      end
    end

    test "viewers can view the benchmark page", %{
      conn: conn,
      org: org,
      workspace: workspace,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/benchmark")

      assert has_element?(view, "#observability-benchmark-page")
    end

    test "admins can view the benchmark page", %{
      conn: conn,
      org: org,
      workspace: workspace,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/benchmark")

      assert has_element?(view, "#observability-benchmark-page")
    end
  end
end
