defmodule ControlKeel.Benchmark.Runner do
  @moduledoc false

  alias ControlKeel.Benchmark.Scenario
  alias ControlKeel.Benchmark.SubjectLoader
  alias ControlKeel.Benchmark.Subjects.{ControlKeelProxy, ControlKeelValidate, Shell}
  alias ControlKeel.MCP.Tools.CkValidate

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

  def run_subject(%Scenario{} = scenario, %{"type" => "shell"} = subject, opts) do
    finalize(Shell.run(scenario, subject, opts), scenario)
  end

  def run_subject(%Scenario{} = scenario, %{"type" => "manual_import"} = subject, _opts) do
    finalize(placeholder_outcome("awaiting_import", subject), scenario)
  end

  def run_subject(%Scenario{} = scenario, subject, _opts) do
    finalize(placeholder_outcome("skipped_unconfigured", subject), scenario)
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
          Map.merge(result["metadata"], %{"import_metadata" => stringify_keys(metadata)})
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
    findings = Enum.map(result.findings, &finding_to_map/1)

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

  def placeholder_outcome(status, subject) do
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
        "summary" => placeholder_summary(status, subject),
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
              "decision" => "allow",
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

    Map.put(outcome, "matched_expected", rules_match and decision_match)
  end

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

  defp placeholder_summary("awaiting_import", subject),
    do: "#{subject["label"] || subject["id"]} is awaiting imported benchmark output."

  defp placeholder_summary("skipped_unconfigured", subject),
    do:
      "#{subject["label"] || subject["id"]} is not configured in controlkeel/benchmark_subjects.json."

  defp placeholder_summary(status, subject),
    do: "#{subject["label"] || subject["id"]} is in #{status} state."

  defp finding_to_map(finding) do
    %{
      "id" => finding.id,
      "severity" => finding.severity,
      "category" => finding.category,
      "rule_id" => finding.rule_id,
      "decision" => finding.decision,
      "plain_message" => finding.plain_message,
      "location" => finding.location,
      "metadata" => finding.metadata
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp stringify_keys(value), do: value
end
