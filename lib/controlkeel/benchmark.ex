defmodule ControlKeel.Benchmark do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Benchmark.{
    BuiltinSuites,
    Metadata,
    Result,
    Run,
    Runner,
    Scenario,
    SubjectLoader,
    Suite
  }

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Repo

  @recent_runs_limit 12
  @busy_retry_backoff_ms [0, 1_000, 3_000, 7_000, 15_000]

  def list_suites(opts \\ []) do
    ensure_builtin_suites()
    include_internal = Keyword.get(opts, :include_internal, false)
    domain_pack = normalize_domain_pack_filter(Keyword.get(opts, :domain_pack))

    Suite
    |> order_by([suite], asc: suite.name)
    |> preload([:scenarios])
    |> Repo.all()
    |> maybe_exclude_internal(include_internal)
    |> maybe_filter_suites_by_domain(domain_pack)
  end

  def list_recent_runs(limit) when is_integer(limit) do
    list_recent_runs(limit: limit)
  end

  def list_recent_runs(opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, @recent_runs_limit)
    domain_pack = normalize_domain_pack_filter(Keyword.get(opts, :domain_pack))
    query_limit = if domain_pack, do: max(limit * 5, 50), else: limit

    Run
    |> order_by([run], desc: run.inserted_at)
    |> limit(^query_limit)
    |> preload([:suite, results: [scenario: []]])
    |> Repo.all()
    |> maybe_filter_runs_by_domain(domain_pack)
    |> Enum.take(limit)
  end

  def list_recent_runs, do: list_recent_runs(limit: @recent_runs_limit)

  def benchmark_summary(limit) when is_integer(limit) do
    benchmark_summary(limit: limit)
  end

  def benchmark_summary(opts) when is_list(opts) do
    runs = list_recent_runs(opts)
    total_suites = builtin_suite_count(Keyword.get(opts, :domain_pack))

    catch_rates = Enum.map(runs, & &1.catch_rate)
    overheads = Enum.reject(Enum.map(runs, & &1.average_overhead_percent), &is_nil/1)

    %{
      total_suites: total_suites,
      total_runs: length(runs),
      average_catch_rate: average(catch_rates),
      average_overhead_percent: average(overheads),
      latest_run: List.first(runs)
    }
  end

  def benchmark_summary, do: benchmark_summary(limit: @recent_runs_limit)

  def get_suite_by_slug(slug) when is_binary(slug) do
    ensure_builtin_suite(slug)

    Suite
    |> Repo.get_by(slug: slug)
    |> Repo.preload(:scenarios)
  end

  def get_run(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> get_run(parsed)
      _error -> nil
    end
  end

  def get_run(id) when is_integer(id) do
    Run
    |> Repo.get(id)
    |> preload_run()
  end

  def get_run!(id) when is_integer(id) do
    Run
    |> Repo.get!(id)
    |> preload_run()
  end

  def available_subjects(project_root \\ File.cwd!()) do
    SubjectLoader.builtin_subjects() ++ SubjectLoader.external_subjects(project_root)
  end

  def run_suite(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    ensure_builtin_suites()

    suite_slug = Map.get(attrs, "suite") || Map.get(attrs, :suite) || "vibe_failures_v1"

    domain_pack =
      normalize_domain_pack_filter(Map.get(attrs, "domain_pack") || Map.get(attrs, :domain_pack))

    scenario_slugs =
      normalize_scenario_slugs(
        Map.get(attrs, "scenario_slugs") || Map.get(attrs, :scenario_slugs)
      )

    subject_ids =
      Runner.subject_ids_from_input(Map.get(attrs, "subjects") || Map.get(attrs, :subjects))

    baseline_subject =
      Map.get(attrs, "baseline_subject") || Map.get(attrs, :baseline_subject) ||
        List.first(subject_ids)

    with %Suite{} = suite <- get_suite_by_slug(suite_slug) || {:error, :suite_not_found} do
      scenarios =
        suite.scenarios
        |> maybe_filter_scenarios(scenario_slugs)
        |> maybe_filter_scenarios_by_domain(domain_pack)
        |> Enum.sort_by(& &1.position)

      subjects = SubjectLoader.resolve(subject_ids, project_root)
      metadata = run_metadata(suite, subjects, project_root, domain_pack)

      with true <- scenarios != [] || {:error, :no_scenarios},
           {:ok, run} <-
             create_run_record(suite, scenarios, subject_ids, baseline_subject, metadata),
           result_attrs <- Runner.execute(scenarios, subjects, project_root: project_root),
           {:ok, _results} <- insert_results(run, result_attrs),
           {:ok, updated_run} <- recalculate_run(run.id) do
        {:ok, updated_run}
      end
    else
      {:error, :suite_not_found} -> {:error, :suite_not_found}
      {:error, :no_scenarios} -> {:error, :no_scenarios}
    end
  end

  def import_result(run_id, subject, attrs) when is_binary(subject) do
    with %Run{} = run <- get_run(run_id) || {:error, :not_found},
         scenario_slug when is_binary(scenario_slug) <-
           Map.get(attrs, "scenario_slug") || {:error, :scenario_slug_required},
         %Result{} = result <-
           find_result_for_import(run, subject, scenario_slug) || {:error, :result_not_found},
         %Scenario{} = scenario <- result.scenario,
         outcome <- Runner.import_subject_result(scenario, attrs),
         {:ok, _updated_result} <- update_result_from_outcome(result, outcome),
         {:ok, updated_run} <- recalculate_run(run.id) do
      {:ok, updated_run}
    else
      {:error, :scenario_slug_required} -> {:error, :scenario_slug_required}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :result_not_found} -> {:error, :result_not_found}
      nil -> {:error, :not_found}
    end
  end

  def export_run(run_id, format \\ "json")

  def export_run(run_id, format) when is_integer(run_id) or is_binary(run_id) do
    case get_run(run_id) do
      nil ->
        {:error, :not_found}

      run ->
        case format do
          "csv" -> {:ok, export_csv(run)}
          :csv -> {:ok, export_csv(run)}
          _ -> {:ok, Jason.encode!(run_export(run), pretty: true)}
        end
    end
  end

  def list_subjects_for_run(%Run{} = run) do
    run.subjects || []
  end

  def run_matrix(%Run{} = run) do
    scenario_ids =
      run.results
      |> Enum.map(& &1.scenario_id)
      |> MapSet.new()

    results_by_key =
      Map.new(run.results, fn result ->
        {{result.scenario.slug, result.subject}, result}
      end)

    %{
      subjects: run.subjects || [],
      scenarios:
        run.suite.scenarios
        |> Enum.filter(&MapSet.member?(scenario_ids, &1.id))
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn scenario ->
          %{
            scenario: scenario,
            results:
              Enum.map(run.subjects || [], fn subject ->
                results_by_key[{scenario.slug, subject}]
              end)
          }
        end)
    }
  end

  def run_detail_metrics(%Run{} = run) do
    results = run.results

    evaluated =
      Enum.filter(results, fn result ->
        result.status in ["completed", "failed", "timed_out"]
      end)

    matched_expected =
      Enum.count(evaluated, & &1.matched_expected)

    block_rate =
      case evaluated do
        [] -> 0.0
        _ -> Float.round(run.blocked_count / length(evaluated) * 100, 1)
      end

    expected_rule_hit_rate =
      case evaluated do
        [] -> 0.0
        _ -> Float.round(matched_expected / length(evaluated) * 100, 1)
      end

    classification = classification_metrics(run)

    %{
      block_rate: block_rate,
      expected_rule_hit_rate: expected_rule_hit_rate,
      evaluated_results: length(evaluated),
      classification: classification
    }
  end

  @doc """
  Computes OWASP-style classification metrics from run results.

  Uses `expected_decision` ground truth on each scenario:
  - Scenarios expecting "block" or "warn" are positive (should trigger findings)
  - Scenarios expecting "allow" or nil are negative (should NOT trigger findings)

  Returns TP, FP, TN, FN counts plus TPR, FPR, and Youden's J (TPR − FPR).
  """
  def classification_metrics(%Run{} = run) do
    evaluated =
      run.results
      |> Enum.filter(&(&1.status in ["completed", "failed", "timed_out"]))

    {positives, negatives} =
      Enum.split_with(evaluated, fn result ->
        result.scenario.expected_decision in ["block", "warn"]
      end)

    tp = Enum.count(positives, &(&1.findings_count > 0))
    fn_count = length(positives) - tp
    fp = Enum.count(negatives, &(&1.findings_count > 0))
    tn = length(negatives) - fp

    tpr = safe_rate(tp, tp + fn_count)
    fpr = safe_rate(fp, fp + tn)
    youdens_j = if is_nil(tpr) or is_nil(fpr), do: nil, else: Float.round(tpr - fpr, 3)

    %{
      true_positives: tp,
      false_positives: fp,
      true_negatives: tn,
      false_negatives: fn_count,
      tpr: tpr,
      fpr: fpr,
      youdens_j: youdens_j,
      positive_scenarios: length(positives),
      negative_scenarios: length(negatives)
    }
  end

  defp safe_rate(_numerator, 0), do: nil
  defp safe_rate(numerator, denominator), do: Float.round(numerator / denominator, 3)

  def domain_packs_for_suite(%Suite{} = suite) do
    suite.scenarios
    |> Enum.map(&get_in(&1.metadata || %{}, ["domain_pack"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def domain_packs_for_run(%Run{} = run) do
    run.results
    |> Enum.map(&get_in(&1.scenario.metadata || %{}, ["domain_pack"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def suite_eval_profile(%Suite{} = suite) do
    scenarios = suite.scenarios || []

    %{
      "scenario_count" => length(scenarios),
      "split_summary" => count_by(scenarios, &scenario_split/1),
      "category_summary" => count_by(scenarios, & &1.category),
      "behavior_tag_summary" =>
        scenarios
        |> Enum.flat_map(&scenario_behavior_tags/1)
        |> Enum.frequencies(),
      "curation_mode" =>
        get_in(suite.metadata || %{}, ["curation_mode"]) || "hand_curated_plus_trace_promoted"
    }
  end

  def run_eval_profile(%Run{} = run) do
    scenarios =
      run.results
      |> Enum.map(& &1.scenario)
      |> Enum.uniq_by(& &1.id)

    split_summary = count_by(scenarios, &scenario_split/1)

    curation_mode =
      get_in(run, [Access.key(:suite), Access.key(:metadata), "curation_mode"]) ||
        "hand_curated_plus_trace_promoted"

    behavior_tag_summary =
      scenarios
      |> Enum.flat_map(&scenario_behavior_tags/1)
      |> Enum.frequencies()

    profile = %{
      "scenario_count" => length(scenarios),
      "split_summary" => split_summary,
      "category_summary" => count_by(scenarios, & &1.category),
      "behavior_tag_summary" => behavior_tag_summary,
      "holdout_present" => Enum.any?(scenarios, &(scenario_split(&1) == "held_out")),
      "curation_mode" => curation_mode,
      "promotion_integrity" =>
        promotion_integrity_profile(%{
          "scenario_count" => length(scenarios),
          "split_summary" => split_summary,
          "behavior_tag_summary" => behavior_tag_summary,
          "classification" => classification_metrics(run),
          "curation_mode" => curation_mode
        })
    }

    Map.put(profile, "diagnostic_findings", integrity_findings(profile, %{"run_id" => run.id}))
  end

  def promotion_integrity_profile(profile) when is_map(profile) do
    split_summary = Map.get(profile, "split_summary") || %{}
    behavior_tag_summary = Map.get(profile, "behavior_tag_summary") || %{}
    classification = Map.get(profile, "classification") || %{}
    scenario_count = Map.get(profile, "scenario_count") || 0

    evidence_channels =
      []
      |> maybe_channel(scenario_count > 0, "scenarios")
      |> maybe_channel((split_summary["held_out"] || 0) > 0, "held_out")
      |> maybe_channel(map_size(behavior_tag_summary) >= 2, "behavior_tags")
      |> maybe_channel(not is_nil(classification["youdens_j"]), "classification")

    warnings =
      []
      |> maybe_integrity_warning(
        (split_summary["held_out"] || 0) > 0,
        "missing_holdout_evidence"
      )
      |> maybe_integrity_warning(
        map_size(behavior_tag_summary) >= 2,
        "low_behavior_diversity"
      )
      |> maybe_integrity_warning(
        not is_nil(classification["youdens_j"]),
        "missing_classification_evidence"
      )
      |> maybe_integrity_warning(
        length(evidence_channels) > 1,
        "single_score_promotion"
      )
      |> maybe_integrity_warning(
        has_trace_derived_scenarios?(profile),
        "eval_staleness"
      )

    %{
      "status" => if(warnings == [], do: "ready", else: "warn"),
      "evidence_channels" => Enum.reverse(evidence_channels),
      "warnings" => Enum.reverse(warnings)
    }
  end

  def integrity_findings(profile, attrs \\ %{}) when is_map(profile) do
    integrity = Map.get(profile, "promotion_integrity") || promotion_integrity_profile(profile)
    warnings = integrity["warnings"] || []

    Enum.map(warnings, fn warning ->
      %{
        "category" => "governance-product",
        "severity" => "medium",
        "rule_id" => "benchmarks.#{warning}",
        "title" => benchmark_integrity_title(warning),
        "plain_message" => benchmark_integrity_message(warning),
        "metadata" =>
          Map.merge(attrs, %{
            "diagnostic_source" => "benchmark_promotion_integrity",
            "promotion_integrity" => integrity
          })
      }
    end)
  end

  def scenario_behavior_tags(%Scenario{} = scenario) do
    metadata = scenario.metadata || %{}

    [
      scenario.category,
      metadata["domain_pack"],
      metadata["task_type"],
      metadata["artifact_type"],
      metadata["security_workflow_phase"],
      metadata["memory_sharing_strategy"],
      metadata["memory_surface"],
      metadata["retrieval_strategy"],
      metadata["compaction_strategy"],
      metadata["handoff_contract"],
      metadata["artifact_scope"],
      metadata["skill_detection"],
      metadata["token_snapshot"],
      metadata["observed_skill_reads"]
      | List.wrap(metadata["behavior_tags"])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp ensure_builtin_suites do
    Enum.each(BuiltinSuites.list(), &ensure_builtin_suite/1)
  end

  defp ensure_builtin_suite(slug) do
    with {:ok, payload} <- BuiltinSuites.load(slug) do
      expected_scenarios = payload["scenarios"] || []

      case Repo.get_by(Suite, slug: slug) |> Repo.preload(:scenarios) do
        %Suite{} = suite ->
          if builtin_suite_current?(suite, payload, expected_scenarios) do
            {:ok, suite}
          else
            sync_builtin_suite(payload, expected_scenarios)
          end

        _suite ->
          sync_builtin_suite(payload, expected_scenarios)
      end
    end
  end

  defp sync_scenarios(%Suite{} = suite, scenario_payloads) do
    existing =
      Scenario
      |> where([scenario], scenario.suite_id == ^suite.id)
      |> Repo.all()
      |> Map.new(fn scenario -> {scenario.slug, scenario} end)

    incoming_slugs = Enum.map(scenario_payloads, & &1["slug"])

    Enum.each(scenario_payloads, fn payload ->
      scenario =
        existing[payload["slug"]] ||
          %Scenario{}

      scenario
      |> Scenario.changeset(%{
        suite_id: suite.id,
        slug: payload["slug"],
        name: payload["name"],
        category: payload["category"],
        incident_label: payload["incident_label"],
        path: payload["path"],
        kind: payload["kind"] || "code",
        content: payload["content"],
        expected_rules: payload["expected_rules"] || [],
        expected_decision: payload["expected_decision"],
        position: payload["position"] || 0,
        split: payload["split"] || "public",
        metadata: Metadata.normalize_scenario_metadata(payload)
      })
      |> Repo.insert_or_update!()
    end)

    Scenario
    |> where([scenario], scenario.suite_id == ^suite.id and scenario.slug not in ^incoming_slugs)
    |> Repo.delete_all()
  end

  defp create_run_record(suite, scenarios, subject_ids, baseline_subject, metadata) do
    %Run{}
    |> Run.changeset(%{
      suite_id: suite.id,
      status: "running",
      baseline_subject: baseline_subject,
      subjects: subject_ids,
      started_at: now(),
      total_scenarios: length(scenarios),
      caught_count: 0,
      blocked_count: 0,
      catch_rate: 0.0,
      metadata: metadata
    })
    |> insert_with_busy_retry()
  end

  defp builtin_suite_count(domain_pack) do
    BuiltinSuites.list()
    |> Enum.reduce(0, fn slug, count ->
      case BuiltinSuites.load(slug) do
        {:ok, payload} ->
          if builtin_suite_matches_domain?(payload, domain_pack) do
            count + 1
          else
            count
          end

        _error ->
          count
      end
    end)
  end

  defp builtin_suite_matches_domain?(_payload, nil), do: true

  defp builtin_suite_matches_domain?(payload, domain_pack) do
    payload
    |> Map.get("scenarios", [])
    |> Enum.any?(fn scenario ->
      get_in(scenario, ["metadata", "domain_pack"]) == domain_pack
    end)
  end

  defp builtin_suite_current?(suite, payload, expected_scenarios) do
    suite.name == payload["name"] and
      suite.description == payload["description"] and
      suite.version == payload["version"] and
      suite.status == (payload["status"] || "active") and
      suite.metadata == (payload["metadata"] || %{}) and
      length(suite.scenarios) == length(expected_scenarios)
  end

  defp sync_builtin_suite(payload, expected_scenarios) do
    transaction_with_busy_retry(fn ->
      suite =
        Repo.get_by(Suite, slug: payload["slug"]) ||
          %Suite{}

      {:ok, suite} =
        suite
        |> Suite.changeset(%{
          slug: payload["slug"],
          name: payload["name"],
          description: payload["description"],
          version: payload["version"],
          status: payload["status"] || "active",
          metadata: payload["metadata"] || %{}
        })
        |> Repo.insert_or_update()

      sync_scenarios(suite, expected_scenarios)
      suite
    end)
  end

  defp transaction_with_busy_retry(operation, attempt \\ 0)

  defp transaction_with_busy_retry(operation, attempt) do
    Repo.transaction(operation)
  rescue
    error ->
      if busy_error?(error) and attempt < length(@busy_retry_backoff_ms) - 1 do
        Process.sleep(Enum.at(@busy_retry_backoff_ms, attempt + 1))
        transaction_with_busy_retry(operation, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp insert_with_busy_retry(changeset, attempt \\ 0)

  defp insert_with_busy_retry(changeset, attempt) do
    Repo.insert(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(@busy_retry_backoff_ms) - 1 do
        Process.sleep(Enum.at(@busy_retry_backoff_ms, attempt + 1))
        insert_with_busy_retry(changeset, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp update_with_busy_retry(changeset, attempt \\ 0)

  defp update_with_busy_retry(changeset, attempt) do
    Repo.update(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(@busy_retry_backoff_ms) - 1 do
        Process.sleep(Enum.at(@busy_retry_backoff_ms, attempt + 1))
        update_with_busy_retry(changeset, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp update_with_busy_retry!(changeset, attempt \\ 0)

  defp update_with_busy_retry!(changeset, attempt) do
    Repo.update!(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(@busy_retry_backoff_ms) - 1 do
        Process.sleep(Enum.at(@busy_retry_backoff_ms, attempt + 1))
        update_with_busy_retry!(changeset, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp busy_error?(error) do
    error
    |> Exception.message()
    |> String.contains?("Database busy")
  end

  defp maybe_exclude_internal(suites, true), do: suites
  defp maybe_exclude_internal(suites, false), do: Enum.reject(suites, &Metadata.suite_internal?/1)

  defp maybe_filter_suites_by_domain(suites, nil), do: suites

  defp maybe_filter_suites_by_domain(suites, domain_pack) do
    Enum.filter(suites, fn suite ->
      Enum.any?(suite.scenarios, fn scenario ->
        get_in(scenario.metadata || %{}, ["domain_pack"]) == domain_pack
      end)
    end)
  end

  defp maybe_filter_runs_by_domain(runs, nil), do: runs

  defp maybe_filter_runs_by_domain(runs, domain_pack) do
    Enum.filter(runs, fn run ->
      Enum.any?(run.results, fn result ->
        get_in(result.scenario.metadata || %{}, ["domain_pack"]) == domain_pack
      end)
    end)
  end

  defp insert_results(run, result_attrs) do
    Enum.reduce_while(result_attrs, {:ok, []}, fn attrs, {:ok, acc} ->
      attrs =
        attrs
        |> stringify_keys()
        |> Map.put("run_id", run.id)
        |> Map.put_new("payload", %{})
        |> Map.put_new("metadata", %{})

      case %Result{} |> Result.changeset(attrs) |> insert_with_busy_retry() do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp recalculate_run(run_id) do
    run = get_run(run_id)
    overheads = calculate_overheads(run)

    Enum.each(run.results, fn result ->
      case Map.fetch(overheads, result.id) do
        {:ok, overhead_percent} ->
          result
          |> Result.changeset(%{overhead_percent: overhead_percent})
          |> update_with_busy_retry!()

        :error ->
          :ok
      end
    end)

    refreshed = get_run!(run_id)
    aggregates = aggregate_run(refreshed)

    refreshed
    |> Run.changeset(aggregates)
    |> update_with_busy_retry()
  end

  defp aggregate_run(%Run{} = run) do
    results = run.results

    evaluated =
      Enum.filter(results, fn result ->
        result.status in ["completed", "failed", "timed_out"]
      end)

    caught_count = Enum.count(evaluated, &(&1.findings_count > 0))
    blocked_count = Enum.count(evaluated, &(&1.decision == "block"))
    latencies = Enum.reject(Enum.map(evaluated, & &1.latency_ms), &is_nil/1)
    overheads = Enum.reject(Enum.map(results, & &1.overhead_percent), &is_nil/1)

    %{
      status: aggregate_status(results),
      finished_at: now(),
      caught_count: caught_count,
      blocked_count: blocked_count,
      catch_rate: percentage(caught_count, length(evaluated)),
      median_latency_ms: median(latencies),
      average_overhead_percent: average(overheads)
    }
  end

  defp calculate_overheads(%Run{} = run) do
    baseline_latencies =
      run.results
      |> Enum.filter(&(&1.subject == run.baseline_subject))
      |> Map.new(fn result -> {result.scenario_id, result.latency_ms} end)

    Enum.reduce(run.results, %{}, fn result, acc ->
      overhead =
        cond do
          result.subject == run.baseline_subject and is_integer(result.latency_ms) ->
            0.0

          is_integer(result.latency_ms) and is_integer(baseline_latencies[result.scenario_id]) and
              baseline_latencies[result.scenario_id] > 0 ->
            Float.round(
              (result.latency_ms - baseline_latencies[result.scenario_id]) /
                baseline_latencies[result.scenario_id] * 100,
              2
            )

          true ->
            nil
        end

      if is_nil(overhead), do: acc, else: Map.put(acc, result.id, overhead)
    end)
  end

  defp aggregate_status(results) do
    statuses = Enum.map(results, & &1.status)

    cond do
      Enum.any?(statuses, &(&1 == "awaiting_import")) -> "awaiting_import"
      Enum.any?(statuses, &(&1 == "failed")) -> "partial"
      Enum.any?(statuses, &(&1 == "timed_out")) -> "partial"
      true -> "completed"
    end
  end

  defp find_result_for_import(run, subject, scenario_slug) do
    Enum.find(run.results, fn result ->
      result.subject == subject and result.scenario.slug == scenario_slug
    end)
  end

  defp update_result_from_outcome(result, outcome) do
    result
    |> Result.changeset(%{
      status: outcome["status"],
      decision: outcome["decision"],
      findings_count: outcome["findings_count"],
      matched_expected: outcome["matched_expected"],
      latency_ms: outcome["latency_ms"],
      payload: outcome["payload"],
      metadata: outcome["metadata"]
    })
    |> update_with_busy_retry()
  end

  defp maybe_filter_scenarios(scenarios, []), do: scenarios
  defp maybe_filter_scenarios(scenarios, slugs), do: Enum.filter(scenarios, &(&1.slug in slugs))

  defp maybe_filter_scenarios_by_domain(scenarios, nil), do: scenarios

  defp maybe_filter_scenarios_by_domain(scenarios, domain_pack) do
    Enum.filter(scenarios, fn scenario ->
      get_in(scenario.metadata || %{}, ["domain_pack"]) == domain_pack
    end)
  end

  defp normalize_scenario_slugs(nil), do: []
  defp normalize_scenario_slugs(slugs) when is_list(slugs), do: Enum.map(slugs, &to_string/1)

  defp normalize_scenario_slugs(slugs) when is_binary(slugs) do
    slugs
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_scenario_slugs(_value), do: []

  defp run_metadata(suite, subjects, project_root, domain_pack) do
    %{
      "controlkeel_version" => controlkeel_version(),
      "suite_version" => suite.version,
      "domain_pack_filter" => domain_pack,
      "subject_config_hash" => SubjectLoader.subject_config_hash(subjects),
      "project_root" => Path.expand(project_root),
      "eval_profile" => suite_eval_profile(suite),
      "subjects" =>
        Enum.map(subjects, &Map.take(&1, ["id", "label", "type", "configured", "output_mode"]))
    }
  end

  defp normalize_domain_pack_filter(nil), do: nil

  defp normalize_domain_pack_filter(value) do
    pack = Domains.normalize_pack(value, "__unsupported__")
    if Domains.supported_pack?(pack), do: pack, else: nil
  end

  defp preload_run(nil), do: nil

  defp preload_run(run) do
    Repo.preload(run,
      suite: [scenarios: from(scenario in Scenario, order_by: scenario.position)],
      results: [scenario: []]
    )
  end

  defp run_export(run) do
    detail_metrics = run_detail_metrics(run)

    %{
      run: %{
        id: run.id,
        status: run.status,
        suite: %{
          slug: run.suite.slug,
          name: run.suite.name,
          version: run.suite.version
        },
        baseline_subject: run.baseline_subject,
        subjects: run.subjects,
        started_at: run.started_at,
        finished_at: run.finished_at,
        total_scenarios: run.total_scenarios,
        caught_count: run.caught_count,
        blocked_count: run.blocked_count,
        catch_rate: run.catch_rate,
        block_rate: detail_metrics.block_rate,
        expected_rule_hit_rate: detail_metrics.expected_rule_hit_rate,
        classification: detail_metrics.classification,
        median_latency_ms: run.median_latency_ms,
        average_overhead_percent: run.average_overhead_percent,
        eval_profile: run_eval_profile(run),
        metadata: run.metadata
      },
      results:
        Enum.map(run.results, fn result ->
          %{
            id: result.id,
            scenario_slug: result.scenario.slug,
            scenario_name: result.scenario.name,
            subject: result.subject,
            subject_type: result.subject_type,
            status: result.status,
            decision: result.decision,
            findings_count: result.findings_count,
            matched_expected: result.matched_expected,
            latency_ms: result.latency_ms,
            overhead_percent: result.overhead_percent,
            payload: result.payload,
            metadata: result.metadata
          }
        end)
    }
  end

  defp export_csv(run) do
    header =
      "run_id,suite_slug,scenario_slug,scenario_name,subject,subject_type,status,decision,findings_count,matched_expected,latency_ms,overhead_percent\r\n"

    rows =
      Enum.map_join(run.results, "", fn result ->
        [
          run.id,
          run.suite.slug,
          result.scenario.slug,
          csv_escape(result.scenario.name),
          result.subject,
          result.subject_type,
          result.status,
          result.decision || "",
          result.findings_count,
          result.matched_expected,
          result.latency_ms || "",
          result.overhead_percent || ""
        ]
        |> Enum.join(",")
        |> Kernel.<>("\r\n")
      end)

    header <> rows
  end

  defp csv_escape(nil), do: "\"\""

  defp csv_escape(value) do
    "\"" <> (value |> to_string() |> String.replace("\"", "\"\"")) <> "\""
  end

  defp percentage(_count, 0), do: 0.0
  defp percentage(count, total), do: Float.round(count / total * 100, 1)

  defp count_by(values, mapper) do
    values
    |> Enum.group_by(mapper)
    |> Enum.reject(fn {key, _rows} -> is_nil(key) end)
    |> Enum.into(%{}, fn {key, rows} -> {key, length(rows)} end)
  end

  defp maybe_channel(channels, true, channel), do: [channel | channels]
  defp maybe_channel(channels, false, _channel), do: channels

  defp maybe_integrity_warning(warnings, true, _warning), do: warnings
  defp maybe_integrity_warning(warnings, false, warning), do: [warning | warnings]

  defp benchmark_integrity_title("missing_holdout_evidence"), do: "Missing holdout evidence"
  defp benchmark_integrity_title("low_behavior_diversity"), do: "Low benchmark behavior diversity"

  defp benchmark_integrity_title("missing_classification_evidence"),
    do: "Missing classification evidence"

  defp benchmark_integrity_title("single_score_promotion"),
    do: "Single-score promotion risk"

  defp benchmark_integrity_title("eval_staleness"),
    do: "Stale benchmark evaluation set"

  defp benchmark_integrity_title(warning), do: warning

  defp benchmark_integrity_message("missing_holdout_evidence") do
    "Benchmark promotion evidence has no held-out split coverage; avoid treating public-suite score as sufficient."
  end

  defp benchmark_integrity_message("low_behavior_diversity") do
    "Benchmark promotion evidence has too few behavior tags to protect against narrow metric gaming."
  end

  defp benchmark_integrity_message("missing_classification_evidence") do
    "Benchmark promotion evidence is missing classification metrics such as TPR/FPR or Youden's J."
  end

  defp benchmark_integrity_message("single_score_promotion") do
    "Promotion evidence relies on a single channel; multi-channel corroboration is needed to resist metric gaming."
  end

  defp benchmark_integrity_message("eval_staleness") do
    "The evaluation set has not been refreshed with trace-derived scenarios; repeated passes on the same set may mask regressions."
  end

  defp benchmark_integrity_message(warning),
    do: "Benchmark promotion integrity warning: #{warning}."

  defp scenario_split(%Scenario{} = scenario), do: scenario.split || "public"

  defp has_trace_derived_scenarios?(profile) do
    curation_mode = Map.get(profile, "curation_mode") || "hand_curated_plus_trace_promoted"
    String.contains?(curation_mode, "trace")
  end

  defp average([]), do: nil
  defp average(values), do: Float.round(Enum.sum(values) / length(values), 1)

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    length = Kernel.length(sorted)
    midpoint = div(length, 2)

    if rem(length, 2) == 1 do
      Enum.at(sorted, midpoint)
    else
      div(Enum.at(sorted, midpoint - 1) + Enum.at(sorted, midpoint), 2)
    end
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp controlkeel_version do
    Application.spec(:controlkeel, :vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
