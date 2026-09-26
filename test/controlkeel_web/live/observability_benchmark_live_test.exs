defmodule ControlKeelWeb.ObservabilityBenchmarkLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
  alias ControlKeel.Repo

  defp benchmark_path(org, ws), do: "/#{org.slug}/workspaces/#{ws.slug}/benchmark"

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

    assert html =~ "controlkeel obs benchmarks drafts"
    assert html =~ "controlkeel obs benchmarks scenarios"
    assert html =~ "controlkeel obs benchmarks history"
    assert html =~ "controlkeel obs regressions"

    assert html =~ "No benchmark drafts yet."
    assert html =~ "No materialized observability scenarios yet."
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

    assert html =~ "Approved and materialized"
    assert html =~ "approved"
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

  test "benchmark page redirects unknown workspaces", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/benchmark")
  end

  test "benchmark page redirects scope-mismatched slugs", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/organizations"}}} =
             live(conn, "/#{org.slug}/workspaces/other-ws/benchmark")

    assert {:error, {:live_redirect, %{to: "/organizations"}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/benchmark")
  end

  test "global benchmark path resolves to the workspace page", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/observability/benchmark")

    assert redirected_to(conn, 302) == benchmark_path(org, ws)
  end

  test "legacy benchmark sub-routes redirect to anchored workspace sections", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    base = benchmark_path(org, ws)

    for {path, anchor} <- [
          {"/observability/benchmarks/drafts", "#benchmarks-drafts"},
          {"/observability/benchmarks/scenarios", "#benchmarks-scenarios"},
          {"/observability/benchmarks/history", "#benchmarks-history"},
          {"/observability/regressions", "#benchmarks-regressions"}
        ] do
      conn = get(conn, path)
      assert redirected_to(conn, 302) == "#{base}#{anchor}"
    end
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

    test "resolvers fall back to the workspace picker without sessions", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      for path <- [
            "/observability/benchmark",
            "/observability/benchmarks/drafts",
            "/observability/regressions"
          ] do
        conn = get(conn, path)
        assert redirected_to(conn, 302) == "/organizations"
      end
    end

    test "viewers are redirected from the benchmark page", %{
      conn: conn,
      org: org,
      workspace: ws,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      assert {:error,
              {:live_redirect,
               %{
                 to: "/organizations",
                 flash: %{"error" => "Admin or owner role required."}
               }}} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/benchmark")
    end

    test "admins can view the benchmark page", %{
      conn: conn,
      org: org,
      workspace: ws,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})

      {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/benchmark")

      assert has_element?(view, "#observability-benchmark-page")
    end
  end
end
