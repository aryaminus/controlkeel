defmodule ControlKeelWeb.ObservabilityLoopLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
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

    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/loop")

    assert html =~ "Learning loop"
    assert html =~ "Safety boundary"
    assert html =~ "Automatic benchmark execution: false"
    assert html =~ "Automatic promotion: false"
  end

  test "loop page renders loop diagnostics section with no detected runs", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/loop")

    assert html =~ "Loop diagnostics"
    assert html =~ "Repeated tool events"
    assert html =~ "Repeated invocations"
    assert html =~ "No repeated identical tool-event runs detected."
    assert html =~ "No repeated identical invocation runs detected."
  end

  test "capture performance snapshot persists a memory record and renders results", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/loop")

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

  describe "capture-perf-snapshot authorization (cloud mode)" do
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
        Accounts.create_org(%{name: "LoopCo #{suffix}", slug: "loopco-#{suffix}"})

      {:ok, admin} =
        Accounts.create_user(%{email: "loop-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} =
        Accounts.create_user(%{email: "loop-viewer-#{suffix}@example.com"})

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

    test "viewers see no capture button and cannot persist a snapshot", %{
      conn: conn,
      org: org,
      workspace: workspace,
      viewer: viewer
    } do
      conn = init_test_session(conn, %{current_user_id: viewer.id, current_org_id: org.id})

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/loop")

      refute has_element?(view, "#observability-perf-capture")

      denied_html = render_click(view, "capture-perf-snapshot")
      assert denied_html =~ "Admin or owner role required."

      assert Repo.aggregate(
               from(r in Record, where: r.source_type == "observability"),
               :count,
               :id
             ) == 0
    end

    test "admins can capture a performance snapshot", %{
      conn: conn,
      org: org,
      workspace: workspace,
      admin: admin
    } do
      conn = init_test_session(conn, %{current_user_id: admin.id, current_org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      {:ok, view, _html} =
        live(conn, "/#{org.slug}/workspaces/#{workspace.slug}/observability/loop")

      assert has_element?(view, "#observability-perf-capture")

      rendered = render_click(view, "capture-perf-snapshot")
      assert rendered =~ "Performance snapshot"

      assert Repo.aggregate(
               from(r in Record,
                 where: r.source_type == "observability" and r.session_id == ^session.id
               ),
               :count,
               :id
             ) == 1
    end
  end
end
