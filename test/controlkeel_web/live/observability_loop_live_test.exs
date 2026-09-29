defmodule ControlKeelWeb.ObservabilityLoopLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Memory.Record
  alias ControlKeel.Repo

  test "workspace loop path 302s to observability with query preserved", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/#{org.slug}/workspaces/#{ws.slug}/loop?filter=red")

    assert redirected_to(conn, 302) ==
             "/#{org.slug}/workspaces/#{ws.slug}/observability?filter=red"
  end

  test "legacy global loop path still resolves to workspace observability", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()

    conn = get(conn, "/observability/loop")
    assert redirected_to(conn, 302) == "/#{org.slug}/workspaces/#{ws.slug}/observability"
  end

  test "folded overview renders read-only learning loop status", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Loop page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.loop_page"
    })

    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

    assert html =~ "Safety boundary"
    assert html =~ "Automatic benchmark execution: false"
    assert html =~ "Automatic promotion: false"
    refute html =~ "controlkeel obs loop"
  end

  test "folded overview renders loop diagnostics section with no detected runs", %{conn: conn} do
    {org, ws, _session} = org_bound_session_fixture()
    {:ok, _view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

    assert html =~ "Loop diagnostics"
    assert html =~ "Repeated tool events"
    assert html =~ "Repeated invocations"
    assert html =~ "No repeated identical tool-event runs detected."
    assert html =~ "No repeated identical invocation runs detected."
  end

  test "capture performance snapshot persists a memory record and renders results", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    {:ok, view, html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability")

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

  test "unknown workspace slug redirects instead of crashing", %{conn: conn} do
    {org, _ws, _session} = org_bound_session_fixture()

    assert {:error,
            {:live_redirect, %{to: "/organizations", flash: %{"error" => "Workspace not found."}}}} =
             live(conn, "/#{org.slug}/workspaces/no-such-ws/observability")
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

    defp cloud_loop_setup(suffix) do
      {:ok, org} = Accounts.create_org(%{name: "LoopCo #{suffix}", slug: "loopco-#{suffix}"})

      {:ok, admin} = Accounts.create_user(%{email: "loop-admin-#{suffix}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, viewer} = Accounts.create_user(%{email: "loop-viewer-#{suffix}@example.com"})

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

      %{org: org, workspace: ws, session: session, admin: admin, viewer: viewer}
    end

    defp session_conn(conn, user, org) do
      Plug.Test.init_test_session(conn, %{
        "current_user_id" => user.id,
        "current_org_id" => org.id
      })
    end

    defp persisted_snapshot?(workspace_id) do
      from(r in Record,
        where: r.workspace_id == ^workspace_id and r.source_type == "observability",
        limit: 1
      )
      |> Repo.one()
    end

    test "viewers keep read access to the folded observability page", %{conn: conn} do
      %{org: org, workspace: ws, viewer: viewer} =
        cloud_loop_setup(System.unique_integer([:positive]))

      {:ok, _view, html} =
        live(session_conn(conn, viewer, org), "/#{org.slug}/workspaces/#{ws.slug}/observability")

      assert html =~ "Safety boundary"
    end

    test "viewers cannot capture performance snapshots", %{conn: conn} do
      %{org: org, workspace: ws, viewer: viewer} =
        cloud_loop_setup(System.unique_integer([:positive]))

      {:ok, view, _html} =
        live(session_conn(conn, viewer, org), "/#{org.slug}/workspaces/#{ws.slug}/observability")

      view
      |> element("#observability-perf-capture")
      |> render_click()

      assert render(view) =~ "Admin or owner role required."
      refute persisted_snapshot?(ws.id)
    end
  end
end
