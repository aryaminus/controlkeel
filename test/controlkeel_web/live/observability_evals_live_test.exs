defmodule ControlKeelWeb.ObservabilityEvalsLiveTest do
  # The standalone Evals page is folded into Benchmark (`#evals` section, the
  # draft pipeline the candidates feed). These tests cover the merged content
  # on the benchmark page plus the `/evals` redirects (workspace + legacy
  # global).
  #
  # Note: the benchmark page is admin-gated for reads, so the folded evals
  # section inherits that gate — viewers could read the old standalone page.
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
  alias ControlKeel.Repo

  defp benchmark_path(org, ws), do: "/#{org.slug}/workspaces/#{ws.slug}/benchmark"

  defp eval_finding_fixture(session) do
    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.evals"
    })
  end

  test "benchmark page renders folded eval candidates", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    eval_finding_fixture(session)

    {:ok, view, html} = live(conn, benchmark_path(org, ws))

    assert html =~ "Eval candidates"
    assert html =~ "controlkeel obs evals"
    assert has_element?(view, "#evals")
    assert has_element?(view, "#observability-evals-list")
    assert has_element?(view, "#observability-persisted-evals-list")
    assert html =~ "View grouped problems"
    assert html =~ "benchmarks-drafts"
  end

  test "workspace evals path redirects to the benchmark evals section", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/benchmark#evals"
  end

  test "workspace evals redirect preserves the query string", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals?status=open")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/benchmark#evals?status=open"
  end

  test "legacy global evals path redirects to the workspace benchmark section", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/observability/evals")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/benchmark#evals"
  end

  test "save button flashes a summary after saving candidates", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    eval_finding_fixture(session)

    {:ok, view, _html} = live(conn, benchmark_path(org, ws))

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Saved 1 candidate(s)"
  end

  test "repeat save flashes a nothing-new message", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()
    eval_finding_fixture(session)

    {:ok, view, _html} = live(conn, benchmark_path(org, ws))

    view
    |> element("#observability-evals-save")
    |> render_click()

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Nothing new to save"
  end

  test "unknown workspace slug redirects instead of crashing", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/benchmark")
  end

  test "mismatched org slug redirects", %{conn: conn} do
    {_org, ws, _session} = org_bound_session_fixture()

    assert {:error, {:live_redirect, %{to: "/organizations"}}} =
             live(conn, "/other-org/workspaces/#{ws.slug}/benchmark")
  end

  describe "cloud mode role gates" do
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

    defp cloud_evals_setup(suffix) do
      {:ok, org} = Accounts.create_org(%{name: "EvalCo #{suffix}", slug: "evalco-#{suffix}"})

      {:ok, admin} = Accounts.create_user(%{email: "evals-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} = Accounts.create_user(%{email: "evals-viewer-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: viewer.id,
        org_id: org.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      ws = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: ws})

      finding_fixture(%{
        session: session,
        title: "Eval candidate finding",
        severity: "high",
        status: "open",
        category: "security",
        rule_id: "security.evals"
      })

      %{org: org, workspace: ws, admin: admin, viewer: viewer}
    end

    defp session_conn(conn, user, org) do
      Plug.Test.init_test_session(conn, %{
        "current_user_id" => user.id,
        "current_org_id" => org.id
      })
    end

    # The folded section inherits the benchmark admin read gate: viewers are
    # redirected instead of reading eval candidates.
    test "viewers are redirected from the folded evals section", %{conn: conn} do
      %{org: org, workspace: ws, viewer: viewer} =
        cloud_evals_setup(System.unique_integer([:positive]))

      assert {:error,
              {:live_redirect,
               %{
                 to: "/organizations",
                 flash: %{"error" => "Admin or owner role required."}
               }}} =
               live(
                 session_conn(conn, viewer, org),
                 "/#{org.slug}/workspaces/#{ws.slug}/benchmark"
               )

      assert Observability.saved_eval_candidates(workspace_id: ws.id).count == 0
    end

    test "admins can save candidates", %{conn: conn} do
      %{org: org, workspace: ws, admin: admin} =
        cloud_evals_setup(System.unique_integer([:positive]))

      {:ok, view, _html} =
        live(session_conn(conn, admin, org), "/#{org.slug}/workspaces/#{ws.slug}/benchmark")

      view
      |> element("#observability-evals-save")
      |> render_click()

      assert render(view) =~ "Saved 1 candidate(s)"
    end
  end
end
