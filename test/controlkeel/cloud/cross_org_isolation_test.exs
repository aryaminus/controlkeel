defmodule ControlKeel.Cloud.CrossOrgIsolationTest do
  @moduledoc """
  Regression test for CK-CLOUD-XORG-TEST-001.

  Locks in the boundary that a user in org A cannot observe enrolled
  workspaces, run packages, mission workspaces, or telemetry events
  belonging to org B through any of the user-facing surfaces (Accounts,
  KeyRegistry, RuntimeContext, CloudProjectsLive).
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.Workspace.KeyRegistry
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  setup do
    {org_a, user_a, mws_a, key_a, pkg_a} = setup_tenant("A")
    {org_b, user_b, mws_b, key_b, pkg_b} = setup_tenant("B")

    {:ok,
     org_a: org_a,
     user_a: user_a,
     mws_a: mws_a,
     key_a: key_a,
     pkg_a: pkg_a,
     org_b: org_b,
     user_b: user_b,
     mws_b: mws_b,
     key_b: key_b,
     pkg_b: pkg_b}
  end

  describe "Accounts.authorize_cloud_execution/2 across orgs" do
    test "user from org B cannot authorize cloud execution on org A's workspace", %{
      mws_a: mws_a,
      user_b: user_b
    } do
      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(mws_a.id, user_id: user_b.id)
    end

    test "user from org A cannot authorize cloud execution on org B's workspace", %{
      mws_b: mws_b,
      user_a: user_a
    } do
      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(mws_b.id, user_id: user_a.id)
    end
  end

  describe "KeyRegistry.list_for_org/1" do
    test "scopes to caller's org only", %{
      org_a: org_a,
      org_b: org_b,
      key_a: key_a,
      key_b: key_b
    } do
      ids_a = KeyRegistry.list_for_org(org_a.id) |> Enum.map(& &1.id)
      ids_b = KeyRegistry.list_for_org(org_b.id) |> Enum.map(& &1.id)

      assert key_a.id in ids_a
      refute key_b.id in ids_a

      assert key_b.id in ids_b
      refute key_a.id in ids_b
    end
  end

  describe "RuntimeContext.list_for_workspace/2" do
    test "returns only packages bound to the given workspace", %{
      mws_a: mws_a,
      mws_b: mws_b,
      pkg_a: pkg_a,
      pkg_b: pkg_b
    } do
      ids_a = RuntimeContext.list_for_workspace(mws_a.id) |> Enum.map(& &1.id)
      ids_b = RuntimeContext.list_for_workspace(mws_b.id) |> Enum.map(& &1.id)

      assert ids_a == [pkg_a.id]
      assert ids_b == [pkg_b.id]
    end
  end

  describe "CloudProjectsLive :index" do
    test "shows only org A's workspaces when signed in as user_a", %{
      conn: conn,
      user_a: user_a,
      key_a: key_a,
      key_b: key_b
    } do
      conn = session_conn(conn, user_a.id)
      {:ok, _view, html} = live(conn, ~p"/cloud/projects")

      assert html =~ key_a.workspace_id
      refute html =~ key_b.workspace_id
    end
  end

  describe "CloudProjectsLive :show" do
    test "refuses access to org B's enrolled workspace when signed in as user_a", %{
      conn: conn,
      user_a: user_a,
      key_b: key_b
    } do
      conn = session_conn(conn, user_a.id)
      {:ok, _view, html} = live(conn, ~p"/cloud/projects/#{key_b.workspace_id}")

      assert html =~ "Not visible"
      refute html =~ "Cloud run packages"
    end

    test "user_a can see their own org A workspace and packages", %{
      conn: conn,
      user_a: user_a,
      key_a: key_a,
      pkg_a: pkg_a
    } do
      conn = session_conn(conn, user_a.id)
      {:ok, _view, html} = live(conn, ~p"/cloud/projects/#{key_a.workspace_id}")

      assert html =~ "Cloud run packages"
      assert html =~ pkg_a.runtime_target
    end
  end

  # ─────────────── helpers ───────────────

  defp setup_tenant(label) do
    n = Integer.to_string(System.unique_integer([:positive]))
    slug = "org-#{label}-#{n}" |> String.downcase()
    org = insert_org(slug)
    user = insert_user("user-#{label}-#{n}@example.com")
    insert_active_membership(user.id, org.id, "member")
    mws = insert_mission_workspace(org, "mws-#{label}-#{n}")
    key = enroll_key(org.id, mws.id)
    pkg = create_package(mws, user.id)
    {org, user, mws, key, pkg}
  end

  defp session_conn(conn, user_id) do
    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

  defp insert_org(slug) do
    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: slug, slug: slug, status: "active"})
      |> Repo.insert()

    org
  end

  defp insert_user(email) do
    {:ok, user} =
      %Accounts.User{}
      |> Accounts.User.changeset(%{email: email, status: "active"})
      |> Repo.insert()

    user
  end

  defp insert_active_membership(user_id, org_id, role) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, m} =
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user_id,
        org_id: org_id,
        role: role,
        status: "active",
        accepted_at: now
      })
      |> Repo.insert()

    m
  end

  defp insert_mission_workspace(org, slug) do
    {:ok, ws} =
      %ControlKeel.Mission.Workspace{}
      |> ControlKeel.Mission.Workspace.changeset(%{
        name: slug,
        slug: slug,
        org_id: org.id,
        industry: "technology",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "baseline",
        status: "active"
      })
      |> Repo.insert()

    ws
  end

  defp enroll_key(org_id, mws_id) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    pub_b64 = Base.encode64(pub)
    fp = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

    {:ok, key} =
      KeyRegistry.enroll(%{
        workspace_id:
          "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
        public_key: pub_b64,
        algorithm: "ed25519",
        fingerprint: fp,
        name: "key-#{org_id}",
        org_id: org_id,
        mission_workspace_id: mws_id
      })

    key
  end

  defp create_package(mws, user_id) do
    session = MissionFixtures.session_fixture(%{workspace: mws})
    task = MissionFixtures.task_fixture(%{session: session})

    {:ok, pkg, _token} =
      RuntimeContext.create_package(%{
        workspace_id: mws.id,
        session_id: session.id,
        task_id: task.id,
        runtime_target: "devin",
        budget_cents_allocated: 100,
        user_id: user_id
      })

    pkg
  end
end
