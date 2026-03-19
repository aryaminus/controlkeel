defmodule Mix.Tasks.Ck.Demo do
  use Mix.Task

  @shortdoc "Seeds a demo session showing ControlKeel detecting a hardcoded secret"

  @moduledoc """
  Creates a demo mission that walks through the core ControlKeel detection loop:

    1. Creates a governed session for a healthcare project
    2. Runs ck_validate with content containing a hardcoded API key
    3. Reports the findings detected and the Mission Control URL

  Usage:

      mix ck.demo [--host http://localhost:4000]

  """

  alias ControlKeel.Benchmark

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
             "scenario_slugs" => scenario_slugs
           }) do
      report_benchmark(shell, run, host)
    else
      {:error, reason} ->
        Mix.raise("Demo failed: #{inspect(reason)}")
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
    shell.info("  #{host}/benchmarks/runs/#{run.id}")
    shell.info("  #{host}/benchmarks")
    shell.info("")
    shell.info("  Export JSON:")
    shell.info("    #{host}/api/v1/benchmarks/runs/#{run.id}")
    shell.info("")
  end
end
