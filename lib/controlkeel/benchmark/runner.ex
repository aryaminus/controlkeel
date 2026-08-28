defmodule ControlKeel.Benchmark.Runner do
  @moduledoc false

  alias ControlKeel.Benchmark.Scenario
  alias ControlKeel.Benchmark.SubjectLoader
  alias ControlKeel.Benchmark.Subjects.{ControlKeelProxy, ControlKeelValidate, Shell}
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Scanner.Finding
  alias ControlKeel.Utils

  def execute(scenarios, subjects, opts \\ []) when is_list(scenarios) and is_list(subjects) do
    Enum.flat_map(subjects, fn subject ->
      Enum.map(scenarios, fn scenario ->
        scenario
        |> run_subject(subject, opts)
        |> Map.merge(%{
          subject: subject["id"],
          subject_type: subject["type"],
          scenario_id: scenario.id
        })
      end)
    end)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "controlkeel_validate"} = subject, opts) do
    finalize(ControlKeelValidate.run(scenario, subject, opts), scenario)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "controlkeel_proxy"} = subject, opts) do
    finalize(ControlKeelProxy.run(scenario, subject, opts), scenario)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "null_policy_baseline"} = subject, _opts) do
    finalize(ungoverned_outcome(subject), scenario)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "shell"} = subject, opts) do
    finalize(Shell.run(scenario, subject, opts), scenario)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "manual_import"} = subject, _opts) do
    finalize(pending_outcome("awaiting_import", subject), scenario)
  end

  def run_subject(%Scenario{} = scenario, subject, _opts) do
    finalize(pending_outcome("skipped_unconfigured", subject), scenario)
  end

  def import_subject_result(%Scenario{} = scenario, attrs) when is_map(attrs) do
    content = Map.get(attrs, "content") || Map.get(attrs, :content)
    path = Map.get(attrs, "path") || Map.get(attrs, :path) || scenario.path
    kind = Map.get(attrs, "kind") || Map.get(attrs, :kind) || scenario.kind

    duration_ms =
      normalize_duration(Map.get(attrs, "duration_ms") || Map.get(attrs, :duration_ms))

    metadata = Map.get(attrs, "metadata") || Map.get(attrs, :metadata) || %{}

    result =
      case CkValidate.call(%{
             "content" => content,
             "path" => path,
             "kind" => kind,
             "domain_pack" => get_in(scenario.metadata || %{}, ["domain_pack"])
           }) do
        {:ok, public_result} ->
          outcome_from_public_result("completed", public_result, duration_ms, %{
            "runner" => "manual_import"
          })

        {:error, reason} ->
          error_outcome("failed", inspect(reason), duration_ms)
      end

    finalize(
      merge_payload(result, %{
        "payload" =>
          Map.merge(result["payload"], %{
            "import" => %{
              "content" => content,
              "path" => path,
              "kind" => kind,
              "metadata" => metadata
            }
          }),
        "metadata" =>
          Map.merge(result["metadata"], %{
            "import_metadata" => Utils.stringify_keys_deep(metadata)
          })
      }),
      scenario
    )
  end

  def outcome_from_public_result(status, result, latency_ms, metadata) do
    findings = Map.get(result, "findings", [])

    %{
      "status" => status,
      "decision" => Map.get(result, "decision"),
      "findings_count" => length(findings),
      "latency_ms" => latency_ms,
      "metadata" => metadata,
      "payload" => %{
        "allowed" => Map.get(result, "allowed"),
        "summary" => Map.get(result, "summary"),
        "findings" => findings,
        "scanned_at" => Map.get(result, "scanned_at")
      }
    }
  end

  def outcome_from_scan_result(status, result, latency_ms, metadata) do
    findings = Enum.map(result.findings, &Finding.to_map/1)

    %{
      "status" => status,
      "decision" => result.decision,
      "findings_count" => length(findings),
      "latency_ms" => latency_ms,
      "metadata" => metadata,
      "payload" => %{
        "allowed" => result.allowed,
        "summary" => result.summary,
        "findings" => findings
      }
    }
  end

  def pending_outcome(status, subject) do
    %{
      "status" => status,
      "decision" => nil,
      "findings_count" => 0,
      "latency_ms" => nil,
      "metadata" => %{
        "runner" => subject["type"],
        "label" => subject["label"],
        "configured" => subject["configured"] || false
      },
      "payload" => %{
        "summary" => pending_summary(status, subject),
        "findings" => []
      }
    }
  end

  def ungoverned_outcome(subject) do
    %{
      "status" => "completed",
      "decision" => "allow",
      "findings_count" => 0,
      "latency_ms" => 0,
      "metadata" => %{
        "runner" => subject["type"],
        "label" => subject["label"],
        "configured" => true,
        "comparison_role" => "null_policy_baseline",
        "input_tokens" => 0,
        "output_tokens" => 0,
        "total_tokens" => 0,
        "cost_cents" => 0
      },
      "payload" => %{
        "summary" =>
          "Null baseline: no ControlKeel policy gate is applied, so the artifact proceeds unchanged.",
        "findings" => []
      }
    }
  end

  def error_outcome(status, reason, latency_ms) do
    %{
      "status" => status,
      "decision" => nil,
      "findings_count" => 0,
      "latency_ms" => latency_ms,
      "metadata" => %{"runner" => "benchmark", "reason" => reason},
      "payload" => %{"summary" => reason, "findings" => []}
    }
  end

  def merge_payload(base, attrs) do
    payload = Map.merge(base["payload"] || %{}, attrs["payload"] || %{})
    metadata = Map.merge(base["metadata"] || %{}, attrs["metadata"] || %{})

    base
    |> Map.merge(Map.drop(attrs, ["payload", "metadata"]))
    |> Map.put("payload", payload)
    |> Map.put("metadata", metadata)
  end

  def scan_generated_output(stdout, output_dir, scenario, output_mode) do
    artifacts =
      case output_files(output_dir) do
        [] ->
          stdout_artifacts(stdout, scenario, output_mode)

        files ->
          Enum.map(files, fn file ->
            %{
              "content" => File.read!(file),
              "path" => Path.relative_to(file, output_dir),
              "kind" => scenario.kind,
              "domain_pack" => get_in(scenario.metadata || %{}, ["domain_pack"])
            }
          end)
      end

    case artifacts do
      [] ->
        %{
          "status" => "failed",
          "decision" => nil,
          "findings_count" => 0,
          "latency_ms" => nil,
          "metadata" => %{"runner" => "shell"},
          "payload" => %{
            "summary" => "No generated output found.",
            "findings" => [],
            "artifacts" => []
          }
        }

      _ ->
        scan_artifacts(artifacts)
    end
  end

  def output_files(output_dir) do
    Path.join(output_dir, "**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(Path.basename(&1) in [".controlkeel_metrics.json", "host-events.jsonl"]))
  end

  def subject_ids_from_input(nil), do: SubjectLoader.default_subject_ids()
  def subject_ids_from_input(value) when is_list(value), do: Enum.map(value, &to_string/1)

  def subject_ids_from_input(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> SubjectLoader.default_subject_ids()
      subjects -> subjects
    end
  end

  def subject_ids_from_input(_value), do: SubjectLoader.default_subject_ids()

  defp scan_artifacts(artifacts) do
    results =
      Enum.map(artifacts, fn artifact ->
        case CkValidate.call(artifact) do
          {:ok, result} ->
            result

          {:error, reason} ->
            %{
              "allowed" => false,
              "decision" => "block",
              "summary" => inspect(reason),
              "findings" => []
            }
        end
      end)

    findings =
      results
      |> Enum.flat_map(&Map.get(&1, "findings", []))
      |> Enum.uniq_by(fn finding ->
        {finding["rule_id"], get_in(finding, ["location", "path"]),
         get_in(finding, ["metadata", "matched_text_redacted"])}
      end)

    decision = strongest_decision(results)

    %{
      "status" => "completed",
      "decision" => decision,
      "findings_count" => length(findings),
      "latency_ms" => nil,
      "metadata" => %{"runner" => "shell"},
      "payload" => %{
        "summary" => summarize(decision, findings),
        "findings" => findings,
        "artifacts" => artifacts
      }
    }
  end

  defp stdout_artifacts(stdout, scenario, _output_mode) when is_binary(stdout) do
    trimmed = String.trim(stdout)

    if trimmed == "" do
      []
    else
      [
        %{
          "content" => stdout,
          "path" => scenario.path || "stdout.txt",
          "kind" => scenario.kind || "text",
          "domain_pack" => get_in(scenario.metadata || %{}, ["domain_pack"])
        }
      ]
    end
  end

  defp stdout_artifacts(_stdout, _scenario, _output_mode), do: []

  defp finalize(outcome, %Scenario{} = scenario) do
    actual_rules =
      outcome["payload"]
      |> Map.get("findings", [])
      |> Enum.map(& &1["rule_id"])
      |> MapSet.new()

    expected_rules = MapSet.new(scenario.expected_rules || [])

    rules_match =
      expected_rules == MapSet.new() or
        Enum.all?(expected_rules, fn rule_id -> MapSet.member?(actual_rules, rule_id) end)

    decision_match =
      case scenario.expected_decision do
        nil -> true
        "" -> true
        decision -> outcome["decision"] == decision
      end

    matched = rules_match and decision_match

    outcome
    |> Map.put("matched_expected", matched)
    |> Map.put("severity_weight", severity_weight(scenario))
    |> Map.put("weighted_score", if(matched, do: severity_weight(scenario), else: 0.0))
    |> maybe_apply_llm_judge(scenario, matched)
  end

  # eval_mode=llm_judge: run the judge and record its verdict. The judge only
  # OVERRIDES matched_expected for scenarios with no deterministic signal
  # (empty expected_rules and blank expected_decision) — otherwise it is
  # advisory metadata and deterministic matching stays authoritative.
  defp maybe_apply_llm_judge(outcome, scenario, deterministic_matched) do
    if get_in(scenario.metadata || %{}, ["eval_mode"]) == "llm_judge" do
      case ControlKeel.Benchmark.LlmJudge.judge(scenario, outcome) do
        {:ok, verdict} ->
          matched =
            if ControlKeel.Benchmark.LlmJudge.judge_decides?(scenario) do
              verdict.verdict == "pass"
            else
              deterministic_matched
            end

          outcome
          |> Map.put("matched_expected", matched)
          |> Map.put("weighted_score", if(matched, do: severity_weight(scenario), else: 0.0))
          |> Map.update("metadata", %{}, fn meta ->
            meta
            |> Map.put("llm_judge", %{
              "verdict" => verdict.verdict,
              "score" => verdict.score,
              "rationale" => verdict.rationale
            })
          end)

        {:error, reason} ->
          outcome
          |> Map.update("metadata", %{}, &Map.put(&1, "llm_judge_error", to_string(reason)))
      end
    else
      outcome
    end
  end

  defp severity_weight(%{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "risk_tier") || Map.get(metadata, "riskTier") do
      "critical" -> 3.0
      "high" -> 2.0
      "moderate" -> 1.2
      "medium" -> 1.0
      "low" -> 0.5
      "none" -> 0.3
      _ -> 1.0
    end
  end

  defp severity_weight(_scenario), do: 1.0

  defp normalize_duration(value) when is_integer(value) and value >= 0, do: value

  defp normalize_duration(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp normalize_duration(_value), do: 0

  defp summarize("block", findings), do: "Blocked #{length(findings)} finding(s)."
  defp summarize("warn", findings), do: "Warnings detected (#{length(findings)})."
  defp summarize(_decision, _findings), do: "No issues detected."

  defp strongest_decision(results) do
    decisions = Enum.map(results, &Map.get(&1, "decision"))

    cond do
      "block" in decisions -> "block"
      "warn" in decisions -> "warn"
      true -> "allow"
    end
  end

  defp pending_summary("awaiting_import", subject),
    do: "#{subject["label"] || subject["id"]} is awaiting imported benchmark output."

  defp pending_summary("skipped_unconfigured", subject),
    do:
      "#{subject["label"] || subject["id"]} is not configured in controlkeel/benchmark_subjects.json."

  defp pending_summary(status, subject),
    do: "#{subject["label"] || subject["id"]} is in #{status} state."
end
