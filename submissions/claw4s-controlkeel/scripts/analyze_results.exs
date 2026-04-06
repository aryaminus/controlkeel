defmodule Claw4SControlKeelAnalysis do
  @moduledoc false

  def run([vibe_path, benign_path, output_dir]) do
    File.mkdir_p!(output_dir)

    vibe = vibe_path |> read_export() |> summarize_suite()
    benign = benign_path |> read_export() |> summarize_suite()

    metrics = %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      suites: [vibe, benign]
    }

    summary = markdown_summary(vibe, benign)
    table = latex_table(vibe, benign)

    File.write!(Path.join(output_dir, "metrics.json"), Jason.encode!(metrics, pretty: true))
    File.write!(Path.join(output_dir, "summary.md"), summary)
    File.write!(Path.join(output_dir, "results_table.tex"), table)

    IO.puts(summary)
  end

  def run(_args) do
    IO.puts("""
    Usage:
      mix run submissions/claw4s-controlkeel/scripts/analyze_results.exs \
        <vibe_export_log> <benign_export_log> <output_dir>
    """)

    System.halt(1)
  end

  defp read_export(path) do
    path
    |> File.read!()
    |> extract_json_body()
    |> Jason.decode!()
  end

  defp extract_json_body(contents) do
    contents
    |> String.split("\n")
    |> Enum.drop_while(&(not String.starts_with?(&1, "{")))
    |> Enum.join("\n")
  end

  defp summarize_suite(%{"run" => run, "results" => results}) do
    classification = run["classification"] || %{}

    positives =
      results
      |> Enum.filter(&(&1["decision"] != "allow"))
      |> Enum.map(&Map.take(&1, ["scenario_slug", "scenario_name", "decision", "findings_count", "matched_expected"]))

    misses =
      results
      |> Enum.filter(&(&1["matched_expected"] == false and &1["decision"] == "allow"))
      |> Enum.map(& &1["scenario_slug"])

    partials =
      results
      |> Enum.filter(&(&1["matched_expected"] == false and &1["decision"] != "allow"))
      |> Enum.map(& &1["scenario_slug"])

    clean =
      results
      |> Enum.filter(&(&1["decision"] == "allow"))
      |> Enum.map(& &1["scenario_slug"])

    %{
      suite_slug: get_in(run, ["suite", "slug"]),
      suite_name: get_in(run, ["suite", "name"]),
      total_scenarios: run["total_scenarios"],
      catch_rate: run["catch_rate"],
      block_rate: run["block_rate"],
      expected_rule_hit_rate: run["expected_rule_hit_rate"],
      median_latency_ms: run["median_latency_ms"],
      average_overhead_percent: run["average_overhead_percent"],
      caught_count: run["caught_count"],
      blocked_count: run["blocked_count"],
      positive_scenarios: classification["positive_scenarios"],
      negative_scenarios: classification["negative_scenarios"],
      true_positives: classification["true_positives"],
      true_negatives: classification["true_negatives"],
      false_positives: classification["false_positives"],
      false_negatives: classification["false_negatives"],
      tpr: classification["tpr"],
      fpr: classification["fpr"],
      positives: positives,
      misses: misses,
      partials: partials,
      clean: clean
    }
  end

  defp markdown_summary(vibe, benign) do
    """
    # ControlKeel Claw4S Benchmark Summary

    ## Aggregate Metrics

    | Suite | Scenarios | Catch rate | Block rate | TPR | FPR | Expected-rule hit rate | Median latency (ms) |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    | `#{vibe.suite_slug}` | #{vibe.total_scenarios} | #{percent_md(vibe.catch_rate)} | #{percent_md(vibe.block_rate)} | #{ratio(vibe.tpr)} | #{ratio(vibe.fpr)} | #{percent_md(vibe.expected_rule_hit_rate)} | #{vibe.median_latency_ms} |
    | `#{benign.suite_slug}` | #{benign.total_scenarios} | #{percent_md(benign.catch_rate)} | #{percent_md(benign.block_rate)} | #{ratio(benign.tpr)} | #{ratio(benign.fpr)} | #{percent_md(benign.expected_rule_hit_rate)} | #{benign.median_latency_ms} |

    ## Positive Suite Notes

    - True positives: #{vibe.true_positives} of #{vibe.positive_scenarios}
    - False negatives: #{vibe.false_negatives}
    - Partial detections (flagged but not matched to the expected gate): #{list_or_none(vibe.partials)}
    - Complete misses (allowed when the expected outcome was stricter): #{list_or_none(vibe.misses)}

    ## Benign Suite Notes

    - True negatives: #{benign.true_negatives} of #{benign.negative_scenarios}
    - False positives: #{benign.false_positives}
    - Flagged benign scenarios: #{list_or_none(Enum.map(benign.positives, & &1["scenario_slug"]))}
    - Clean benign scenarios: #{list_or_none(benign.clean)}

    ## Interpretation

    - The current built-in validator catches several high-salience risky patterns, but it does not cover the entire positive suite.
    - The benign suite still produces measurable false positives, which is useful evidence for calibration work rather than a reason to hide the benchmark.
    - Average overhead in both runs remained #{percent_md(vibe.average_overhead_percent)} / #{percent_md(benign.average_overhead_percent)}, because this benchmark compares the validator path to itself rather than to an external subject.
    """
    |> String.trim_trailing()
  end

  defp latex_table(vibe, benign) do
    """
    \\begin{tabular}{lrrrrrr}
    \\toprule
    Suite & N & Catch & Block & TPR & FPR & Rule hit \\\\
    \\midrule
    \\texttt{#{vibe.suite_slug}} & #{vibe.total_scenarios} & #{percent_tex(vibe.catch_rate)} & #{percent_tex(vibe.block_rate)} & #{ratio(vibe.tpr)} & #{ratio(vibe.fpr)} & #{percent_tex(vibe.expected_rule_hit_rate)} \\\\
    \\texttt{#{benign.suite_slug}} & #{benign.total_scenarios} & #{percent_tex(benign.catch_rate)} & #{percent_tex(benign.block_rate)} & #{ratio(benign.tpr)} & #{ratio(benign.fpr)} & #{percent_tex(benign.expected_rule_hit_rate)} \\\\
    \\bottomrule
    \\end{tabular}
    """
    |> String.trim_trailing()
  end

  defp percent_md(nil), do: "--"
  defp percent_md(value) when is_integer(value), do: "#{value}.0%"
  defp percent_md(value) when is_float(value), do: "#{:erlang.float_to_binary(value, decimals: 1)}%"

  defp percent_tex(nil), do: "--"
  defp percent_tex(value) when is_integer(value), do: "#{value}.0\\%"
  defp percent_tex(value) when is_float(value), do: "#{:erlang.float_to_binary(value, decimals: 1)}\\%"

  defp ratio(nil), do: "--"
  defp ratio(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp ratio(value), do: to_string(value)

  defp list_or_none([]), do: "none"
  defp list_or_none(items), do: Enum.join(items, ", ")
end

Claw4SControlKeelAnalysis.run(System.argv())
