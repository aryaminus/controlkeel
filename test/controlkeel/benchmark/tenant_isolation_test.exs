defmodule ControlKeel.Benchmark.TenantIsolationTest do
  @moduledoc """
  Benchmarks carry a `workspace_id` discriminator so tenants cannot read each
  other's suites or runs (issue #248).

  Model: shared schema with a tenant column — the standard B2B SaaS default.
  Built-in suites (workspace_id NULL) are platform content every tenant may
  run; runs are always tenant-scoped.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Benchmark
  alias ControlKeel.Benchmark.{Run, Scenario, Suite}

  # Scoping is opt-driven (explicit workspace_ids / workspace_id attrs), not
  # runtime-mode-driven, so these tests deliberately avoid mutating
  # Application env: every scope boundary below is exercised directly.

  defp workspace do
    slug = "bmws-#{System.unique_integer([:positive])}"

    {:ok, ws} =
      ControlKeel.Mission.create_workspace(%{
        name: "Bench WS",
        slug: slug,
        agent: "claude",
        budget_cents: 1000,
        compliance_profile: "OWASP",
        industry: "web",
        status: "active"
      })

    ws
  end

  defp suite(ws, slug \\ nil) do
    n = System.unique_integer([:positive])

    {:ok, s} =
      Suite.changeset(%Suite{}, %{
        slug: slug || "custom-suite-#{n}",
        name: "Custom #{n}",
        description: "A tenant suite",
        version: 1,
        status: "active",
        metadata: %{},
        workspace_id: ws.id
      })
      |> Repo.insert()

    s
  end

  defp run(suite, workspace_id) do
    n = System.unique_integer([:positive])

    {:ok, r} =
      Run.changeset(%Run{}, %{
        suite_id: suite.id,
        workspace_id: workspace_id,
        status: "completed",
        subjects: ["subject-#{n}"],
        baseline_subject: "subject-#{n}",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        total_scenarios: 1,
        caught_count: 1,
        blocked_count: 0,
        catch_rate: 1.0,
        metadata: %{}
      })
      |> Repo.insert()

    r
  end

  describe "list_recent_runs/1 scoping" do
    test "returns only the caller's runs" do
      ws_a = workspace()
      ws_b = workspace()
      run(suite(ws_a), ws_a.id)
      run_b = run(suite(ws_b), ws_b.id)

      ids = Benchmark.list_recent_runs(workspace_ids: [ws_a.id]) |> Enum.map(& &1.id)
      refute run_b.id in ids
    end

    test "an empty accessible set yields no runs (fail closed)" do
      ws_a = workspace()
      run(suite(ws_a), ws_a.id)

      assert Benchmark.list_recent_runs(workspace_ids: []) == []
    end
  end

  describe "get_run_for_user/2 scoping" do
    test "does not leak another tenant's run by id" do
      ws_a = workspace()
      ws_b = workspace()
      run_b = run(suite(ws_b), ws_b.id)

      assert Benchmark.get_run_for_user(run_b.id, [ws_a.id]) == nil
    end

    test "returns the caller's own run" do
      ws_a = workspace()
      run_a = run(suite(ws_a), ws_a.id)

      found = Benchmark.get_run_for_user(run_a.id, [ws_a.id])
      assert found.id == run_a.id
    end
  end

  describe "list_suites/1 scoping" do
    test "includes platform (builtin) suites but not another tenant's custom suites" do
      ws_a = workspace()
      ws_b = workspace()
      mine = suite(ws_a)
      theirs = suite(ws_b)

      slugs = Benchmark.list_suites(workspace_ids: [ws_a.id]) |> Enum.map(& &1.slug)

      assert mine.slug in slugs
      refute theirs.slug in slugs
    end

    test "a caller with no workspaces still sees platform suites" do
      # Built-in platform suites are loaded by ensure_builtin_suites and remain
      # visible to everyone; tenant-created suites are not.
      slugs = Benchmark.list_suites(workspace_ids: []) |> Enum.map(& &1.slug)
      assert "vibe_failures_v1" in slugs
    end

    test "a platform (NULL workspace) run is invisible to workspace-scoped readers" do
      # Legacy/unscoped rows must not resurface through scoped reads.
      ws_a = workspace()
      orphan = run(suite(ws_a), nil)

      assert Benchmark.get_run_for_user(orphan.id, [ws_a.id]) == nil
      assert Benchmark.list_recent_runs(workspace_ids: [ws_a.id]) == []
    end
  end

  describe "run_suite/2 suite eligibility" do
    test "runs each workspace's suite when they share a slug" do
      workspace_a = workspace()
      workspace_b = workspace()
      suite_a = suite(workspace_a, "shared-suite")
      suite_b = suite(workspace_b, "shared-suite")

      for suite <- [suite_a, suite_b] do
        %Scenario{}
        |> Scenario.changeset(%{
          suite_id: suite.id,
          slug: "simple-check",
          name: "Simple check",
          category: "security",
          content: "true",
          expected_rules: ["example.rule"],
          expected_decision: "allow"
        })
        |> Repo.insert!()

        assert {:ok, run} =
                 Benchmark.run_suite(%{
                   "suite" => suite.slug,
                   "workspace_id" => suite.workspace_id,
                   "subjects" => "controlkeel_validate"
                 })

        assert run.suite_id == suite.id
        assert run.workspace_id == suite.workspace_id
      end
    end

    # The run path is guarded server-side (benchmark tenancy, #259 follow-up):
    # a workspace-stamped caller may execute platform suites or their own.
    test "rejects another tenant's suite with :suite_not_found and executes nothing" do
      ws_a = workspace()
      ws_b = workspace()
      theirs = suite(ws_b)

      assert {:error, :suite_not_found} =
               Benchmark.run_suite(%{
                 "suite" => theirs.slug,
                 "workspace_id" => ws_a.id,
                 "subjects" => "controlkeel_validate"
               })

      # Rejected before any run record (or scenario work) is created.
      assert Repo.aggregate(Run, :count, :id) == 0
    end

    test "allows the caller's own suite" do
      ws_a = workspace()
      mine = suite(ws_a)

      # The fixture suite has no scenarios, so a passing guard is observable
      # as the next pipeline error rather than :suite_not_found.
      assert {:error, :no_scenarios} =
               Benchmark.run_suite(%{
                 "suite" => mine.slug,
                 "workspace_id" => ws_a.id,
                 "subjects" => "controlkeel_validate"
               })
    end

    test "platform suites stay runnable from any workspace" do
      ws_a = workspace()

      # An unknown scenario filter proves the guard passed (NULL-workspace
      # platform suites are executable by every tenant) without running any
      # scenario work.
      assert {:error, :no_scenarios} =
               Benchmark.run_suite(%{
                 "suite" => "vibe_failures_v1",
                 "workspace_id" => ws_a.id,
                 "subjects" => "controlkeel_validate",
                 "scenario_slugs" => "no_such_scenario"
               })
    end
  end
end
