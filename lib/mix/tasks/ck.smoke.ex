defmodule Mix.Tasks.Ck.Smoke do
  use Mix.Task

  @shortdoc "Runs the built-in governance benchmark smoke check"

  @moduledoc """
  Runs a built-in governance smoke check through the benchmark engine:

    1. Selects a built-in governance benchmark scenario
    2. Runs ck_validate through the benchmark engine
    3. Reports the findings detected and the benchmark URL

  Usage:

      mix ck.smoke [--host http://localhost:4000]

  """

  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  # Smoke runs are workspace-owned like every CLI/API run (benchmarks issue,
  # slice 1). The smoke check targets the default workspace, provisioning it
  # via LocalDefaults (find-or-create, boot-seed source of truth) so a fresh
  # local database never dead-ends the smoke check.
  defp smoke_workspace_id do
    case ControlKeel.Bootstrap.LocalDefaults.ensure() do
      {:ok, {_org, workspace}} when workspace != nil ->
        workspace.id

      {:ok, nil} ->
        raise ArgumentError,
              "mix ck.smoke runs only in local mode — remote modes have no default workspace."

      {:error, reason} ->
        raise ArgumentError, "Could not provision the default workspace: #{inspect(reason)}"
    end
  end

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [host: :string, scenario: :integer])
    host = Keyword.get(opts, :host, "http://localhost:4000")
    scenario_idx = Keyword.get(opts, :scenario)

    shell = Mix.shell()
    shell.info("")
    shell.info("ControlKeel Benchmark — vibe_failures_v1")
    shell.info(String.duplicate("─", 64))

    scenario_slugs =
      if scenario_idx do
        case Benchmark.get_suite_by_slug("vibe_failures_v1") do
          nil ->
            []

          suite ->
            [
              Enum.at(Enum.sort_by(suite.scenarios, & &1.position), scenario_idx - 1) ||
                hd(suite.scenarios)
            ]
        end
        |> Enum.map(& &1.slug)
      else
        []
      end

    with {:ok, run} <-
           Benchmark.run_suite(%{
             "suite" => "vibe_failures_v1",
             "subjects" => "controlkeel_validate",
             "baseline_subject" => "controlkeel_validate",
             "scenario_slugs" => scenario_slugs,
             "workspace_id" => smoke_workspace_id()
           }) do
      report_benchmark(shell, run, host)
    else
      {:error, reason} ->
        Mix.raise("Smoke check failed: #{inspect(reason)}")
    end
  end

  defp report_benchmark(shell, run, host) do
    total = length(run.results)
    caught = run.caught_count
    blocked = run.blocked_count
    total_findings = Enum.sum(Enum.map(run.results, & &1.findings_count))
    catch_rate = run.catch_rate

    shell.info("")
    shell.info(String.duplicate("─", 64))
    shell.info("BENCHMARK RESULTS")
    shell.info(String.duplicate("─", 64))
    shell.info("")
    shell.info("  Scenarios evaluated:  #{total}")
    shell.info("  Scenarios with finds: #{caught}/#{total}  (#{catch_rate}% catch rate)")
    shell.info("  Hard blocks:          #{blocked}")
    shell.info("  Total findings:       #{total_findings}")
    shell.info("")

    Enum.each(run.results, fn r ->
      icon =
        cond do
          r.decision == "block" -> "✗ BLOCKED"
          r.findings_count > 0 -> "⚠ WARNED "
          true -> "✓ PASSED "
        end

      shell.info("  #{icon}  #{r.scenario.name}")
    end)

    shell.info("")
    shell.info(String.duplicate("─", 64))
    shell.info("REVIEW IN MISSION CONTROL")
    shell.info("")
    workspace = Mission.get_workspace!(run.workspace_id)
    workspace = Repo.preload(workspace, :org)

    shell.info(
      "  #{host}/#{workspace.org.slug}/workspaces/#{workspace.slug}/benchmarks/runs/#{run.id}"
    )

    shell.info("  #{host}/#{workspace.org.slug}/workspaces/#{workspace.slug}/benchmarks")
    shell.info("")
    shell.info("  Export JSON:")

    shell.info(
      "    #{host}/api/v1/#{workspace.org.slug}/workspaces/#{workspace.slug}/benchmarks/runs/#{run.id}"
    )

    shell.info("")
  end
end
