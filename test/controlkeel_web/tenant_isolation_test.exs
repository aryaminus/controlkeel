defmodule ControlKeelWeb.TenantIsolationTest do
  @moduledoc """
  Regression coverage for cross-tenant data leaks on the browser surfaces.

  These assertions encode the invariant directly: a user must never see or
  mutate another organization's data, and scoping must be derived from the
  authenticated viewer rather than an ambient hint.

  Before the fix, `inject_org_workspace_ids/2` fell open (no filter when the
  org had no workspaces, and raw user params flowed through), the observability
  pages derived their workspace from `list_recent_sessions(1)` (newest session
  in the whole database), and the session filter dropdowns listed every session
  across all tenants.
  """
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

  # Creates a user who OWNS an org, giving them an active membership and one
  # accessible workspace.
  defp viewer_with_workspace do
    suffix = System.unique_integer([:positive])
    user = fixture_user("viewer-#{suffix}@example.com")

    {:ok, org} =
      Accounts.create_org_with_owner(user.id, %{
        name: "ViewerOrg #{suffix}",
        slug: "viewer-org-#{suffix}"
      })

    workspace = workspace_fixture(%{org_id: org.id})
    %{user: user, org: org, workspace: workspace}
  end

  defp fixture_user(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  describe "accessible_workspace_ids/1 scoping" do
    test "returns only workspaces in the user's orgs" do
      %{user: viewer, workspace: ws_a} = viewer_with_workspace()
      {_org_b, ws_b, _session_b} = org_bound_session_fixture()

      ids = Mission.accessible_workspace_ids(viewer.id)

      assert ws_a.id in ids
      refute ws_b.id in ids
    end

    test "a user with no org membership has no accessible workspaces" do
      viewer = fixture_user("no-memberships-#{System.unique_integer([:positive])}@example.com")
      {_org, _ws, _session} = org_bound_session_fixture()

      assert Mission.accessible_workspace_ids(viewer.id) == []
    end
  end

  describe "list_findings_browser_sessions_for_user/2" do
    test "does not leak sessions from another org" do
      %{user: viewer, workspace: ws_a} = viewer_with_workspace()
      session_a = session_fixture(%{workspace: ws_a})
      {_org_b, _ws_b, session_b} = org_bound_session_fixture()

      ids = Mission.list_findings_browser_sessions_for_user(viewer, 30) |> Enum.map(& &1.id)

      assert session_a.id in ids
      refute session_b.id in ids
    end

    test "returns no rows for a user with no memberships" do
      viewer = fixture_user("no-members-#{System.unique_integer([:positive])}@example.com")
      {_org, _ws, _session} = org_bound_session_fixture()

      assert Mission.list_findings_browser_sessions_for_user(viewer, 30) == []
    end
  end

  describe "list_recent_sessions_for_user/2" do
    test "does not leak sessions from another org" do
      %{user: viewer, workspace: ws_a} = viewer_with_workspace()
      session_a = session_fixture(%{workspace: ws_a})
      {_org_b, _ws_b, session_b} = org_bound_session_fixture()

      ids = Mission.list_recent_sessions_for_user(viewer, 30) |> Enum.map(& &1.id)

      assert session_a.id in ids
      refute session_b.id in ids
    end

    test "returns no rows for a nil user in cloud mode" do
      {_org, _ws, _session} = org_bound_session_fixture()

      assert Mission.list_recent_sessions_for_user(nil, 5) == []
    end
  end

  describe "browse_findings/1 tenancy" do
    test "an injected empty workspace filter yields no cross-tenant rows" do
      {_org_a, _ws_a, session_a} = org_bound_session_fixture()

      {:ok, finding} =
        Mission.create_finding(%{
          session_id: session_a.id,
          title: "Tenant A finding",
          rule_id: "tenant-probe",
          category: "security",
          severity: "high",
          status: "open",
          auto_resolved: false,
          metadata: %{},
          plain_message: "Tenant A finding"
        })

      result = Mission.browse_findings(%{"workspace_ids" => []})

      refute Enum.any?(result.entries, &(&1.id == finding.id))
    end

    test "a workspace filter limited to one org excludes another org's finding" do
      %{workspace: ws_a} = viewer_with_workspace()
      {_org_b, _ws_b, session_b} = org_bound_session_fixture()

      {:ok, finding_b} =
        Mission.create_finding(%{
          session_id: session_b.id,
          title: "Tenant B finding",
          rule_id: "other-tenant",
          category: "security",
          severity: "high",
          status: "open",
          auto_resolved: false,
          metadata: %{},
          plain_message: "Tenant B finding"
        })

      result = Mission.browse_findings(%{"workspace_ids" => [ws_a.id]})

      refute Enum.any?(result.entries, &(&1.id == finding_b.id))
    end
  end

  describe "observability context layer fails closed" do
    test "workspace_overview with no filter yields no cross-tenant rows in cloud mode" do
      # A foreign session exists; a caller with no accessible workspace must not see it.
      {_org, _ws, _session} = org_bound_session_fixture()

      overview = ControlKeel.Observability.workspace_overview(limit: 6)

      assert overview.runs.recent == []
    end

    test "trends with no filter yields no cross-tenant totals in cloud mode" do
      {_org, _ws, _session} = org_bound_session_fixture()

      totals = ControlKeel.Observability.trends([]).totals

      assert Enum.all?(Map.values(totals), &(is_integer(&1) and &1 == 0))
    end

    test "funnel_summary scoped to a viewer excludes another org's sessions" do
      %{user: viewer, workspace: ws_a} = viewer_with_workspace()
      session_a = session_fixture(%{workspace: ws_a})
      {_org_b, _ws_b, session_b} = org_bound_session_fixture()

      mine = ControlKeel.Analytics.funnel_summary(user: viewer, limit: 50)
      assert mine.recent_session_count == Enum.count([session_a.id])

      scoped = ControlKeel.Analytics.funnel_summary(workspace_ids: [ws_a.id], limit: 50)
      assert scoped.recent_session_count == Enum.count([session_a.id])
      refute scoped.recent_session_count == 2
      _ = session_b
    end

    test "funnel_summary with no scope is empty in cloud mode" do
      {_org, _ws, _session} = org_bound_session_fixture()

      summary = ControlKeel.Analytics.funnel_summary(limit: 50)
      assert summary.recent_session_count == 0
    end
  end
end
