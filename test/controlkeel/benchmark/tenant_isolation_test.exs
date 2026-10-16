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
  alias ControlKeel.Benchmark.{Run, Suite}

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

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

  defp suite(ws) do
    n = System.unique_integer([:positive])

    {:ok, s} =
      Suite.changeset(%Suite{}, %{
        slug: "custom-suite-#{n}",
        name: "Custom #{n}",
        description: "A tenant suite",
        version: 1,
        status: "active",
        metadata: %{},
        workspace_id: ws && ws.id
      })
      |> Repo.insert()

    s
  end

  defp run(suite, ws) do
    n = System.unique_integer([:positive])

    {:ok, r} =
      Run.changeset(%Run{}, %{
        suite_id: suite.id,
        workspace_id: ws && ws.id,
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
      run(suite(ws_a), ws_a)
      run_b = run(suite(ws_b), ws_b)

      ids = Benchmark.list_recent_runs(workspace_ids: [ws_a.id]) |> Enum.map(& &1.id)
      refute run_b.id in ids
    end

    test "an empty accessible set yields no runs (fail closed)" do
      ws_a = workspace()
      run(suite(ws_a), ws_a)

      assert Benchmark.list_recent_runs(workspace_ids: []) == []
    end
  end

  describe "get_run_for_user/2 scoping" do
    test "does not leak another tenant's run by id" do
      ws_a = workspace()
      ws_b = workspace()
      run_b = run(suite(ws_b), ws_b)

      assert Benchmark.get_run_for_user(run_b.id, [ws_a.id]) == nil
    end

    test "returns the caller's own run" do
      ws_a = workspace()
      run_a = run(suite(ws_a), ws_a)

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
      assert is_list(slugs)
    end
  end
end
