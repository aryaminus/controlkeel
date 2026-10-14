defmodule ControlKeel.Cloud.RuntimeContextTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.MissionFixtures

  setup do
    {workspace, user, _org} = MissionFixtures.org_bound_workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace, user: user})
    {:ok, workspace: workspace, session: session, user: user}
  end

  describe "create_package/1" do
    test "creates a pending package and returns the raw callback token", %{
      workspace: workspace,
      user: user,
      session: session
    } do
      assert {:ok, package, raw_token} =
               RuntimeContext.create_package(%{
                 workspace_id: workspace.id,
                 user_id: user.id,
                 user_id: user.id,
                 session_id: session.id,
                 runtime_target: "devin",
                 budget_cents_allocated: 500,
                 scopes: ["mcp:access", "context:read"],
                 payload: %{"task" => "implement feature X"}
               })

      assert package.status == "pending"
      assert package.runtime_target == "devin"
      assert package.budget_cents_allocated == 500
      assert package.scopes == "mcp:access,context:read"
      assert package.payload == %{"task" => "implement feature X"}
      assert is_binary(raw_token)
      assert byte_size(raw_token) > 20
      refute package.callback_token_hash == raw_token
    end

    test "rejects unknown runtime targets", %{workspace: workspace, user: user} do
      assert {:error, changeset} =
               RuntimeContext.create_package(%{
                 workspace_id: workspace.id,
                 user_id: user.id,
                 user_id: user.id,
                 runtime_target: "made-up-runtime",
                 budget_cents_allocated: 0
               })

      assert "is invalid" in errors_on(changeset).runtime_target
    end

    test "rejects negative budget", %{workspace: workspace, user: user} do
      assert {:error, changeset} =
               RuntimeContext.create_package(%{
                 workspace_id: workspace.id,
                 user_id: user.id,
                 user_id: user.id,
                 runtime_target: "open-swe",
                 budget_cents_allocated: -100
               })

      assert errors_on(changeset).budget_cents_allocated != []
    end
  end

  describe "authenticate_callback/1" do
    test "returns the package for a valid token", %{workspace: workspace, user: user} do
      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          runtime_target: "executor",
          budget_cents_allocated: 100
        })

      assert {:ok, ^package} = RuntimeContext.authenticate_callback(raw_token)
    end

    test "returns :not_found for unknown tokens", %{} do
      assert :not_found = RuntimeContext.authenticate_callback("garbage-token-value")
    end

    test "returns {:terminal, _} for completed packages", %{workspace: workspace, user: user} do
      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          runtime_target: "open-swe",
          budget_cents_allocated: 0
        })

      {:ok, _} = RuntimeContext.transition_status(package, "completed")

      assert {:terminal, completed} = RuntimeContext.authenticate_callback(raw_token)
      assert completed.status == "completed"
    end
  end

  describe "transition_status/3" do
    setup %{workspace: workspace, user: user} do
      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          runtime_target: "warp-oz",
          budget_cents_allocated: 200
        })

      {:ok, package: package, raw_token: raw_token}
    end

    test "stamps dispatched_at when moving to dispatched", %{package: package} do
      {:ok, updated} = RuntimeContext.transition_status(package, "dispatched")
      assert updated.status == "dispatched"
      assert %DateTime{} = updated.dispatched_at
      refute updated.completed_at
    end

    test "stamps completed_at on terminal states", %{package: package} do
      {:ok, updated} =
        RuntimeContext.transition_status(package, "completed",
          result_summary: "ok",
          proof_refs: ["abc123", "def456"]
        )

      assert updated.status == "completed"
      assert %DateTime{} = updated.completed_at
      assert updated.result_summary == "ok"
      assert updated.proof_refs == "abc123,def456"
    end

    test "rejects late updates on terminal packages", %{package: package} do
      {:ok, _} = RuntimeContext.transition_status(package, "failed", error_summary: "boom")
      assert {:error, :terminal} = RuntimeContext.transition_status(package, "completed")
    end

    test "rejects invalid status strings", %{package: package} do
      assert {:error, :invalid_status} = RuntimeContext.transition_status(package, "nope")
    end

    test "by id: returns :not_found for unknown package", %{} do
      assert {:error, :not_found} = RuntimeContext.transition_status(999_999, "completed")
    end
  end

  describe "list_for_workspace/2 + status_counts/1" do
    setup %{workspace: workspace, user: user} do
      for runtime <- ~w(devin open-swe executor) do
        {:ok, _pkg, _token} =
          RuntimeContext.create_package(%{
            workspace_id: workspace.id,
            user_id: user.id,
            runtime_target: runtime,
            budget_cents_allocated: 100
          })
      end

      {:ok, replit_pkg, _replit_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          runtime_target: "replit-agent",
          budget_cents_allocated: 0
        })

      {:ok, _completed} = RuntimeContext.transition_status(replit_pkg, "completed")
      :ok
    end

    test "lists newest-first capped to limit", %{workspace: workspace, user: user} do
      packages = RuntimeContext.list_for_workspace(workspace.id, limit: 2)
      assert length(packages) == 2
    end

    test "filters by status", %{workspace: workspace, user: user} do
      pending = RuntimeContext.list_for_workspace(workspace.id, status: "pending")
      assert length(pending) == 3
      assert Enum.all?(pending, &(&1.status == "pending"))
    end

    test "status_counts/1 aggregates", %{workspace: workspace, user: user} do
      counts = RuntimeContext.status_counts(workspace.id)
      assert counts["pending"] == 3
      assert counts["completed"] == 1
    end
  end

  describe "RunPackage helpers" do
    test "terminal? matches all three terminal statuses" do
      for status <- ~w(completed failed cancelled) do
        assert RunPackage.terminal?(%RunPackage{status: status}),
               "status #{status} should be terminal"
      end

      refute RunPackage.terminal?(%RunPackage{status: "pending"})
      refute RunPackage.terminal?(%RunPackage{status: "dispatched"})
    end
  end

  describe "tenant isolation for scoped lookups" do
    test "get_by_external_id/2 returns nil for different workspace" do
      {ws_a, user_a} = insert_workspace("rt-iso-a")
      {ws_b, _user_b} = insert_workspace("rt-iso-b")

      {:ok, pkg, _token} = insert_package({ws_a, user_a})

      assert RuntimeContext.get_by_external_id(pkg.external_id, ws_a.id) != nil
      assert RuntimeContext.get_by_external_id(pkg.external_id, ws_b.id) == nil
    end

    test "get_package/2 returns nil for different workspace" do
      {ws_a, user_a} = insert_workspace("rt-iso-c")
      {ws_b, _user_b} = insert_workspace("rt-iso-d")

      {:ok, pkg, _token} = insert_package({ws_a, user_a})

      assert RuntimeContext.get_package(pkg.id, ws_a.id) != nil
      assert RuntimeContext.get_package(pkg.id, ws_b.id) == nil
    end
  end

  defp insert_workspace(seed) do
    {ws, user, _org} = MissionFixtures.org_bound_workspace_fixture(%{name: "RT-ISO-#{seed}"})
    {ws, user}
  end

  defp insert_package({ws, user}) do
    session = MissionFixtures.session_fixture(%{workspace: ws})

    RuntimeContext.create_package(%{
      workspace_id: ws.id,
      user_id: user.id,
      session_id: session.id,
      runtime_target: "executor",
      budget_cents_allocated: 1000,
      scopes: ["mcp:access"],
      payload: %{"task" => "isolation test"}
    })
  end
end
