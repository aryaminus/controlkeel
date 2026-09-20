defmodule ControlKeel.Cloud.ScopeTest do
  use ControlKeel.DataCase, async: true

  import ControlKeel.Cloud.Scope

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Repo

  describe "scope_workspace/2" do
    test "pass-through when workspace_id is nil" do
      query = from(p in RunPackage, select: p.id)
      assert scope_workspace(query, nil) == query
    end

    test "adds workspace_id filter to queryable" do
      query = from(p in RunPackage, select: p.id)

      scoped = scope_workspace(query, 42)

      assert inspect(scoped) =~ "workspace_id"
    end
  end

  describe "scope_workspaces/2" do
    test "empty list yields no rows, not a pass-through" do
      # "No accessible workspaces" must never degrade into an unscoped
      # fetch (issue #183).
      session =
        ControlKeel.MissionFixtures.session_fixture(%{title: "Scoped session"})

      assert Repo.all(scope_workspaces(Session, [])) == []

      assert Repo.all(scope_workspaces(Session, [session.workspace_id]))
             |> Enum.map(& &1.id) == [session.id]
    end

    test "adds IN clause for workspace ids" do
      query = from(p in RunPackage, select: p.id)

      scoped = scope_workspaces(query, [1, 2, 3])

      assert inspect(scoped) =~ "workspace_id"
    end
  end

  describe "scope_org/2" do
    test "pass-through when org_id is nil" do
      query = from(p in RunPackage, select: p.id)
      assert scope_org(query, nil) == query
    end

    test "adds org_id filter to queryable" do
      query = from(p in RunPackage, select: p.id)

      scoped = scope_org(query, 7)

      assert inspect(scoped) =~ "org_id"
    end
  end

  describe "get_in_workspace/3" do
    test "returns nil for non-existent record" do
      assert get_in_workspace(RunPackage, 999_999, 1) == nil
    end

    test "returns nil when record belongs to different workspace" do
      ws_a = insert_workspace("scope-ws-a")
      ws_b = insert_workspace("scope-ws-b")

      {:ok, pkg} = insert_run_package(ws_a)

      # Can see in correct workspace
      assert get_in_workspace(RunPackage, pkg.id, ws_a.id) != nil

      # Cannot see in different workspace
      assert get_in_workspace(RunPackage, pkg.id, ws_b.id) == nil
    end
  end

  describe "get_by_in_workspace/3" do
    test "returns nil when no record matches clauses in workspace" do
      assert get_by_in_workspace(RunPackage, [external_id: "nonexistent"], 1) == nil
    end

    test "returns record only in correct workspace" do
      ws_a = insert_workspace("scope-ws-c")
      ws_b = insert_workspace("scope-ws-d")

      {:ok, pkg} = insert_run_package(ws_a)

      # Can fetch by external_id in correct workspace
      result = get_by_in_workspace(RunPackage, [external_id: pkg.external_id], ws_a.id)
      assert result.id == pkg.id

      # Cannot fetch by external_id in wrong workspace
      assert get_by_in_workspace(RunPackage, [external_id: pkg.external_id], ws_b.id) == nil
    end

    test "works with map clauses" do
      ws = insert_workspace("scope-ws-e")

      {:ok, pkg} = insert_run_package(ws)

      result = get_by_in_workspace(RunPackage, %{external_id: pkg.external_id}, ws.id)
      assert result.id == pkg.id
    end
  end

  describe "require_workspace/2" do
    test "returns :ok when workspace_id matches" do
      record = %{workspace_id: 42, id: 1}
      assert require_workspace(record, 42) == :ok
    end

    test "returns error when workspace_id mismatches" do
      record = %{workspace_id: 42, id: 1}
      assert require_workspace(record, 99) == {:error, :workspace_scope_mismatch}
    end

    test "returns error for struct without workspace_id" do
      record = %{id: 1}
      assert require_workspace(record, 42) == {:error, :workspace_scope_mismatch}
    end
  end

  describe "resolve_session/2" do
    test "returns error for non-existent session" do
      assert resolve_session(999_999, 1) == {:error, :not_found}
    end

    test "returns ok when session belongs to workspace" do
      ws = insert_workspace("scope-ws-f")
      session = insert_session(ws, "scope-test-1")

      assert {:ok, ^session} = resolve_session(session.id, ws.id)
    end

    test "returns error when session belongs to different workspace" do
      ws_a = insert_workspace("scope-ws-g")
      ws_b = insert_workspace("scope-ws-h")
      session = insert_session(ws_a, "scope-test-2")

      assert resolve_session(session.id, ws_b.id) == {:error, :workspace_scope_mismatch}
    end
  end

  # --- Helpers ---

  defp insert_workspace(seed) do
    {:ok, ws} =
      ControlKeel.Mission.create_workspace(%{
        name: "Scope-#{seed}",
        slug: "scope-#{seed}-#{:rand.uniform(99_999)}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    ws
  end

  defp insert_session(ws, title) do
    {:ok, session} =
      Mission.create_session(%{
        title: title,
        objective: "scope test",
        risk_tier: "low",
        budget_cents: 10_000,
        daily_budget_cents: 5_000,
        workspace_id: ws.id
      })

    session
  end

  defp insert_run_package(ws) do
    # Generate a valid pkg_<ULID> external_id (26 uppercase alphanumeric chars)
    ulid = ControlKeel.Cloud.Telemetry.Envelope.ulid()

    %RunPackage{}
    |> RunPackage.changeset(%{
      workspace_id: ws.id,
      external_id: "pkg_#{ulid}",
      runtime_target: "executor",
      status: "pending",
      callback_token_hash: "hash_#{:rand.uniform(99_999_999)}",
      budget_cents_allocated: 1000
    })
    |> Repo.insert()
  end
end
