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
      # A foreign session AND a foreign finding exist; a caller with no
      # accessible workspace must see neither — runs stay empty and the
      # problems aggregate must not leak other tenants' findings.
      {_org, _ws, session} = org_bound_session_fixture()
      {:ok, _finding} = create_foreign_finding(session)

      overview = ControlKeel.Observability.workspace_overview(limit: 6)

      assert overview.runs.recent == []
      assert overview.problems.count == 0
      assert overview.problems.total_findings == 0
      assert overview.problems.top == []
    end

    test "problems with no filter yields no cross-tenant rows in cloud mode" do
      {_org, _ws, session} = org_bound_session_fixture()
      {:ok, _finding} = create_foreign_finding(session)

      problems = ControlKeel.Observability.problems(limit: 5)

      assert problems.count == 0
      assert problems.total_findings == 0
      assert problems.problems == []
    end

    test "imports with no filter yields no cross-tenant rows in cloud mode" do
      insert_foreign_import_envelope()

      imports = ControlKeel.Observability.imports([])

      assert imports.count == 0
      assert imports.recent == []
    end

    test "loop diagnostics with no filter yields no cross-tenant events in cloud mode" do
      {_org, _ws, session} = org_bound_session_fixture()
      insert_foreign_session_event(session)

      diagnostics = ControlKeel.Observability.loop_diagnostics([])

      assert diagnostics.totals.event_runs == 0
      assert diagnostics.repeated_tool_events == []
    end

    test "memory quality with no filter yields no cross-tenant records in cloud mode" do
      {_org, _ws, session} = org_bound_session_fixture()
      memory_record_fixture(%{session: session})

      quality = ControlKeel.Observability.memory_quality([])

      assert quality.totals.records == 0
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

  # ── Foreign-row fixtures ────────────────────────────────────────────────
  #
  # The fail-closed assertions must run against tables that actually contain
  # another tenant's rows: a filter that collapses to "unfiltered" is only
  # detectable when foreign data exists to leak (the original PR's tests ran
  # against empty tables and therefore could not catch it).

  defp create_foreign_finding(session) do
    Mission.create_finding(%{
      session_id: session.id,
      title: "Foreign tenant finding",
      rule_id: "foreign-probe",
      category: "security",
      severity: "high",
      status: "open",
      auto_resolved: false,
      metadata: %{},
      plain_message: "Foreign tenant finding"
    })
  end

  defp insert_foreign_import_envelope do
    {_org, ws, _session} = org_bound_session_fixture()

    payload_sha256 =
      :crypto.hash(:sha256, "foreign-#{System.unique_integer([:positive])}")
      |> Base.encode16(case: :lower)

    %ControlKeel.Observability.ImportedEnvelope{}
    |> ControlKeel.Observability.ImportedEnvelope.changeset(%{
      schema_version: "controlkeel.observability.v1",
      source: %{"product" => "controlkeel", "surface" => "cli"},
      original_session_title: "foreign envelope",
      health: "healthy",
      problem_groups: 0,
      total_problem_findings: 0,
      redaction_policy: "summary_only",
      integrity_status: "verified",
      payload_sha256: payload_sha256,
      import_mode: "local_persist",
      imported_at: DateTime.utc_now() |> DateTime.truncate(:second),
      envelope: %{},
      workspace_id: ws.id
    })
    |> ControlKeel.Repo.insert!()
  end

  defp insert_foreign_session_event(session) do
    %ControlKeel.Mission.SessionEvent{}
    |> ControlKeel.Mission.SessionEvent.changeset(%{
      session_id: session.id,
      event_type: "tool_call",
      actor: "fixture",
      summary: "foreign tenant event",
      payload: %{},
      metadata: %{}
    })
    |> ControlKeel.Repo.insert!()
  end
end
