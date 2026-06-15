defmodule ControlKeel.Observability do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Benchmark
  alias ControlKeel.Benchmark.{Result, Scenario, Suite}
  alias ControlKeel.Benchmark.Run, as: BenchmarkRun
  alias ControlKeel.Budget
  alias ControlKeel.Memory
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Mission
  alias ControlKeel.MCP.Tools.CkTokenAudit
  alias ControlKeel.Observability.{BenchmarkDraft, EvalCandidate, ImportedEnvelope}
  alias ControlKeel.Mission.{Finding, Invocation, Session, SessionEvent}
  alias ControlKeel.Repo

  @active_finding_statuses ~w(open blocked escalated)
  @active_task_statuses ~w(queued in_progress blocked paused)
  @cost_group_fields ~w(model tool source provider)

  def workspace_overview(opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    sessions = recent_sessions(opts, limit)
    runs = Enum.map(sessions, &session_run(&1.id, events_limit: 3))

    run_summaries =
      runs
      |> Enum.flat_map(fn
        {:ok, run} -> [overview_run_summary(run)]
        _other -> []
      end)

    workspace_id =
      Keyword.get(opts, :workspace_id) ||
        run_summaries |> List.first() |> then(&(&1 && &1.workspace_id))

    problems_opts = if workspace_id, do: [workspace_id: workspace_id, limit: 5], else: [limit: 5]
    problem_summary = problems(problems_opts)
    health = overview_health(run_summaries, problem_summary)

    %{
      health: health,
      workspace: overview_workspace(run_summaries),
      runs: %{
        count: length(run_summaries),
        recent: run_summaries
      },
      problems: %{
        health: problem_summary.health,
        count: problem_summary.count,
        total_findings: problem_summary.total_findings,
        top: problem_summary.problems,
        recommendations: problem_summary.recommendations
      },
      costs: overview_costs(run_summaries),
      telemetry: overview_telemetry(workspace_id),
      recommendations: overview_recommendations(health, run_summaries, problem_summary)
    }
  end

  def imports(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    snapshots = imported_envelopes(opts, limit)

    %{
      count: imported_envelope_count(opts),
      limit: limit,
      recent: Enum.map(snapshots, &import_summary/1),
      by_integrity: frequencies(snapshots, &(&1.integrity_status || "unknown")),
      by_health: frequencies(snapshots, &(&1.health || "unknown")),
      recommendations: import_recommendations(snapshots)
    }
  end

  def loop_diagnostics(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    session_id = Keyword.get(opts, :session_id)
    workspace_id = Keyword.get(opts, :workspace_id)

    events = diagnostic_events(session_id, workspace_id, limit * 5)
    invocations = cost_invocations(opts) |> Enum.take(limit * 5)
    repeated_events = repeated_event_runs(events, limit)
    repeated_invocations = repeated_invocation_runs(invocations, limit)

    %{
      read_only: true,
      mutation: "none",
      session_id: session_id,
      workspace_id: workspace_id,
      repeated_tool_events: repeated_events,
      repeated_invocations: repeated_invocations,
      totals: %{
        event_runs: length(repeated_events),
        invocation_runs: length(repeated_invocations)
      },
      recommendations: loop_diagnostic_recommendations(repeated_events, repeated_invocations)
    }
  end

  def trends(opts \\ []) do
    days = opts |> Keyword.get(:days, 7) |> normalize_days()
    workspace_id = Keyword.get(opts, :workspace_id)
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))
    since = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    sessions = trend_sessions(workspace_id, since)
    findings = trend_findings(workspace_id, since)
    invocations = trend_invocations(workspace_id, since)
    imports = trend_imports(workspace_id, since)

    series = trend_series(today, days, sessions, findings, invocations, imports)
    totals = trend_totals(series)

    %{
      days: days,
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(today),
      totals: totals,
      series: series,
      recommendations: trend_recommendations(series, totals)
    }
  end

  def problems(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # Two-query strategy: aggregate counts in DB (returns at most `limit` rows),
    # then fetch up to 3 example findings per group. Replaces a full table scan
    # + Elixir-side Enum.group_by that grew linearly with finding count.
    aggregates = problem_aggregates(opts, limit)
    total_findings = problem_total_count(opts)

    groups =
      Enum.map(aggregates, fn agg ->
        examples = problem_examples(agg.rule_id, agg.category, opts, 3)
        problem_summary_from_aggregate(agg, examples)
      end)

    %{
      count: length(groups),
      total_findings: total_findings,
      problems: groups,
      health: problems_health(groups),
      recommendations: problems_recommendations(groups)
    }
  end

  def costs(opts \\ []) do
    by = normalize_cost_group(Keyword.get(opts, :by, "model"))
    invocations = cost_invocations(opts)
    totals = cost_totals(invocations)
    groups = cost_groups(invocations, by)

    %{
      by: by,
      totals: totals,
      groups: groups,
      recommendations: cost_recommendations(totals, groups, by),
      available_groupings: @cost_group_fields
    }
  end

  def comparison(opts \\ []) do
    by = normalize_cost_group(Keyword.get(opts, :by, "model"))
    invocations = cost_invocations(opts)
    groups = comparison_groups(invocations, by)

    %{
      by: by,
      totals: cost_totals(invocations),
      groups: groups,
      available_groupings: @cost_group_fields,
      recommendations: comparison_recommendations(groups, by)
    }
  end

  def saved_eval_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    candidates = saved_eval_candidate_records(opts, limit)

    %{
      count: saved_eval_candidate_count(opts),
      limit: limit,
      candidates: Enum.map(candidates, &saved_eval_candidate_summary/1),
      by_status: frequencies(candidates, &(&1.status || "unknown")),
      by_priority: frequencies(candidates, &(&1.priority || "unknown")),
      recommendations: saved_eval_candidate_recommendations(candidates)
    }
  end

  def save_eval_candidates(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    derived = eval_candidates(if(workspace_id, do: [workspace_id: workspace_id], else: []))

    results =
      Enum.map(derived.candidates, fn candidate ->
        save_eval_candidate(candidate, workspace_id)
      end)

    %{
      source_count: derived.count,
      stored: Enum.count(results, &match?({:stored, _}, &1)),
      existing: Enum.count(results, &match?({:existing, _}, &1)),
      candidates:
        Enum.map(results, fn {_status, record} -> saved_eval_candidate_summary(record) end),
      human_gate_required: true,
      mutation: "advisory_record_only"
    }
  end

  def benchmark_drafts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    drafts = benchmark_draft_records(opts, limit)

    %{
      count: benchmark_draft_count(opts),
      limit: limit,
      drafts: Enum.map(drafts, &benchmark_draft_summary/1),
      by_status: frequencies(drafts, &(&1.status || "unknown")),
      by_suite: frequencies(drafts, &(&1.suite_slug || "unknown")),
      recommendations: benchmark_draft_recommendations(drafts)
    }
  end

  def generate_benchmark_drafts(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)

    candidates =
      EvalCandidate
      |> maybe_filter_eval_workspace(workspace_id)
      |> maybe_filter_eval_status("open")
      |> order_by([c], desc: c.inserted_at, desc: c.id)
      |> Repo.all()

    results = Enum.map(candidates, &generate_benchmark_draft/1)

    %{
      source_count: length(candidates),
      stored: Enum.count(results, &match?({:stored, _}, &1)),
      existing: Enum.count(results, &match?({:existing, _}, &1)),
      drafts: Enum.map(results, fn {_status, draft} -> benchmark_draft_summary(draft) end),
      human_gate_required: true,
      mutation: "draft_record_only"
    }
  end

  def materialize_benchmark_drafts(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)

    drafts =
      BenchmarkDraft
      |> maybe_filter_draft_workspace(workspace_id)
      |> maybe_filter_draft_status("approved")
      |> order_by([d], asc: d.id)
      |> Repo.all()

    results = Enum.map(drafts, &materialize_benchmark_draft/1)

    %{
      source_count: length(drafts),
      materialized: Enum.count(results, &match?({:materialized, _}, &1)),
      existing: Enum.count(results, &match?({:existing, _}, &1)),
      scenarios:
        Enum.map(results, fn {_status, scenario} -> observability_scenario_summary(scenario) end),
      benchmark_execution: false,
      human_gate_required: true,
      mutation: "local_benchmark_scenario_only"
    }
  end

  @doc """
  Close or reopen EvalCandidates based on benchmark run results.

  For every result whose scenario originated from an EvalCandidate:
  - all subjects matched expected → archive the candidate (lifecycle closed)
  - any subject missed → reopen the candidate (status set to "open")

  Idempotent: updating an already-closed candidate with new failure evidence
  reopens it, keeping the loop honest.
  """
  def close_eval_candidate_lifecycle_from_run!(run_or_id) do
    case normalize_benchmark_run(run_or_id) do
      nil ->
        []

      run ->
        run.results
        |> Enum.reject(&is_nil(&1.scenario))
        |> Enum.group_by(fn result -> result.scenario end)
        |> Enum.reduce([], fn {scenario, results}, acc ->
          case scenario.metadata do
            %{"eval_candidate_id" => candidate_id} when is_integer(candidate_id) ->
              updated = update_eval_candidate_from_results(candidate_id, scenario, results, run)

              if updated, do: [updated | acc], else: acc

            _other ->
              acc
          end
        end)
    end
  end

  defp normalize_benchmark_run(%BenchmarkRun{} = run), do: Repo.preload(run, results: :scenario)

  defp normalize_benchmark_run(run_id) when is_integer(run_id) do
    BenchmarkRun
    |> where([r], r.id == ^run_id)
    |> preload([:suite, results: [:scenario]])
    |> Repo.one()
  end

  defp update_eval_candidate_from_results(candidate_id, scenario, results, run) do
    case Repo.get(EvalCandidate, candidate_id) do
      nil ->
        nil

      candidate ->
        all_matched = Enum.all?(results, & &1.matched_expected)
        {new_status, lifecycle_key} = lifecycle_transition(all_matched)
        now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

        metadata =
          (candidate.metadata || %{})
          |> Map.put(lifecycle_key, %{
            "run_id" => run.id,
            "scenario_id" => scenario.id,
            "scenario_slug" => scenario.slug,
            "all_matched" => all_matched,
            "result_count" => length(results),
            "closed_at" => now
          })

        candidate
        |> EvalCandidate.changeset(%{status: new_status, metadata: metadata})
        |> Repo.update()
        |> case do
          {:ok, updated} -> updated
          {:error, _reason} -> nil
        end
    end
  end

  defp lifecycle_transition(true), do: {"archived", "lifecycle_closed_by_run"}
  defp lifecycle_transition(false), do: {"open", "lifecycle_reopened_by_run"}

  def observability_benchmark_scenarios(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    scenarios = observability_scenario_records(opts, limit)

    %{
      count: observability_scenario_count(opts),
      limit: limit,
      scenarios: Enum.map(scenarios, &observability_scenario_summary/1),
      by_suite: frequencies(scenarios, &observability_scenario_suite_slug/1),
      recommendations: observability_scenario_recommendations(scenarios)
    }
  end

  def observability_benchmark_run_preview(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    suite_slug = Keyword.get(opts, :suite)
    scenario_slugs = normalize_observability_scenario_slugs(Keyword.get(opts, :scenario_slugs))
    subjects = Keyword.get(opts, :subjects)

    scenarios =
      opts
      |> Keyword.put(:limit, limit)
      |> observability_scenario_records(limit)
      |> maybe_filter_observability_scenarios_by_suite(suite_slug)
      |> maybe_filter_observability_scenarios_by_slugs(scenario_slugs)

    suites =
      scenarios
      |> Enum.map(&observability_scenario_suite_slug/1)
      |> Enum.uniq()
      |> Enum.sort()

    selected_suite = suite_slug || single_suite(suites)

    selected_scenarios =
      if selected_suite do
        Enum.filter(scenarios, &(observability_scenario_suite_slug(&1) == selected_suite))
      else
        scenarios
      end

    %{
      suite: selected_suite,
      suites: suites,
      scenario_slugs: Enum.map(selected_scenarios, & &1.slug),
      scenarios: Enum.map(selected_scenarios, &observability_scenario_summary/1),
      subjects: subjects,
      executable:
        selected_suite != nil and subjects_present?(subjects) and selected_scenarios != [],
      dry_run: true,
      benchmark_execution: false,
      command: observability_benchmark_run_command(selected_suite, selected_scenarios, subjects),
      recommendations:
        observability_run_recommendations(selected_suite, suites, selected_scenarios, subjects)
    }
  end

  def run_observability_benchmark(opts \\ [], project_root \\ File.cwd!()) do
    preview = observability_benchmark_run_preview(opts)

    cond do
      Keyword.get(opts, :dry_run, true) ->
        {:ok, preview}

      not Keyword.get(opts, :execute, false) ->
        {:error, :execute_required, preview}

      not preview.executable ->
        {:error, :not_executable, preview}

      true ->
        attrs = %{
          "suite" => preview.suite,
          "subjects" => preview.subjects,
          "baseline_subject" => Keyword.get(opts, :baseline_subject) || preview.subjects,
          "scenario_slugs" => Enum.join(preview.scenario_slugs, ",")
        }

        case Benchmark.run_suite(attrs, project_root) do
          {:ok, run} ->
            close_eval_candidate_lifecycle_from_run!(run)
            {:ok, observability_benchmark_run_result(run, preview)}

          {:error, reason} ->
            {:error, reason, preview}
        end
    end
  end

  def observability_benchmark_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)
    workspace_id = Keyword.get(opts, :workspace_id)
    scenarios = observability_scenario_records([workspace_id: workspace_id, limit: 500], 500)
    scenario_ids = Enum.map(scenarios, & &1.id)
    runs = observability_benchmark_run_records(scenarios, limit)

    covered_ids =
      runs
      |> Enum.flat_map(&(&1.results || []))
      |> Enum.map(& &1.scenario_id)
      |> Enum.uniq()

    saved = saved_eval_candidates(workspace_id: workspace_id)
    drafts = benchmark_drafts(workspace_id: workspace_id)
    approved_drafts = benchmark_draft_count(workspace_id: workspace_id, status: "approved")
    latest = List.first(runs)

    coverage = %{
      saved_eval_candidates: saved.count,
      benchmark_drafts: drafts.count,
      approved_drafts: approved_drafts,
      materialized_scenarios: length(scenario_ids),
      covered_scenarios: length(Enum.filter(scenario_ids, &(&1 in covered_ids))),
      benchmark_runs: length(runs)
    }

    %{
      limit: limit,
      readiness: observability_benchmark_readiness(latest, coverage),
      coverage: coverage,
      latest_run: if(latest, do: observability_benchmark_history_run_summary(latest), else: nil),
      runs: Enum.map(runs, &observability_benchmark_history_run_summary/1),
      missed: observability_benchmark_missed_summaries(runs),
      recommendations: observability_benchmark_history_recommendations(latest, coverage)
    }
  end

  def promotion_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    workspace_id = Keyword.get(opts, :workspace_id)
    candidates = saved_eval_candidate_records([workspace_id: workspace_id], limit)
    drafts = benchmark_draft_records([workspace_id: workspace_id], 500)
    history = observability_benchmark_history(workspace_id: workspace_id)

    items =
      Enum.map(candidates, fn candidate ->
        draft = Enum.find(drafts, &(&1.eval_candidate_id == candidate.id))
        promotion_candidate_summary(candidate, draft, history)
      end)

    %{
      count: length(items),
      limit: limit,
      promotion_execution: false,
      by_readiness: frequencies(items, & &1.readiness),
      candidates: items,
      recommendations: promotion_candidate_recommendations(items, history)
    }
  end

  def update_benchmark_draft_status(id, status, opts \\ [])

  def update_benchmark_draft_status(id, status, opts)
      when status in ["approved", "rejected", "archived"] do
    with {:ok, draft_id} <- parse_id(id),
         %BenchmarkDraft{} = draft <- Repo.get(BenchmarkDraft, draft_id) || {:error, :not_found},
         {:ok, updated} <- update_benchmark_draft_record(draft, status, opts) do
      {:ok, benchmark_draft_status_result(updated)}
    end
  end

  def update_benchmark_draft_status(_id, _status, _opts), do: {:error, :invalid_status}

  def regressions(opts \\ []) do
    days = Keyword.get(opts, :days) || 30
    limit = Keyword.get(opts, :limit) || 12
    workspace_id = Keyword.get(opts, :workspace_id)
    runs = benchmark_run_records(days, limit)
    drafts = benchmark_drafts(workspace_id: workspace_id)
    saved = saved_eval_candidates(workspace_id: workspace_id)

    %{
      days: days,
      health: regression_health(runs, drafts, saved),
      benchmark_runs: %{
        count: length(runs),
        recent: Enum.map(runs, &benchmark_run_summary/1),
        average_catch_rate: average_value(Enum.map(runs, &(&1.catch_rate || 0.0))),
        by_status: frequencies(runs, &(&1.status || "unknown")),
        by_suite: frequencies(runs, &benchmark_run_suite_slug/1)
      },
      draft_coverage: %{
        saved_eval_candidates: saved.count,
        benchmark_drafts: drafts.count,
        draft_status: drafts.by_status,
        draft_suites: drafts.by_suite
      },
      recommendations: regression_recommendations(runs, drafts, saved)
    }
  end

  def loop_status(opts \\ []) do
    overview = workspace_overview(opts)
    workspace_id = Keyword.get(opts, :workspace_id) || overview.workspace.id
    scoped_opts = if workspace_id, do: [workspace_id: workspace_id], else: []
    problems_report = problems(Keyword.put(scoped_opts, :limit, 5))
    evals = eval_candidates(Keyword.put(scoped_opts, :limit, 5))
    saved = saved_eval_candidates(Keyword.put(scoped_opts, :limit, 10))
    drafts = benchmark_drafts(Keyword.put(scoped_opts, :limit, 10))
    scenarios = observability_benchmark_scenarios(Keyword.put(scoped_opts, :limit, 10))
    history = observability_benchmark_history(Keyword.put(scoped_opts, :limit, 10))
    promotions = promotion_candidates(Keyword.put(scoped_opts, :limit, 10))
    recommendations_report = recommendations(scoped_opts)

    blockers = loop_status_blockers(overview, problems_report, drafts, history, promotions)

    %{
      health: loop_status_health(overview.health, history.readiness, promotions, blockers),
      workspace: overview.workspace,
      read_only: true,
      mutation: "none",
      learning_loop: %{
        mode: "local_first_human_gated",
        automatic_benchmark_execution: false,
        automatic_promotion: false,
        generated_benchmarks: "operator_reviewed_regression_seeds"
      },
      active_problems: %{
        count: problems_report.count,
        total_findings: problems_report.total_findings,
        top: problems_report.problems
      },
      evals: %{derived: evals.count, saved: saved.count, saved_by_status: saved.by_status},
      benchmarks: %{
        drafts: drafts.count,
        draft_status: drafts.by_status,
        scenarios: scenarios.count,
        history_readiness: history.readiness,
        coverage: history.coverage,
        latest_run: history.latest_run
      },
      promotions: %{
        count: promotions.count,
        by_readiness: promotions.by_readiness,
        promotion_execution: promotions.promotion_execution,
        candidates: promotions.candidates
      },
      blockers: blockers,
      next_actions: Enum.take(recommendations_report.actions, 8),
      recommendations: loop_status_recommendations(blockers, history, promotions)
    }
  end

  def recommendations(opts \\ []) do
    overview = workspace_overview(opts)
    workspace_id = overview.workspace.id
    scoped_opts = if workspace_id, do: [workspace_id: workspace_id], else: []
    problems = problems(Keyword.put(scoped_opts, :limit, 5))
    costs = costs(scoped_opts)
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    actions =
      []
      |> add_health_actions(overview)
      |> add_problem_actions(problems)
      |> add_cost_actions(costs)
      |> add_token_overhead_actions(project_root)
      |> Enum.sort_by(&{priority_rank(&1.priority), &1.id})

    %{
      health: recommendation_health(actions),
      count: length(actions),
      actions: actions,
      categories: actions |> Enum.map(& &1.category) |> Enum.uniq(),
      workspace: overview.workspace
    }
  end

  def perf_snapshot(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)
    persist = Keyword.get(opts, :persist, false)

    items =
      []
      |> Kernel.++([
        perf_item("observability.workspace_overview", fn -> workspace_overview(opts) end),
        perf_item("observability.loop_status", fn -> loop_status(opts) end),
        perf_item("observability.recommendations", fn -> recommendations(opts) end),
        perf_item("observability.costs", fn -> costs(opts) end)
      ])
      |> maybe_add_session_perf_items(session_id, opts)
      |> maybe_add_mission_perf_items(session_id)
      |> maybe_add_memory_perf_items(session_id, workspace_id, task_id)

    snapshot = %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      workspace_id: workspace_id,
      session_id: session_id,
      task_id: task_id,
      items: items,
      summary: perf_summary(items)
    }

    if persist do
      persist_perf_snapshot(snapshot, opts)
    end

    snapshot
  end

  def eval_candidates(opts \\ []) do
    problem_summary = problems(opts)

    candidates =
      problem_summary.problems
      |> Enum.map(&eval_candidate_from_problem/1)
      |> Enum.sort_by(&{priority_rank(&1.priority), &1.rule_id})

    %{
      count: length(candidates),
      health: eval_candidates_health(candidates),
      candidates: candidates,
      recommendations: eval_candidate_recommendations(candidates)
    }
  end

  def timeline(session_or_id, opts \\ [])

  def timeline(%Session{} = session, opts) do
    session = ensure_workspace_preloaded(session)
    limit = Keyword.get(opts, :limit, 50)
    events = Mission.list_session_events(session.id, limit)
    event_summaries = Enum.map(events, &timeline_event/1)

    %{
      session: session_summary(session),
      count: length(event_summaries),
      limit: limit,
      by_event_type: frequencies(event_summaries, & &1.event_type),
      by_actor: frequencies(event_summaries, & &1.actor),
      events: event_summaries
    }
  end

  def timeline(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_with_workspace(session_id) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, timeline(session, opts)}
    end
  end

  def timeline(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> timeline(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  def memory_context(session_or_id, opts \\ [])

  def memory_context(%Session{} = session, opts) do
    session = ensure_preloaded(session)
    limit = Keyword.get(opts, :limit, 10)
    records = memory_records(session.id, limit)
    active_records = Enum.filter(records, &is_nil(&1.archived_at))
    archived_records = Enum.reject(records, &is_nil(&1.archived_at))

    %{
      session: session_summary(session),
      context: %{
        tasks: length(session.tasks || []),
        findings: length(session.findings || []),
        reviews: length(session.reviews || []),
        invocations: length(session.invocations || [])
      },
      memory: %{
        count: length(records),
        active: length(active_records),
        archived: length(archived_records),
        by_type: frequencies(records, &(&1.record_type || "unknown")),
        by_source: frequencies(records, &(&1.source_type || "unknown")),
        recent: Enum.map(records, &memory_record_summary/1)
      },
      recommendations: memory_context_recommendations(active_records, archived_records)
    }
  end

  def memory_context(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_with_workspace(session_id) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, memory_context_for_session_id(session, opts)}
    end
  end

  def memory_context(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> memory_context(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  defp memory_context_for_session_id(%Session{} = session, opts) do
    limit = Keyword.get(opts, :limit, 10)
    records = memory_records(session.id, limit)
    active_records = Enum.filter(records, &is_nil(&1.archived_at))
    archived_records = Enum.reject(records, &is_nil(&1.archived_at))

    %{
      session: session_summary(session),
      context: session_context_counts(session.id),
      memory: %{
        count: length(records),
        active: length(active_records),
        archived: length(archived_records),
        by_type: frequencies(records, &(&1.record_type || "unknown")),
        by_source: frequencies(records, &(&1.source_type || "unknown")),
        recent: Enum.map(records, &memory_record_summary/1)
      },
      recommendations: memory_context_recommendations(active_records, archived_records)
    }
  end

  def memory_quality(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    stale_days = opts |> Keyword.get(:stale_days, 30) |> normalize_stale_days()
    workspace_id = Keyword.get(opts, :workspace_id)
    records = memory_quality_records(workspace_id)

    sessions =
      recent_sessions([workspace_id: workspace_id], Keyword.get(opts, :session_limit, 20))

    active_records = Enum.filter(records, &is_nil(&1.archived_at))
    archived_records = Enum.reject(records, &is_nil(&1.archived_at))
    stale = stale_memory_candidates(active_records, stale_days, limit)
    duplicates = duplicate_memory_clusters(active_records, limit)
    contradictions = contradiction_memory_candidates(active_records, limit)
    missed = missed_memory_sessions(sessions, records, limit)

    %{
      stale_days: stale_days,
      totals: %{
        records: length(records),
        active: length(active_records),
        archived: length(archived_records),
        stale_candidates: length(stale),
        duplicate_clusters: length(duplicates),
        contradiction_candidates: length(contradictions),
        missed_memory_sessions: length(missed)
      },
      distributions: %{
        by_type: frequencies(records, &(&1.record_type || "unknown")),
        by_source: frequencies(records, &(&1.source_type || "unknown"))
      },
      stale_candidates: stale,
      duplicate_clusters: duplicates,
      contradiction_candidates: contradictions,
      missed_memory_sessions: missed,
      recommendations:
        memory_quality_recommendations(stale, duplicates, contradictions, missed, records)
    }
  end

  def session_run(session_or_id, opts \\ [])

  def session_run(%Session{} = session, opts) do
    session = ensure_preloaded(session)
    events_limit = Keyword.get(opts, :events_limit, 8)
    events = Mission.list_session_events(session.id, events_limit)
    budget = budget_status(session)

    findings = session.findings || []
    tasks = session.tasks || []
    reviews = session.reviews || []
    invocations = session.invocations || []

    finding_counts = Mission.session_finding_counts(session.id)
    task_counts = Mission.session_task_counts(session.id)
    review_counts = Mission.session_review_counts(session.id)
    invocation_counts = Mission.session_invocation_counts(session.id)

    proofs = Mission.latest_proof_bundles_for_session(session.id)
    memory_count = memory_count(session.id)

    health =
      health(
        finding_counts.total,
        finding_counts.active,
        finding_counts.blocked,
        finding_counts.critical_active,
        task_counts.active,
        review_counts.pending,
        budget
      )

    %{
      session: session_summary(session),
      health: health,
      budget: budget,
      findings: finding_summary_with_counts(findings, finding_counts),
      tasks: task_summary_with_counts(tasks, task_counts),
      gates: gate_summary_with_counts(reviews, review_counts),
      timeline: timeline_summary(events),
      memory: %{records: memory_count},
      proofs: proof_summary(proofs),
      hosts_models_tools: invocation_summary_with_counts(invocations, invocation_counts),
      recommendations:
        recommendations(
          health,
          finding_counts.total,
          finding_counts.active,
          finding_counts.critical_active,
          finding_counts.high_active,
          review_counts.pending,
          budget,
          memory_count
        )
    }
  end

  def session_run(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_context(session_id,
           findings_limit: 10,
           tasks_limit: 20,
           reviews_limit: 5,
           invocations_limit: 20
         ) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, session_run(session, opts)}
    end
  end

  def session_run(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> session_run(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  defp normalize_stale_days(days) when is_integer(days) and days > 0 and days <= 365, do: days
  defp normalize_stale_days(days) when is_integer(days) and days > 365, do: 365
  defp normalize_stale_days(_days), do: 30

  defp memory_quality_records(workspace_id) do
    MemoryRecord
    |> maybe_filter_memory_workspace(workspace_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Repo.all()
  end

  defp maybe_filter_memory_workspace(query, nil), do: query

  defp maybe_filter_memory_workspace(query, workspace_id),
    do: where(query, [m], m.workspace_id == ^workspace_id)

  defp stale_memory_candidates(records, stale_days, limit) do
    today = Date.utc_today()

    records
    |> Enum.map(fn record -> {record, memory_age_days(record, today)} end)
    |> Enum.filter(fn {_record, age_days} -> age_days >= stale_days end)
    |> Enum.sort_by(fn {_record, age_days} -> age_days end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {record, age_days} -> memory_quality_record_summary(record, age_days) end)
  end

  defp memory_age_days(record, today) do
    case record.inserted_at do
      %DateTime{} = inserted_at -> Date.diff(today, DateTime.to_date(inserted_at))
      %NaiveDateTime{} = inserted_at -> Date.diff(today, NaiveDateTime.to_date(inserted_at))
      _ -> 0
    end
  end

  defp duplicate_memory_clusters(records, limit) do
    records
    |> Enum.group_by(&memory_duplicate_key/1)
    |> Enum.reject(fn {key, group} -> key == "" or length(group) < 2 end)
    |> Enum.map(fn {key, group} ->
      %{
        key: key,
        count: length(group),
        records: group |> Enum.take(5) |> Enum.map(&memory_quality_record_summary(&1, nil))
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp memory_duplicate_key(record) do
    [record.title, record.summary]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" | ")
    |> String.downcase()
  end

  defp contradiction_memory_candidates(records, limit) do
    records
    |> Enum.filter(&contradiction_marker?/1)
    |> Enum.take(limit)
    |> Enum.map(&memory_quality_record_summary(&1, nil))
  end

  defp contradiction_marker?(record) do
    text =
      [record.title, record.summary | List.wrap(record.tags)]
      |> Enum.concat(record.metadata |> Map.keys() |> Enum.map(&to_string/1))
      |> Enum.concat(record.metadata |> Map.values() |> Enum.map(&metadata_text/1))
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    Enum.any?(["contradict", "superseded", "obsolete", "conflict"], &String.contains?(text, &1))
  end

  defp metadata_text(value) when is_binary(value), do: value

  defp metadata_text(value) when is_atom(value) or is_number(value) or is_boolean(value),
    do: to_string(value)

  defp metadata_text(value) when is_nil(value), do: nil
  defp metadata_text(value), do: inspect(value)

  defp missed_memory_sessions(sessions, records, limit) do
    memory_session_ids =
      records
      |> Enum.filter(&(&1.record_type in ["brief", "checkpoint", "decision", "goal"]))
      |> Enum.map(& &1.session_id)
      |> MapSet.new()

    sessions
    |> Enum.reject(&MapSet.member?(memory_session_ids, &1.id))
    |> Enum.map(fn session -> {session, session_evidence_counts(session.id)} end)
    |> Enum.filter(fn {_session, counts} ->
      counts.findings > 0 or counts.reviews > 0 or counts.invocations > 0
    end)
    |> Enum.take(limit)
    |> Enum.map(fn {session, counts} ->
      %{
        id: session.id,
        title: session.title,
        findings: counts.findings,
        reviews: counts.reviews,
        invocations: counts.invocations,
        recommendation: "Record a checkpoint or decision memory for this session's evidence."
      }
    end)
  end

  defp session_evidence_counts(session_id) do
    %{
      findings:
        Repo.aggregate(from(f in Finding, where: f.session_id == ^session_id), :count, :id),
      reviews:
        Repo.aggregate(
          from(r in ControlKeel.Mission.Review, where: r.session_id == ^session_id),
          :count,
          :id
        ),
      invocations:
        Repo.aggregate(from(i in Invocation, where: i.session_id == ^session_id), :count, :id)
    }
  end

  defp memory_quality_record_summary(record, age_days) do
    %{
      id: record.id,
      title: record.title,
      summary: record.summary,
      record_type: record.record_type,
      source_type: record.source_type,
      session_id: record.session_id,
      task_id: record.task_id,
      tags: record.tags || [],
      archived: not is_nil(record.archived_at),
      inserted_at: format_datetime(record.inserted_at),
      age_days: age_days
    }
  end

  defp memory_quality_recommendations(stale, duplicates, contradictions, missed, records) do
    []
    |> maybe_reason(
      records == [],
      "No memory records exist yet; record checkpoints and decisions for durable continuity."
    )
    |> maybe_reason(
      stale != [],
      "Review stale memory candidates and archive or supersede records that no longer match current behavior."
    )
    |> maybe_reason(
      duplicates != [],
      "Deduplicate repeated memory records to reduce retrieval noise."
    )
    |> maybe_reason(
      contradictions != [],
      "Review contradiction or superseded memory candidates before relying on retrieved context."
    )
    |> maybe_reason(
      missed != [],
      "Add checkpoint or decision memory for sessions with evidence but no durable memory."
    )
    |> case do
      [] -> ["Memory quality signals look stable for this workspace."]
      recommendations -> recommendations
    end
  end

  defp normalize_days(days) when is_integer(days) and days > 0 and days <= 90, do: days
  defp normalize_days(days) when is_integer(days) and days > 90, do: 90
  defp normalize_days(_days), do: 7

  defp trend_sessions(workspace_id, since) do
    Session
    |> maybe_filter_session_workspace(workspace_id)
    |> where([s], s.inserted_at >= ^since)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> Repo.all()
    |> Enum.map(&ensure_preloaded/1)
  end

  defp trend_findings(workspace_id, since) do
    Finding
    |> join(:inner, [f], s in assoc(f, :session))
    |> maybe_filter_workspace(workspace_id)
    |> where([f, _s], f.inserted_at >= ^since)
    |> where([f, _s], f.status in ^@active_finding_statuses)
    |> Repo.all()
  end

  defp trend_invocations(workspace_id, since) do
    Invocation
    |> join(:inner, [i], s in assoc(i, :session))
    |> maybe_filter_invocation_workspace(workspace_id)
    |> where([i, _s], i.inserted_at >= ^since)
    |> Repo.all()
  end

  defp trend_imports(workspace_id, since) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(workspace_id)
    |> where([i], i.imported_at >= ^since)
    |> Repo.all()
  end

  defp trend_series(today, days, sessions, findings, invocations, imports) do
    session_groups = Enum.group_by(sessions, &day_key(&1.inserted_at))
    finding_groups = Enum.group_by(findings, &day_key(&1.inserted_at))
    invocation_groups = Enum.group_by(invocations, &day_key(&1.inserted_at))
    import_groups = Enum.group_by(imports, &day_key(&1.imported_at))

    0..(days - 1)
    |> Enum.map(fn offset -> Date.add(today, -(days - 1 - offset)) end)
    |> Enum.map(fn date ->
      key = Date.to_iso8601(date)
      day_sessions = Map.get(session_groups, key, [])
      day_findings = Map.get(finding_groups, key, [])
      day_invocations = Map.get(invocation_groups, key, [])
      day_imports = Map.get(import_groups, key, [])
      health_counts = frequencies(day_sessions, &session_health_status/1)

      %{
        date: key,
        runs: length(day_sessions),
        health: %{
          red: Map.get(health_counts, "red", 0),
          yellow: Map.get(health_counts, "yellow", 0),
          green: Map.get(health_counts, "green", 0)
        },
        active_findings: length(day_findings),
        blocked_findings: Enum.count(day_findings, &(&1.status == "blocked")),
        estimated_cost_cents: sum_invocation_field(day_invocations, :estimated_cost_cents),
        imports: length(day_imports),
        verified_imports: Enum.count(day_imports, &(&1.integrity_status == "verified")),
        non_verified_imports: Enum.count(day_imports, &(&1.integrity_status != "verified"))
      }
    end)
  end

  defp session_health_status(session) do
    session = ensure_preloaded(session)
    findings = session.findings || []
    tasks = session.tasks || []
    reviews = session.reviews || []

    health(findings, tasks, reviews, budget_status(session)).status
  end

  defp trend_totals(series) do
    %{
      runs: Enum.reduce(series, 0, &(&1.runs + &2)),
      red_runs: Enum.reduce(series, 0, &(&1.health.red + &2)),
      yellow_runs: Enum.reduce(series, 0, &(&1.health.yellow + &2)),
      green_runs: Enum.reduce(series, 0, &(&1.health.green + &2)),
      active_findings: Enum.reduce(series, 0, &(&1.active_findings + &2)),
      blocked_findings: Enum.reduce(series, 0, &(&1.blocked_findings + &2)),
      estimated_cost_cents: Enum.reduce(series, 0, &(&1.estimated_cost_cents + &2)),
      imports: Enum.reduce(series, 0, &(&1.imports + &2)),
      verified_imports: Enum.reduce(series, 0, &(&1.verified_imports + &2)),
      non_verified_imports: Enum.reduce(series, 0, &(&1.non_verified_imports + &2))
    }
  end

  defp trend_recommendations(series, totals) do
    last_day = List.last(series) || %{}

    []
    |> maybe_reason(totals.runs == 0, "No session runs recorded in this trend window yet.")
    |> maybe_reason(
      totals.red_runs > 0,
      "Red runs appeared in the trend window; inspect blocked findings and gates before widening automation."
    )
    |> maybe_reason(
      totals.blocked_findings > 0,
      "Blocked findings are still present in the trend window; resolve or disposition them before promotion work."
    )
    |> maybe_reason(
      totals.imports == 0,
      "No persisted import snapshots in this trend window; persist verified exports to enable cross-run trend baselines."
    )
    |> maybe_reason(
      totals.non_verified_imports > 0,
      "Some imports are not verified; exclude them from benchmark evidence until resolved."
    )
    |> maybe_reason(
      (last_day[:estimated_cost_cents] || 0) > div(max(totals.estimated_cost_cents, 1), 2),
      "Recent estimated spend is concentrated in the latest day; review cost efficiency before scaling."
    )
    |> case do
      [] -> ["Local observability trends look stable for this window."]
      recommendations -> recommendations
    end
  end

  defp day_key(nil), do: "unknown"
  defp day_key(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp day_key(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp overview_telemetry(workspace_id) do
    import_summary =
      imports(if(workspace_id, do: [workspace_id: workspace_id, limit: 3], else: [limit: 3]))

    %{
      export_schema_version: ControlKeel.Observability.Telemetry.schema_version(),
      import_mode: "dry_run_or_local_persist",
      integrity: "sha256",
      persisted_imports: import_summary.count,
      recent_imports: import_summary.recent
    }
  end

  defp imported_envelopes(opts, limit) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(Keyword.get(opts, :workspace_id))
    |> order_by([i], desc: i.imported_at, desc: i.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp imported_envelope_count(opts) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(Keyword.get(opts, :workspace_id))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_import_workspace(query, nil), do: query

  defp maybe_filter_import_workspace(query, workspace_id),
    do: where(query, [i], i.workspace_id == ^workspace_id)

  defp import_summary(%ImportedEnvelope{} = imported) do
    %{
      id: imported.id,
      schema_version: imported.schema_version,
      exported_at: format_datetime(imported.exported_at),
      imported_at: format_datetime(imported.imported_at),
      original_session_id: imported.original_session_id,
      original_session_title: imported.original_session_title,
      health: imported.health || "unknown",
      problem_groups: imported.problem_groups || 0,
      total_problem_findings: imported.total_problem_findings || 0,
      redaction_policy: imported.redaction_policy,
      integrity_status: imported.integrity_status || "unknown",
      payload_sha256: imported.payload_sha256,
      payload_fingerprint: fingerprint_prefix(imported.payload_sha256),
      import_mode: imported.import_mode,
      source: imported.source || %{},
      mutation: "none",
      workspace_id: imported.workspace_id,
      session_id: imported.session_id
    }
  end

  defp fingerprint_prefix(nil), do: nil
  defp fingerprint_prefix(value) when is_binary(value), do: String.slice(value, 0, 12)

  defp import_recommendations([]) do
    [
      "No persisted observability imports yet; use `controlkeel obs import <file> --persist` after verifying an envelope."
    ]
  end

  defp import_recommendations(imports) do
    []
    |> maybe_reason(
      Enum.any?(imports, &(&1.integrity_status != "verified")),
      "Review imports with non-verified integrity before using them as benchmark evidence."
    )
    |> maybe_reason(
      Enum.any?(imports, &((&1.problem_groups || 0) > 0)),
      "Convert recurring imported problem groups into eval or benchmark coverage."
    )
    |> case do
      [] -> ["Imported observability snapshots are verified and ready for trend analysis."]
      recommendations -> recommendations
    end
  end

  defp recent_sessions(opts, limit) do
    workspace_id = Keyword.get(opts, :workspace_id)

    Session
    |> maybe_filter_session_workspace(workspace_id)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp diagnostic_events(session_id, workspace_id, limit) do
    SessionEvent
    |> join(:left, [e], s in assoc(e, :session))
    |> maybe_filter_event_session(session_id)
    |> maybe_filter_event_workspace(workspace_id)
    |> order_by([e, _s], asc: e.inserted_at, asc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_event_session(query, nil), do: query

  defp maybe_filter_event_session(query, session_id),
    do: where(query, [e, _s], e.session_id == ^session_id)

  defp maybe_filter_event_workspace(query, nil), do: query

  defp maybe_filter_event_workspace(query, workspace_id),
    do: where(query, [_e, s], s.workspace_id == ^workspace_id)

  defp repeated_event_runs(events, limit) do
    events
    |> Enum.map(fn event ->
      %{
        key: event_key(event),
        event_type: event.event_type,
        actor: event.actor,
        summary: event.summary,
        session_id: event.session_id,
        task_id: event.task_id,
        inserted_at: event.inserted_at
      }
    end)
    |> repeated_runs(limit)
  end

  defp repeated_invocation_runs(invocations, limit) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        key: invocation_key(invocation),
        tool: invocation.tool,
        source: invocation.source,
        provider: invocation.provider,
        model: invocation.model,
        session_id: invocation.session_id,
        task_id: invocation.task_id,
        inserted_at: invocation.inserted_at
      }
    end)
    |> repeated_runs(limit)
  end

  defp repeated_runs(items, limit) do
    items
    |> Enum.chunk_by(& &1.key)
    |> Enum.filter(&(length(&1) >= 3))
    |> Enum.map(fn run ->
      first = List.first(run)
      last = List.last(run)

      %{
        key: first.key,
        count: length(run),
        first_at: first.inserted_at,
        last_at: last.inserted_at,
        sample: Map.drop(first, [:key, :inserted_at])
      }
    end)
    |> Enum.take(limit)
  end

  defp event_key(event) do
    [event.event_type, event.actor, event.summary]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(":")
  end

  defp invocation_key(invocation) do
    [invocation.source, invocation.tool, invocation.provider, invocation.model]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(":")
  end

  defp loop_diagnostic_recommendations([], []) do
    ["No repeated identical tool or invocation loops were detected in the sampled window."]
  end

  defp loop_diagnostic_recommendations(event_runs, invocation_runs) do
    []
    |> maybe_reason(
      event_runs != [],
      "Repeated identical session events detected; inspect for agent retry or stale-context loops."
    )
    |> maybe_reason(
      invocation_runs != [],
      "Repeated identical invocations detected; add a harness gate or memory note to avoid tool doom loops."
    )
  end

  defp maybe_filter_session_workspace(query, nil), do: query

  defp maybe_filter_session_workspace(query, workspace_id),
    do: where(query, [s], s.workspace_id == ^workspace_id)

  defp overview_run_summary(run) do
    %{
      id: run.session.id,
      title: run.session.title,
      objective: run.session.objective,
      workspace_id: run.session.workspace_id,
      workspace_name: run.session.workspace_name,
      health: run.health.status,
      health_label: run.health.label,
      active_findings: run.findings.active,
      blocked_findings: run.findings.blocked,
      pending_gates: run.gates.pending_reviews,
      timeline_events: run.timeline.count,
      memory_records: run.memory.records,
      proof_bundles: run.proofs.count,
      invocations: run.hosts_models_tools.invocations,
      estimated_cost_cents: run.hosts_models_tools.estimated_cost_cents,
      budget_spent_cents: run.budget["spent_cents"] || 0,
      budget_limit_cents: run.budget["session_budget_cents"] || 0,
      recommendations: Enum.take(run.recommendations, 2)
    }
  end

  defp overview_workspace([]), do: %{id: nil, name: "No workspace"}

  defp overview_workspace([run | _runs]) do
    %{id: run.workspace_id, name: run.workspace_name || "Workspace #{run.workspace_id}"}
  end

  defp overview_health(runs, problems) do
    status =
      cond do
        Enum.any?(runs, &(&1.health == "red")) or problems.health == "red" -> "red"
        Enum.any?(runs, &(&1.health == "yellow")) or problems.health == "yellow" -> "yellow"
        runs == [] -> "yellow"
        true -> "green"
      end

    %{
      status: status,
      label: health_label(status),
      run_count: length(runs),
      red_runs: Enum.count(runs, &(&1.health == "red")),
      yellow_runs: Enum.count(runs, &(&1.health == "yellow")),
      green_runs: Enum.count(runs, &(&1.health == "green"))
    }
  end

  defp overview_costs(runs) do
    %{
      spent_cents: Enum.reduce(runs, 0, &(&1.budget_spent_cents + &2)),
      budget_cents: Enum.reduce(runs, 0, &(&1.budget_limit_cents + &2)),
      estimated_invocation_cents: Enum.reduce(runs, 0, &(&1.estimated_cost_cents + &2)),
      invocations: Enum.reduce(runs, 0, &(&1.invocations + &2))
    }
  end

  defp loop_status_blockers(overview, problems, drafts, history, promotions) do
    []
    |> maybe_add_loop_blocker(
      overview.health.status == "red",
      "session_health",
      "Session health is red; clear critical/high findings or pending gates first."
    )
    |> maybe_add_loop_blocker(
      problems.total_findings > 0,
      "active_problems",
      "Active governed findings should become reviewed eval coverage before widening automation."
    )
    |> maybe_add_loop_blocker(
      Map.get(drafts.by_status, "draft", 0) > 0,
      "draft_review",
      "Benchmark drafts need human approval before materialization."
    )
    |> maybe_add_loop_blocker(
      history.readiness.status != "green",
      "benchmark_evidence",
      history.readiness.reason
    )
    |> maybe_add_loop_blocker(
      Map.get(promotions.by_readiness, "blocked", 0) > 0,
      "promotion_blocked",
      "Promotion candidates with incomplete or failed candidate-specific evidence remain blocked."
    )
  end

  defp maybe_add_loop_blocker(blockers, true, id, reason),
    do: [%{id: id, reason: reason} | blockers]

  defp maybe_add_loop_blocker(blockers, false, _id, _reason), do: blockers

  defp loop_status_health(%{status: "red"}, _history_readiness, _promotions, _blockers), do: "red"
  defp loop_status_health(_overview, %{status: "red"}, _promotions, _blockers), do: "red"

  defp loop_status_health(_overview, _history_readiness, promotions, _blockers) do
    cond do
      Map.get(promotions.by_readiness, "blocked", 0) > 0 -> "red"
      Map.get(promotions.by_readiness, "ready", 0) > 0 -> "green"
      promotions.count > 0 -> "yellow"
      true -> "yellow"
    end
  end

  defp loop_status_recommendations([], _history, promotions) do
    if Map.get(promotions.by_readiness, "ready", 0) > 0 do
      ["Review ready promotion candidates manually; no automatic mutation will occur."]
    else
      [
        "Keep using CK so findings, reviews, memory, and benchmark outcomes can become evidence for agent improvement."
      ]
    end
  end

  defp loop_status_recommendations(blockers, _history, _promotions) do
    [
      "Work blockers from top to bottom: active problems → saved evals → reviewed drafts → benchmark evidence → human promotion review.",
      "Agents should use this read-only loop status before proposing policy, prompt, routing, or skill changes."
    ] ++ Enum.map(blockers, & &1.reason)
  end

  defp overview_recommendations(health, runs, problems) do
    []
    |> maybe_reason(runs == [], "No session runs are available yet.")
    |> maybe_reason(
      health.status == "red",
      "Prioritize red session runs and blocked findings before widening automation."
    )
    |> maybe_reason(
      problems.count > 0,
      "Review grouped problems and convert recurring failures into eval coverage."
    )
    |> maybe_reason(
      Enum.any?(runs, &(&1.pending_gates > 0)),
      "Clear pending review gates before marking runs healthy."
    )
    |> maybe_reason(
      Enum.any?(runs, &(&1.proof_bundles == 0)),
      "Generate proof bundles for runs that need reproducible evidence."
    )
    |> case do
      [] -> ["Workspace observability is healthy."]
      recommendations -> Enum.take(recommendations ++ problems.recommendations, 5)
    end
  end

  # DB-side aggregate: returns one row per (rule_id, category) group with counts,
  # max severity, and last_seen — avoids loading all finding rows into memory.
  defp problem_aggregates(opts, limit) do
    session_id = Keyword.get(opts, :session_id)
    workspace_id = Keyword.get(opts, :workspace_id)

    base =
      from(f in Finding,
        join: s in assoc(f, :session),
        where: f.status in ^@active_finding_statuses,
        group_by: [f.rule_id, f.category],
        select: %{
          rule_id: f.rule_id,
          category: f.category,
          count: count(f.id),
          blocked_count: filter(count(f.id), f.status == "blocked"),
          escalated_count: filter(count(f.id), f.status == "escalated"),
          last_seen: max(f.inserted_at),
          affected_session_count: count(f.session_id, :distinct)
        }
      )

    base
    |> maybe_filter_aggregate_session(session_id)
    |> maybe_filter_aggregate_workspace(workspace_id)
    |> order_by([f, _s], desc: count(f.id))
    |> limit(^limit)
    |> Repo.all()
  end

  defp problem_total_count(opts) do
    session_id = Keyword.get(opts, :session_id)
    workspace_id = Keyword.get(opts, :workspace_id)

    base =
      from(f in Finding,
        join: s in assoc(f, :session),
        where: f.status in ^@active_finding_statuses,
        select: count(f.id)
      )

    base
    |> maybe_filter_aggregate_session(session_id)
    |> maybe_filter_aggregate_workspace(workspace_id)
    |> Repo.one() || 0
  end

  defp problem_examples(rule_id, category, opts, limit) do
    session_id = Keyword.get(opts, :session_id)
    workspace_id = Keyword.get(opts, :workspace_id)

    base =
      from(f in Finding,
        join: s in assoc(f, :session),
        where:
          f.status in ^@active_finding_statuses and f.rule_id == ^rule_id and
            f.category == ^category,
        preload: [session: s],
        order_by: [desc: f.inserted_at],
        limit: ^limit
      )

    base
    |> maybe_filter_aggregate_session(session_id)
    |> maybe_filter_aggregate_workspace(workspace_id)
    |> Repo.all()
  end

  defp maybe_filter_aggregate_session(query, nil), do: query

  defp maybe_filter_aggregate_session(query, session_id),
    do: where(query, [f, _s], f.session_id == ^session_id)

  defp maybe_filter_aggregate_workspace(query, nil), do: query

  defp maybe_filter_aggregate_workspace(query, workspace_id),
    do: where(query, [_f, s], s.workspace_id == ^workspace_id)

  defp maybe_filter_workspace(query, nil), do: query

  defp maybe_filter_workspace(query, workspace_id),
    do: where(query, [_f, s], s.workspace_id == ^workspace_id)

  defp cost_invocations(opts) do
    base = from(i in Invocation, join: s in assoc(i, :session), preload: [session: s])

    base
    |> maybe_filter_invocation_session(Keyword.get(opts, :session_id))
    |> maybe_filter_invocation_workspace(Keyword.get(opts, :workspace_id))
    |> order_by([i, _s], desc: i.inserted_at, desc: i.id)
    |> Repo.all()
  end

  defp maybe_filter_invocation_session(query, nil), do: query

  defp maybe_filter_invocation_session(query, session_id),
    do: where(query, [i, _s], i.session_id == ^session_id)

  defp maybe_filter_invocation_workspace(query, nil), do: query

  defp maybe_filter_invocation_workspace(query, workspace_id),
    do: where(query, [_i, s], s.workspace_id == ^workspace_id)

  defp normalize_cost_group(group) when group in @cost_group_fields, do: group
  defp normalize_cost_group(_group), do: "model"

  defp cost_totals(invocations) do
    %{
      invocations: length(invocations),
      estimated_cost_cents: sum_invocation_field(invocations, :estimated_cost_cents),
      input_tokens: sum_invocation_field(invocations, :input_tokens),
      cached_input_tokens: sum_invocation_field(invocations, :cached_input_tokens),
      output_tokens: sum_invocation_field(invocations, :output_tokens),
      sessions: invocations |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()
    }
  end

  defp cost_groups(invocations, by) do
    invocations
    |> Enum.group_by(&cost_group_value(&1, by))
    |> Enum.map(fn {name, group} ->
      %{
        name: name,
        invocations: length(group),
        estimated_cost_cents: sum_invocation_field(group, :estimated_cost_cents),
        input_tokens: sum_invocation_field(group, :input_tokens),
        cached_input_tokens: sum_invocation_field(group, :cached_input_tokens),
        output_tokens: sum_invocation_field(group, :output_tokens),
        sessions: group |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()
      }
    end)
    |> Enum.sort_by(&{&1.estimated_cost_cents, &1.invocations}, :desc)
  end

  defp comparison_groups(invocations, by) do
    invocations
    |> Enum.group_by(&cost_group_value(&1, by))
    |> Enum.map(fn {name, group} ->
      total_cost = sum_invocation_field(group, :estimated_cost_cents)
      total_tokens = total_tokens(group)
      invocation_count = length(group)

      %{
        name: name,
        invocations: invocation_count,
        sessions: group |> Enum.map(& &1.session_id) |> Enum.uniq() |> length(),
        estimated_cost_cents: total_cost,
        input_tokens: sum_invocation_field(group, :input_tokens),
        cached_input_tokens: sum_invocation_field(group, :cached_input_tokens),
        output_tokens: sum_invocation_field(group, :output_tokens),
        total_tokens: total_tokens,
        cost_per_call_cents: ratio(total_cost, invocation_count),
        tokens_per_call: ratio(total_tokens, invocation_count),
        decisions: frequencies(group, &(&1.decision || "unknown"))
      }
    end)
    |> Enum.sort_by(&{&1.estimated_cost_cents, &1.invocations}, :desc)
  end

  defp cost_group_value(invocation, "model"), do: invocation.model || "unknown"
  defp cost_group_value(invocation, "tool"), do: invocation.tool || "unknown"
  defp cost_group_value(invocation, "source"), do: invocation.source || "unknown"
  defp cost_group_value(invocation, "provider"), do: invocation.provider || "unknown"

  defp sum_invocation_field(invocations, field) do
    Enum.reduce(invocations, 0, &((Map.get(&1, field) || 0) + &2))
  end

  defp total_tokens(invocations) do
    sum_invocation_field(invocations, :input_tokens) +
      sum_invocation_field(invocations, :cached_input_tokens) +
      sum_invocation_field(invocations, :output_tokens)
  end

  defp ratio(_numerator, 0), do: 0.0
  defp ratio(numerator, denominator), do: Float.round(numerator / denominator, 2)

  defp cost_recommendations(%{invocations: 0}, _groups, _by),
    do: ["No invocation cost data has been recorded yet."]

  defp cost_recommendations(totals, groups, by) do
    top_group = List.first(groups)

    []
    |> maybe_reason(
      totals.cached_input_tokens == 0 and totals.input_tokens > 0,
      "No cached input tokens recorded; check whether repeated context can be reused."
    )
    |> maybe_top_cost_reason(top_group, totals, by)
    |> maybe_reason(
      totals.estimated_cost_cents > 0 and totals.invocations > 0,
      "Track cost per successful task once outcomes are available for these invocations."
    )
    |> case do
      [] -> ["Invocation cost distribution looks balanced."]
      recommendations -> recommendations
    end
  end

  defp comparison_recommendations([], _by),
    do: ["No invocation data is available for comparison yet."]

  defp comparison_recommendations(groups, by) do
    top_cost = List.first(groups)
    lowest_cost = Enum.min_by(groups, & &1.cost_per_call_cents, fn -> nil end)

    []
    |> maybe_reason(
      length(groups) > 1 and top_cost != nil,
      "Compare #{by} #{top_cost.name} against lower-cost groups before scaling similar work."
    )
    |> maybe_reason(
      lowest_cost != nil,
      "Lowest observed cost per call is #{lowest_cost.cost_per_call_cents} cent(s) for #{by} #{lowest_cost.name}."
    )
  end

  defp maybe_top_cost_reason(recommendations, nil, _totals, _by), do: recommendations

  defp maybe_top_cost_reason(recommendations, top_group, totals, by) do
    maybe_reason(
      recommendations,
      top_group.estimated_cost_cents > div(totals.estimated_cost_cents, 2),
      "Most estimated spend is concentrated in #{by} #{top_group.name}; compare it against cheaper alternatives before scaling similar runs."
    )
  end

  defp average_value([]), do: 0.0

  defp average_value(values) do
    values = Enum.reject(values, &is_nil/1)

    case values do
      [] -> 0.0
      values -> Enum.sum(values) / length(values)
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _other -> {:error, :invalid_id}
    end
  end

  defp parse_id(_id), do: {:error, :invalid_id}

  defp benchmark_run_records(days, limit) do
    since = DateTime.add(DateTime.utc_now(), -max(days, 1) * 86_400, :second)

    BenchmarkRun
    |> where([run], run.inserted_at >= ^since)
    |> order_by([run], desc: run.inserted_at, desc: run.id)
    |> limit(^limit)
    |> preload([:suite, results: []])
    |> Repo.all()
  end

  defp benchmark_run_summary(%BenchmarkRun{} = run) do
    %{
      id: run.id,
      status: run.status,
      suite: benchmark_run_suite_slug(run),
      baseline_subject: run.baseline_subject,
      subjects: run.subjects || [],
      total_scenarios: run.total_scenarios,
      caught_count: run.caught_count,
      blocked_count: run.blocked_count,
      catch_rate: run.catch_rate || 0.0,
      median_latency_ms: run.median_latency_ms,
      average_overhead_percent: run.average_overhead_percent,
      result_count: length(run.results || []),
      inserted_at: format_datetime(run.inserted_at),
      finished_at: format_datetime(run.finished_at)
    }
  end

  defp benchmark_run_suite_slug(%BenchmarkRun{suite: %{slug: slug}}) when is_binary(slug),
    do: slug

  defp benchmark_run_suite_slug(_run), do: "unknown"

  defp regression_health([], %{count: draft_count}, %{count: saved_count})
       when draft_count > 0 or saved_count > 0 do
    %{
      status: "yellow",
      reason:
        "Eval candidates or benchmark drafts exist, but no recent benchmark run closes the loop."
    }
  end

  defp regression_health([], _drafts, _saved) do
    %{status: "green", reason: "No recent benchmark regressions recorded."}
  end

  defp regression_health(runs, _drafts, _saved) do
    latest = List.first(runs)
    average_catch_rate = average_value(Enum.map(runs, &(&1.catch_rate || 0.0)))

    cond do
      (latest.catch_rate || 0.0) < 100.0 ->
        %{status: "red", reason: "Latest benchmark run did not catch every expected scenario."}

      average_catch_rate < 100.0 ->
        %{
          status: "yellow",
          reason: "Recent benchmark history includes missed expected scenarios."
        }

      true ->
        %{status: "green", reason: "Recent benchmark runs are fully catching expected scenarios."}
    end
  end

  defp regression_recommendations([], %{count: draft_count}, _saved) when draft_count > 0,
    do: [
      "Review benchmark drafts and run an approved benchmark suite to establish regression history."
    ]

  defp regression_recommendations([], _drafts, %{count: saved_count}) when saved_count > 0,
    do: [
      "Generate benchmark drafts from saved eval candidates before regression tracking can compare runs."
    ]

  defp regression_recommendations([], _drafts, _saved),
    do: ["No regression action is needed until eval candidates or benchmark drafts exist."]

  defp regression_recommendations(runs, drafts, _saved) do
    latest = List.first(runs)
    recommendations = []

    recommendations =
      maybe_reason(
        recommendations,
        (latest.catch_rate || 0.0) < 100.0,
        "Investigate latest benchmark misses before promoting policy, prompt, or routing changes."
      )

    recommendations =
      maybe_reason(
        recommendations,
        drafts.count > 0,
        "Keep benchmark drafts linked to saved eval candidates so reviewed failure patterns become regression coverage."
      )

    if recommendations == [] do
      [
        "Recent benchmark runs look healthy; keep tracking regressions after each self-improvement change."
      ]
    else
      recommendations
    end
  end

  defp benchmark_draft_records(opts, limit) do
    BenchmarkDraft
    |> maybe_filter_draft_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_draft_status(Keyword.get(opts, :status))
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp benchmark_draft_count(opts) do
    BenchmarkDraft
    |> maybe_filter_draft_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_draft_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_draft_workspace(query, nil), do: query

  defp maybe_filter_draft_workspace(query, workspace_id),
    do: where(query, [d], d.workspace_id == ^workspace_id)

  defp maybe_filter_draft_status(query, nil), do: query
  defp maybe_filter_draft_status(query, status), do: where(query, [d], d.status == ^status)

  defp generate_benchmark_draft(%EvalCandidate{} = candidate) do
    case Repo.get_by(BenchmarkDraft, eval_candidate_id: candidate.id) do
      %BenchmarkDraft{} = existing ->
        {:existing, existing}

      nil ->
        %BenchmarkDraft{}
        |> BenchmarkDraft.changeset(benchmark_draft_attrs(candidate))
        |> Repo.insert()
        |> case do
          {:ok, draft} ->
            {:stored, draft}

          {:error, changeset} ->
            raise "failed to save benchmark draft: #{inspect(changeset.errors)}"
        end
    end
  end

  defp materialize_benchmark_draft(%BenchmarkDraft{} = draft) do
    case get_in(draft.metadata || %{}, ["materialized_scenario_id"]) do
      scenario_id when is_integer(scenario_id) ->
        case Repo.get(Scenario, scenario_id) |> Repo.preload(:suite) do
          %Scenario{} = scenario -> {:existing, scenario}
          nil -> create_observability_scenario(draft)
        end

      _other ->
        create_observability_scenario(draft)
    end
  end

  defp create_observability_scenario(%BenchmarkDraft{} = draft) do
    suite = ensure_observability_suite(draft)
    slug = "observability-draft-#{draft.id}"

    case Repo.get_by(Scenario, suite_id: suite.id, slug: slug) |> Repo.preload(:suite) do
      %Scenario{} = existing ->
        update_draft_materialized_metadata(draft, existing)
        {:existing, existing}

      nil ->
        position =
          Repo.aggregate(from(s in Scenario, where: s.suite_id == ^suite.id), :count, :id)

        %Scenario{}
        |> Scenario.changeset(%{
          suite_id: suite.id,
          slug: slug,
          name: draft.title,
          category: draft.benchmark_hint || draft.suite_slug,
          incident_label: draft.title,
          path: "observability/benchmark_drafts/#{draft.id}",
          kind: "text",
          content: draft.scenario_prompt,
          expected_rules: expected_rules_for_draft(draft),
          expected_decision: "warn",
          position: position,
          split: "local",
          metadata: %{
            "source" => "observability_benchmark_draft",
            "benchmark_draft_id" => draft.id,
            "eval_candidate_id" => draft.eval_candidate_id,
            "expected_behavior" => draft.expected_behavior,
            "evidence_summary" => draft.evidence_summary,
            "human_gate_required" => draft.human_gate_required
          }
        })
        |> Repo.insert!()
        |> Repo.preload(:suite)
        |> then(fn scenario ->
          update_draft_materialized_metadata(draft, scenario)
          {:materialized, scenario}
        end)
    end
  end

  defp ensure_observability_suite(%BenchmarkDraft{} = draft) do
    slug = "observability-#{draft.suite_slug}"

    case Repo.get_by(Suite, slug: slug) do
      %Suite{} = suite ->
        suite

      nil ->
        %Suite{}
        |> Suite.changeset(%{
          slug: slug,
          name: "Observability #{draft.suite_slug}",
          description:
            "Local generated suite from approved ControlKeel observability benchmark drafts.",
          version: 1,
          status: "active",
          metadata: %{
            "source" => "observability_benchmark_drafts",
            "human_gate_required" => true,
            "benchmark_execution" => false
          }
        })
        |> Repo.insert!()
    end
  end

  defp expected_rules_for_draft(%BenchmarkDraft{} = draft) do
    draft.metadata
    |> Kernel.||(%{})
    |> Map.get("candidate_rule_id")
    |> case do
      rule_id when is_binary(rule_id) and rule_id != "" -> [rule_id]
      _ -> []
    end
  end

  defp update_draft_materialized_metadata(%BenchmarkDraft{} = draft, %Scenario{} = scenario) do
    metadata =
      draft.metadata
      |> Kernel.||(%{})
      |> Map.put("materialized_scenario_id", scenario.id)
      |> Map.put("materialized_suite_id", scenario.suite_id)
      |> Map.put(
        "materialized_at",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    draft
    |> BenchmarkDraft.changeset(%{metadata: metadata})
    |> Repo.update!()
  end

  defp observability_scenario_records(opts, limit) do
    Scenario
    |> join(:inner, [s], suite in assoc(s, :suite))
    |> where(
      [s, _suite],
      json_extract_path(s.metadata, ["source"]) == "observability_benchmark_draft"
    )
    |> maybe_filter_observability_scenario_workspace(Keyword.get(opts, :workspace_id))
    |> preload([_s, suite], suite: suite)
    |> order_by([s, _suite], desc: s.inserted_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp observability_scenario_count(opts) do
    Scenario
    |> join(:inner, [s], suite in assoc(s, :suite))
    |> where(
      [s, _suite],
      json_extract_path(s.metadata, ["source"]) == "observability_benchmark_draft"
    )
    |> maybe_filter_observability_scenario_workspace(Keyword.get(opts, :workspace_id))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_observability_scenario_workspace(query, nil), do: query

  defp maybe_filter_observability_scenario_workspace(query, workspace_id) do
    draft_ids =
      BenchmarkDraft
      |> where([d], d.workspace_id == ^workspace_id)
      |> select([d], d.id)
      |> Repo.all()

    where(
      query,
      [s, _suite],
      json_extract_path(s.metadata, ["benchmark_draft_id"]) in ^draft_ids
    )
  end

  defp observability_scenario_summary(%Scenario{} = scenario) do
    %{
      id: scenario.id,
      slug: scenario.slug,
      name: scenario.name,
      suite_id: scenario.suite_id,
      suite_slug: observability_scenario_suite_slug(scenario),
      category: scenario.category,
      expected_rules: scenario.expected_rules || [],
      expected_decision: scenario.expected_decision,
      split: scenario.split,
      metadata: scenario.metadata || %{},
      inserted_at: format_datetime(scenario.inserted_at)
    }
  end

  defp observability_scenario_suite_slug(%Scenario{suite: %Suite{slug: slug}}), do: slug
  defp observability_scenario_suite_slug(_scenario), do: "unknown"

  defp observability_scenario_recommendations([]),
    do: [
      "No materialized observability benchmark scenarios yet; approve drafts and materialize them before execution."
    ]

  defp observability_scenario_recommendations(scenarios) do
    [
      "Review #{length(scenarios)} materialized scenario(s) before running benchmark suites.",
      "Benchmark execution remains separate and should stay human-gated."
    ]
  end

  defp observability_benchmark_run_records([], _limit), do: []

  defp observability_benchmark_run_records(scenarios, limit) do
    suite_ids = scenarios |> Enum.map(& &1.suite_id) |> Enum.uniq()
    scenario_ids = scenarios |> Enum.map(& &1.id) |> MapSet.new()

    BenchmarkRun
    |> where([run], run.suite_id in ^suite_ids)
    |> order_by([run], desc: run.inserted_at, desc: run.id)
    |> limit(^limit)
    |> preload([:suite, results: [:scenario]])
    |> Repo.all()
    |> Enum.map(fn run ->
      results = Enum.filter(run.results || [], &MapSet.member?(scenario_ids, &1.scenario_id))
      %{run | results: results}
    end)
    |> Enum.reject(&(&1.results == []))
  end

  defp observability_benchmark_history_run_summary(%BenchmarkRun{} = run) do
    detail = Benchmark.run_detail_metrics(run)

    %{
      id: run.id,
      status: run.status,
      suite: benchmark_run_suite_slug(run),
      subjects: run.subjects || [],
      total_scenarios: run.total_scenarios,
      observed_scenarios: run.results |> Enum.map(& &1.scenario_id) |> Enum.uniq() |> length(),
      caught_count: run.caught_count,
      blocked_count: run.blocked_count,
      catch_rate: run.catch_rate || 0.0,
      block_rate: detail.block_rate,
      expected_rule_hit_rate: detail.expected_rule_hit_rate,
      inserted_at: format_datetime(run.inserted_at),
      finished_at: format_datetime(run.finished_at)
    }
  end

  defp observability_benchmark_missed_summaries(runs) do
    runs
    |> Enum.flat_map(&(&1.results || []))
    |> Enum.reject(& &1.matched_expected)
    |> Enum.take(10)
    |> Enum.map(fn result ->
      %{
        run_id: result.run_id,
        scenario_id: result.scenario_id,
        scenario_slug: if(result.scenario, do: result.scenario.slug, else: nil),
        subject: result.subject,
        status: result.status,
        decision: result.decision,
        expected_rules: if(result.scenario, do: result.scenario.expected_rules || [], else: [])
      }
    end)
  end

  defp observability_benchmark_readiness(nil, %{materialized_scenarios: materialized})
       when materialized > 0,
       do: %{
         status: "yellow",
         reason:
           "Materialized observability scenarios exist, but none have benchmark run evidence yet."
       }

  defp observability_benchmark_readiness(nil, _coverage),
    do: %{status: "red", reason: "No materialized observability benchmark scenarios exist yet."}

  defp observability_benchmark_readiness(run, coverage) do
    cond do
      coverage.covered_scenarios < coverage.materialized_scenarios ->
        %{
          status: "yellow",
          reason:
            "Some materialized observability scenarios are not covered by recent benchmark runs."
        }

      (run.catch_rate || 0.0) < 100.0 ->
        %{status: "red", reason: "Latest observability benchmark run missed expected coverage."}

      true ->
        %{
          status: "green",
          reason: "Latest observability benchmark evidence covers materialized scenarios."
        }
    end
  end

  defp observability_benchmark_history_recommendations(nil, %{materialized_scenarios: 0}),
    do: ["Approve and materialize benchmark drafts before regression history can be established."]

  defp observability_benchmark_history_recommendations(nil, _coverage),
    do: [
      "Run `controlkeel obs benchmarks run --dry-run` first, then execute a reviewed generated suite from the CLI."
    ]

  defp observability_benchmark_history_recommendations(run, coverage) do
    []
    |> maybe_reason(
      coverage.covered_scenarios < coverage.materialized_scenarios,
      "Run uncovered generated scenarios before using this evidence for promotion decisions."
    )
    |> maybe_reason(
      (run.catch_rate || 0.0) < 100.0,
      "Investigate missed observability benchmark scenarios before promotion or autofix work."
    )
    |> case do
      [] ->
        [
          "Observability benchmark history is ready for human review before any promotion workflow."
        ]

      recommendations ->
        recommendations
    end
  end

  defp normalize_observability_scenario_slugs(nil), do: []

  defp normalize_observability_scenario_slugs(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_observability_scenario_slugs(value) when is_list(value), do: value
  defp normalize_observability_scenario_slugs(_value), do: []

  defp maybe_filter_observability_scenarios_by_suite(scenarios, nil), do: scenarios

  defp maybe_filter_observability_scenarios_by_suite(scenarios, suite_slug),
    do: Enum.filter(scenarios, &(observability_scenario_suite_slug(&1) == suite_slug))

  defp maybe_filter_observability_scenarios_by_slugs(scenarios, []), do: scenarios

  defp maybe_filter_observability_scenarios_by_slugs(scenarios, slugs),
    do: Enum.filter(scenarios, &(&1.slug in slugs))

  defp single_suite([suite]), do: suite
  defp single_suite(_suites), do: nil

  defp subjects_present?(subjects) when is_binary(subjects), do: String.trim(subjects) != ""
  defp subjects_present?(_subjects), do: false

  defp observability_benchmark_run_command(nil, _scenarios, _subjects), do: nil

  defp observability_benchmark_run_command(suite, scenarios, subjects) do
    scenario_part =
      case Enum.map(scenarios, & &1.slug) do
        [] -> ""
        slugs -> " --scenario-slugs #{Enum.join(slugs, ",")}"
      end

    subject_part =
      if subjects_present?(subjects),
        do: " --subjects #{subjects}",
        else: " --subjects <subject_ids>"

    "controlkeel obs benchmarks run --suite #{suite}#{subject_part}#{scenario_part} --execute"
  end

  defp observability_run_recommendations(nil, [], _scenarios, _subjects),
    do: ["No materialized observability benchmark scenarios are available to run."]

  defp observability_run_recommendations(nil, suites, _scenarios, _subjects),
    do: ["Choose one observability suite before execution: #{Enum.join(suites, ", ")}."]

  defp observability_run_recommendations(_suite, _suites, [], _subjects),
    do: ["No scenarios match the selected observability benchmark filters."]

  defp observability_run_recommendations(_suite, _suites, _scenarios, subjects)
       when not is_binary(subjects) or subjects == "",
       do: [
         "Add --subjects before execution; use --dry-run to inspect generated scenarios first."
       ]

  defp observability_run_recommendations(_suite, _suites, scenarios, _subjects),
    do: [
      "Dry-run reviewed #{length(scenarios)} generated observability scenario(s).",
      "Execution is CLI-only and still requires explicit operator intent."
    ]

  defp observability_benchmark_run_result(run, preview) do
    detail = Benchmark.run_detail_metrics(run)

    %{
      run_id: run.id,
      suite: run.suite.slug,
      subjects: run.subjects || [],
      status: run.status,
      total_scenarios: run.total_scenarios,
      catch_rate: run.catch_rate,
      block_rate: detail.block_rate,
      expected_rule_hit_rate: detail.expected_rule_hit_rate,
      benchmark_execution: true,
      mutation: "benchmark_run_record",
      preview: preview
    }
  end

  defp promotion_candidate_summary(%EvalCandidate{} = candidate, draft, history) do
    materialized_scenario_id =
      if draft, do: get_in(draft.metadata || %{}, ["materialized_scenario_id"])

    evidence = promotion_candidate_evidence(materialized_scenario_id)
    readiness = promotion_candidate_readiness(draft, materialized_scenario_id, evidence, history)

    %{
      id: candidate.id,
      title: candidate.title,
      rule_id: candidate.rule_id,
      category: candidate.category,
      priority: candidate.priority,
      status: candidate.status,
      readiness: readiness,
      source_eval_candidate_id: candidate.id,
      benchmark_draft_id: if(draft, do: draft.id, else: nil),
      benchmark_draft_status: if(draft, do: draft.status, else: nil),
      materialized_scenario_id: materialized_scenario_id,
      latest_run_id: evidence.latest_run_id,
      latest_result_id: evidence.latest_result_id,
      scenario_evidence: evidence,
      evidence_summary: candidate.evidence_summary,
      suggested_action: promotion_candidate_action(readiness, candidate),
      promotion_execution: false,
      human_gate_required: true
    }
  end

  defp promotion_candidate_readiness(nil, _scenario_id, _evidence, _history), do: "needs_draft"

  defp promotion_candidate_readiness(
         %BenchmarkDraft{status: status},
         _scenario_id,
         _evidence,
         _history
       )
       when status != "approved", do: "needs_approval"

  defp promotion_candidate_readiness(_draft, nil, _evidence, _history),
    do: "needs_materialization"

  defp promotion_candidate_readiness(_draft, _scenario_id, %{scenario_covered: false}, _history),
    do: "needs_run"

  defp promotion_candidate_readiness(
         _draft,
         _scenario_id,
         %{matched_expected: true, run_status: status},
         _history
       )
       when status in ["completed", "passed"],
       do: "ready"

  defp promotion_candidate_readiness(_draft, _scenario_id, _evidence, _history), do: "blocked"

  defp promotion_candidate_action("ready", candidate),
    do:
      "Human review may consider promotion evidence for #{candidate.rule_id}; no automatic mutation will occur."

  defp promotion_candidate_action("needs_draft", _candidate),
    do: "Generate a benchmark draft from saved eval candidates."

  defp promotion_candidate_action("needs_approval", _candidate),
    do: "Approve the benchmark draft with a human gate before materialization."

  defp promotion_candidate_action("needs_materialization", _candidate),
    do: "Materialize the approved draft into local benchmark scenarios."

  defp promotion_candidate_action("needs_run", _candidate),
    do: "Run generated observability benchmarks from the CLI after dry-run review."

  defp promotion_candidate_action("blocked", _candidate),
    do: "Investigate failed or incomplete benchmark evidence before promotion review."

  defp promotion_candidate_evidence(nil) do
    %{
      scenario_covered: false,
      latest_run_id: nil,
      latest_result_id: nil,
      matched_expected: false,
      run_status: nil,
      result_status: nil,
      decision: nil,
      catch_rate: nil
    }
  end

  defp promotion_candidate_evidence(scenario_id) when is_integer(scenario_id) do
    case latest_result_for_scenario(scenario_id) do
      %Result{} = result ->
        run = result.run

        %{
          scenario_covered: true,
          latest_run_id: run && run.id,
          latest_result_id: result.id,
          matched_expected: result.matched_expected == true,
          run_status: run && run.status,
          result_status: result.status,
          decision: result.decision,
          catch_rate: if(run, do: run.catch_rate || 0.0, else: nil)
        }

      nil ->
        promotion_candidate_evidence(nil)
    end
  end

  defp promotion_candidate_evidence(_scenario_id), do: promotion_candidate_evidence(nil)

  defp latest_result_for_scenario(scenario_id) do
    Result
    |> where([r], r.scenario_id == ^scenario_id)
    |> join(:inner, [r], run in assoc(r, :run))
    |> order_by([_r, run], desc: run.inserted_at, desc: run.id)
    |> preload([_r, run], run: run)
    |> limit(1)
    |> Repo.one()
  end

  defp promotion_candidate_recommendations([], _history),
    do: [
      "No promotion candidates yet; save eval candidates and establish benchmark evidence first."
    ]

  defp promotion_candidate_recommendations(items, _history) do
    ready = Enum.count(items, &(&1.readiness == "ready"))
    blocked = length(items) - ready

    []
    |> maybe_reason(
      ready > 0,
      "#{ready} candidate(s) have benchmark evidence ready for human promotion review."
    )
    |> maybe_reason(
      blocked > 0,
      "#{blocked} candidate(s) still need approval, materialization, successful runs, or investigation."
    )
  end

  defp update_benchmark_draft_record(%BenchmarkDraft{} = draft, status, opts) do
    reviewed_by = Keyword.get(opts, :reviewed_by, "local_user")

    metadata =
      draft.metadata
      |> Kernel.||(%{})
      |> Map.put("reviewed_by", reviewed_by)
      |> Map.put(
        "reviewed_at",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    draft
    |> BenchmarkDraft.changeset(%{status: status, metadata: metadata})
    |> Repo.update()
  end

  defp benchmark_draft_status_result(%BenchmarkDraft{} = draft) do
    %{
      status: draft.status,
      draft: benchmark_draft_summary(draft),
      human_gate_required: draft.human_gate_required,
      mutation: "draft_status_only"
    }
  end

  defp benchmark_draft_attrs(%EvalCandidate{} = candidate) do
    suite_slug = benchmark_suite_slug(candidate)
    trace_evidence = benchmark_trace_evidence(candidate)

    %{
      title: "Benchmark draft for #{candidate.rule_id}",
      suite_slug: suite_slug,
      scenario_prompt: benchmark_scenario_prompt(candidate, trace_evidence),
      expected_behavior: benchmark_expected_behavior(candidate),
      evidence_summary: candidate.evidence_summary,
      benchmark_hint: candidate.benchmark_hint,
      status: "draft",
      human_gate_required: true,
      workspace_id: candidate.workspace_id,
      eval_candidate_id: candidate.id,
      metadata: %{
        "candidate_rule_id" => candidate.rule_id,
        "candidate_priority" => candidate.priority,
        "candidate_status" => candidate.status,
        "candidate_source_problem_key" => candidate.source_problem_key,
        "example_session_id" => candidate.session_id,
        "example_finding_id" => candidate.finding_id,
        "trace_evidence" => trace_evidence,
        "suggested_action" => candidate.suggested_action
      }
    }
  end

  defp benchmark_suite_slug(%EvalCandidate{benchmark_hint: hint})
       when is_binary(hint) and hint != "" do
    hint
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(&if(&1 == "", do: "observability-regression", else: &1))
  end

  defp benchmark_suite_slug(%EvalCandidate{category: category})
       when is_binary(category) and category != "" do
    "#{category}-regression"
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
  end

  defp benchmark_suite_slug(_candidate), do: "observability-regression"

  defp benchmark_scenario_prompt(candidate, %{"available" => true} = trace_evidence) do
    "Reproduce the governed failure pattern for #{candidate.rule_id} using bounded real trace evidence from session #{trace_evidence["session_id"]}: #{candidate.evidence_summary || "No evidence summary recorded."} Trace evidence includes decision-time findings, reviews, events, and verification state in draft metadata.trace_evidence."
  end

  defp benchmark_scenario_prompt(candidate, _trace_evidence) do
    "Reproduce the governed failure pattern for #{candidate.rule_id} using bounded evidence: #{candidate.evidence_summary || "No evidence summary recorded."}"
  end

  defp benchmark_trace_evidence(%EvalCandidate{session_id: session_id})
       when is_integer(session_id) do
    case Mission.trace_improvement_packet(session_id, events_limit: 10) do
      {:ok, packet} ->
        %{
          "available" => true,
          "session_id" => packet["session_id"],
          "task_id" => packet["task_id"],
          "trace_summary" => packet["trace_summary"],
          "failure_patterns" => Enum.take(packet["failure_patterns"] || [], 5),
          "findings" => packet |> get_in(["trace", "findings"]) |> List.wrap() |> Enum.take(5),
          "reviews" => packet |> get_in(["trace", "reviews"]) |> List.wrap() |> Enum.take(5),
          "recent_events" =>
            packet |> get_in(["trace", "recent_events"]) |> List.wrap() |> Enum.take(10),
          "verification_assessment" => packet["verification_assessment"]
        }

      _ ->
        %{"available" => false, "reason" => "trace_packet_unavailable"}
    end
  rescue
    _ -> %{"available" => false, "reason" => "trace_packet_error"}
  end

  defp benchmark_trace_evidence(_candidate), do: %{"available" => false, "reason" => "no_session"}

  defp benchmark_expected_behavior(candidate) do
    "A governed agent should detect or prevent #{candidate.rule_id}, preserve human approval gates, and avoid regressions before promotion. Suggested action: #{candidate.suggested_action || "review candidate evidence"}."
  end

  defp benchmark_draft_summary(%BenchmarkDraft{} = draft) do
    %{
      id: draft.id,
      title: draft.title,
      suite_slug: draft.suite_slug,
      scenario_prompt: draft.scenario_prompt,
      expected_behavior: draft.expected_behavior,
      evidence_summary: draft.evidence_summary,
      benchmark_hint: draft.benchmark_hint,
      status: draft.status,
      human_gate_required: draft.human_gate_required,
      workspace_id: draft.workspace_id,
      eval_candidate_id: draft.eval_candidate_id,
      metadata: draft.metadata || %{},
      inserted_at: format_datetime(draft.inserted_at)
    }
  end

  defp benchmark_draft_recommendations([]),
    do: [
      "No benchmark drafts yet; generate drafts from saved eval candidates before running benchmark coverage."
    ]

  defp benchmark_draft_recommendations(drafts) do
    draft_count = Enum.count(drafts, &(&1.status == "draft"))

    []
    |> maybe_reason(
      draft_count > 0,
      "Review #{draft_count} draft benchmark scenario(s) with a human gate before execution."
    )
    |> maybe_reason(
      Enum.any?(drafts, & &1.human_gate_required),
      "Keep benchmark drafts human-gated until scenario expectations are approved."
    )
    |> case do
      [] -> ["Benchmark drafts are triaged."]
      recommendations -> recommendations
    end
  end

  defp saved_eval_candidate_records(opts, limit) do
    EvalCandidate
    |> maybe_filter_eval_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_eval_status(Keyword.get(opts, :status))
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp saved_eval_candidate_count(opts) do
    EvalCandidate
    |> maybe_filter_eval_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_eval_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_eval_workspace(query, nil), do: query

  defp maybe_filter_eval_workspace(query, workspace_id),
    do: where(query, [c], c.workspace_id == ^workspace_id)

  defp maybe_filter_eval_status(query, nil), do: query
  defp maybe_filter_eval_status(query, status), do: where(query, [c], c.status == ^status)

  defp save_eval_candidate(candidate, workspace_id) do
    source_problem_key = eval_candidate_source_key(candidate)

    case Repo.get_by(EvalCandidate,
           workspace_id: workspace_id,
           source_problem_key: source_problem_key
         ) do
      %EvalCandidate{} = existing ->
        {:existing, existing}

      nil ->
        %EvalCandidate{}
        |> EvalCandidate.changeset(
          eval_candidate_attrs(candidate, workspace_id, source_problem_key)
        )
        |> Repo.insert()
        |> case do
          {:ok, record} ->
            {:stored, record}

          {:error, changeset} ->
            raise "failed to save eval candidate: #{inspect(changeset.errors)}"
        end
    end
  end

  defp eval_candidate_attrs(candidate, workspace_id, source_problem_key) do
    %{
      title: candidate.title,
      rule_id: candidate.rule_id,
      category: candidate.category,
      severity: candidate.severity,
      priority: candidate.priority,
      evidence_kind: candidate.evidence_kind,
      evidence_summary: candidate.evidence_summary,
      suggested_action: candidate.suggested_action,
      benchmark_hint: candidate.benchmark_hint,
      source_problem_key: source_problem_key,
      status: "open",
      human_gate_required: true,
      workspace_id: workspace_id,
      session_id: candidate.example_session_id,
      finding_id: candidate.example_finding_id,
      metadata: %{
        "affected_session_count" => candidate.affected_session_count,
        "finding_count" => candidate.finding_count,
        "derived_id" => candidate.id,
        "links" => candidate.links
      }
    }
  end

  defp eval_candidate_source_key(candidate) do
    [candidate.rule_id, candidate.category, candidate.severity]
    |> Enum.map(&to_string(&1 || "unknown"))
    |> Enum.join(":")
  end

  defp saved_eval_candidate_summary(%EvalCandidate{} = candidate) do
    %{
      id: candidate.id,
      title: candidate.title,
      rule_id: candidate.rule_id,
      category: candidate.category,
      severity: candidate.severity,
      priority: candidate.priority,
      evidence_kind: candidate.evidence_kind,
      evidence_summary: candidate.evidence_summary,
      suggested_action: candidate.suggested_action,
      benchmark_hint: candidate.benchmark_hint,
      source_problem_key: candidate.source_problem_key,
      status: candidate.status,
      human_gate_required: candidate.human_gate_required,
      workspace_id: candidate.workspace_id,
      session_id: candidate.session_id,
      finding_id: candidate.finding_id,
      metadata: candidate.metadata || %{},
      inserted_at: format_datetime(candidate.inserted_at)
    }
  end

  defp saved_eval_candidate_recommendations([]),
    do: [
      "No saved eval candidates yet; save advisory candidates before generating benchmark coverage."
    ]

  defp saved_eval_candidate_recommendations(candidates) do
    open = Enum.count(candidates, &(&1.status == "open"))
    high = Enum.count(candidates, &(&1.priority in ["critical", "high"]))

    []
    |> maybe_reason(
      open > 0,
      "Review #{open} open saved eval candidate(s) with a human gate before benchmark generation."
    )
    |> maybe_reason(
      high > 0,
      "Prioritize #{high} critical/high saved candidate(s) for regression coverage."
    )
    |> case do
      [] -> ["Saved eval candidates are triaged."]
      recommendations -> recommendations
    end
  end

  defp add_health_actions(actions, overview) do
    actions
    |> maybe_action(
      overview.health.status == "red",
      %{
        id: "health-red-runs",
        title: "Prioritize red session runs",
        category: "health",
        priority: "critical",
        source: "workspace",
        evidence:
          "#{overview.health.red_runs} red run(s), #{overview.problems.total_findings} active finding(s).",
        suggested_action: "Open affected runs and clear blocked findings or review gates.",
        link: "/observability",
        human_gate_required: true
      }
    )
    |> maybe_action(
      overview.health.status == "yellow",
      %{
        id: "health-yellow-runs",
        title: "Review yellow session runs",
        category: "health",
        priority: "medium",
        source: "workspace",
        evidence:
          "#{overview.health.yellow_runs} yellow run(s), #{overview.health.green_runs} green run(s).",
        suggested_action: "Inspect active findings, pending gates, and proof coverage.",
        link: "/observability",
        human_gate_required: true
      }
    )
    |> maybe_action(
      Enum.any?(overview.runs.recent, &(&1.proof_bundles == 0)),
      %{
        id: "proof-coverage",
        title: "Add proof coverage for runs",
        category: "proof",
        priority: "medium",
        source: "session_runs",
        evidence: "At least one recent run has no proof bundle.",
        suggested_action: "Generate proof bundles for runs that need reproducible evidence.",
        link: "/proofs",
        human_gate_required: false
      }
    )
  end

  defp add_problem_actions(actions, problems) do
    Enum.reduce(problems.problems, actions, fn problem, acc ->
      feedback = problem.feedback_loop

      acc ++
        [
          %{
            id: "problem-#{problem.rule_id}",
            title: feedback.eval_candidate_title,
            category: "problem",
            priority: recommendation_priority(problem.health, problem.severity),
            source: "problem_group",
            evidence: feedback.evidence_summary,
            suggested_action: feedback.suggested_action,
            benchmark_hint: feedback.benchmark_hint,
            link: "/observability/problems",
            example_session_id: feedback.example_session_id,
            example_finding_id: feedback.example_finding_id,
            human_gate_required: feedback.human_gate_required
          }
        ]
    end)
  end

  defp add_cost_actions(actions, costs) do
    Enum.reduce(costs.recommendations, actions, fn recommendation, acc ->
      acc ++
        [
          %{
            id: "cost-#{length(acc)}",
            title: "Review cost efficiency",
            category: "cost",
            priority: "low",
            source: "invocations",
            evidence:
              "#{costs.totals.invocations} invocation(s), #{costs.totals.estimated_cost_cents} estimated cent(s).",
            suggested_action: recommendation,
            link: "/observability/costs",
            human_gate_required: false
          }
        ]
    end)
  end

  defp add_token_overhead_actions(actions, project_root) do
    audit_result = CkTokenAudit.call(%{"mode" => "full", "project_root" => project_root})

    case audit_result do
      {:ok, audit} ->
        rule_recs = Map.get(audit, "recommendations", [])
        skill_recs = Map.get(audit, "skill_recommendations", [])
        duplicate_tokens = Map.get(audit, "duplicate_token_count", 0)
        total_words = Map.get(audit, "total_words", 0)
        status = Map.get(audit, "status", "optimal")

        actions
        |> maybe_action(
          status == "oversized",
          %{
            id: "token-rule-files-oversized",
            title: "Reduce rule file token overhead",
            category: "token",
            priority: "medium",
            source: "token_audit",
            evidence:
              "Rule files total #{total_words} words (target: 1200). Excess adds ~#{total_words - 1200} words of context on every request.",
            suggested_action: Enum.join(rule_recs, " "),
            link: "/observability",
            human_gate_required: false
          }
        )
        |> maybe_action(
          duplicate_tokens > 0,
          %{
            id: "token-skill-duplicates",
            title: "Remove duplicate skill copies",
            category: "token",
            priority: "medium",
            source: "token_audit",
            evidence:
              "#{duplicate_tokens} tokens wasted from duplicate skills across user/project/.agents locations. MCP hosts may load all copies.",
            suggested_action: Enum.join(Enum.take(skill_recs, 3), " "),
            link: "/observability",
            human_gate_required: false
          }
        )

      _ ->
        actions
    end
  end

  defp maybe_action(actions, true, action), do: actions ++ [action]
  defp maybe_action(actions, false, _action), do: actions

  defp recommendation_priority("red", _severity), do: "critical"
  defp recommendation_priority(_health, "critical"), do: "critical"
  defp recommendation_priority(_health, "high"), do: "high"
  defp recommendation_priority(_health, _severity), do: "medium"

  defp priority_rank("critical"), do: 1
  defp priority_rank("high"), do: 2
  defp priority_rank("medium"), do: 3
  defp priority_rank("low"), do: 4
  defp priority_rank(_priority), do: 5

  defp recommendation_health(actions) do
    cond do
      Enum.any?(actions, &(&1.priority == "critical")) -> "red"
      Enum.any?(actions, &(&1.priority in ["high", "medium"])) -> "yellow"
      actions == [] -> "green"
      true -> "green"
    end
  end

  defp eval_candidate_from_problem(problem) do
    feedback = problem.feedback_loop

    %{
      id: "eval-#{problem.rule_id}",
      title: feedback.eval_candidate_title,
      rule_id: problem.rule_id,
      category: problem.category,
      severity: problem.severity,
      priority: recommendation_priority(problem.health, problem.severity),
      evidence_kind: feedback.evidence_kind,
      evidence_summary: feedback.evidence_summary,
      suggested_action: feedback.suggested_action,
      benchmark_hint: feedback.benchmark_hint,
      affected_session_count: problem.affected_session_count,
      finding_count: problem.count,
      example_session_id: feedback.example_session_id,
      example_finding_id: feedback.example_finding_id,
      human_gate_required: feedback.human_gate_required,
      links: %{
        problems: "/observability/problems",
        benchmarks: "/benchmarks",
        example_session:
          feedback.example_session_id && "/observability/sessions/#{feedback.example_session_id}"
      }
    }
  end

  defp eval_candidates_health([]), do: "green"

  defp eval_candidates_health(candidates) do
    cond do
      Enum.any?(candidates, &(&1.priority == "critical")) -> "red"
      Enum.any?(candidates, &(&1.priority in ["high", "medium"])) -> "yellow"
      true -> "green"
    end
  end

  defp eval_candidate_recommendations([]),
    do: ["No eval candidates are active from grouped problems."]

  defp eval_candidate_recommendations(candidates) do
    [
      "Review #{length(candidates)} candidate(s) and approve benchmark coverage before promotion.",
      "Start with critical and high priority candidates linked to blocked or recurring findings."
    ]
  end

  defp timeline_event(event) do
    %{
      id: event_value(event, :id),
      event_type: event_value(event, :event_type) || "event",
      actor: event_value(event, :actor) || "unknown",
      summary: event_value(event, :summary) || "No summary",
      body: event_value(event, :body),
      task_id: event_value(event, :task_id),
      inserted_at: format_datetime(event_value(event, :inserted_at))
    }
  end

  defp memory_records(session_id, limit) do
    MemoryRecord
    |> where([r], r.session_id == ^session_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp memory_record_summary(record) do
    %{
      id: record.id,
      record_type: record.record_type,
      title: record.title,
      summary: record.summary,
      tags: record.tags || [],
      source_type: record.source_type,
      source_id: record.source_id,
      archived: not is_nil(record.archived_at),
      inserted_at: format_datetime(record.inserted_at),
      archived_at: format_datetime(record.archived_at)
    }
  end

  defp memory_context_recommendations([], _archived_records),
    do: ["No active memory records are available for this session."]

  defp memory_context_recommendations(_active_records, archived_records) do
    []
    |> maybe_reason(
      archived_records != [],
      "Archived memory is present; confirm current context is not relying on stale notes."
    )
    |> case do
      [] -> ["Session memory has active records available for continuity."]
      recommendations -> recommendations
    end
  end

  defp problem_summary_from_aggregate(agg, examples) do
    rule_id = agg.rule_id || "unknown_rule"
    category = agg.category || "uncategorized"
    latest = List.first(examples)

    # Derive severity from examples; aggregate query doesn't select per-row severity
    # (SQLite lacks a standard first_value aggregate; examples are already ordered DESC).
    severity =
      examples
      |> Enum.map(&(&1.severity || "low"))
      |> Enum.max_by(&severity_rank/1, fn -> "low" end)

    status_counts =
      %{}
      |> then(fn m ->
        if agg.blocked_count > 0, do: Map.put(m, "blocked", agg.blocked_count), else: m
      end)
      |> then(fn m ->
        if agg.escalated_count > 0, do: Map.put(m, "escalated", agg.escalated_count), else: m
      end)
      |> then(fn m ->
        open = agg.count - agg.blocked_count - agg.escalated_count
        if open > 0, do: Map.put(m, "open", open), else: m
      end)

    health = problem_health(severity, status_counts)

    %{
      key: "#{rule_id}:#{category}",
      title: (latest && latest.title) || rule_id,
      rule_id: rule_id,
      category: category,
      severity: severity,
      health: health,
      count: agg.count,
      status_counts: status_counts,
      affected_sessions: [],
      affected_session_count: agg.affected_session_count,
      last_seen: agg.last_seen && format_datetime(agg.last_seen),
      recommendation: problem_recommendation(health, severity, rule_id),
      feedback_loop: feedback_loop(rule_id, category, severity, health, examples),
      examples:
        Enum.map(examples, fn finding ->
          %{
            id: finding.id,
            title: finding.title,
            plain_message: finding.plain_message,
            severity: finding.severity,
            status: finding.status,
            session_id: finding.session_id,
            session_title: finding.session && finding.session.title,
            inserted_at: format_datetime(finding.inserted_at)
          }
        end)
    }
  end

  defp problem_health("critical", _status_counts), do: "red"
  defp problem_health(_severity, %{"blocked" => count}) when count > 0, do: "red"
  defp problem_health("high", _status_counts), do: "yellow"
  defp problem_health(_severity, %{"escalated" => count}) when count > 0, do: "yellow"
  defp problem_health(_severity, _status_counts), do: "yellow"

  defp severity_rank("critical"), do: 4
  defp severity_rank("high"), do: 3
  defp severity_rank("medium"), do: 2
  defp severity_rank("low"), do: 1
  defp severity_rank(_), do: 0

  defp problems_health([]), do: "green"

  defp problems_health(groups) do
    cond do
      Enum.any?(groups, &(&1.health == "red")) -> "red"
      Enum.any?(groups, &(&1.health == "yellow")) -> "yellow"
      true -> "green"
    end
  end

  defp feedback_loop(rule_id, category, severity, health, findings) do
    example = List.first(findings)

    %{
      eval_candidate_title: "Regression eval for #{rule_id}",
      evidence_kind: "finding_group",
      evidence_summary:
        "#{length(findings)} active #{category} finding(s), highest severity #{severity}, health #{health}.",
      suggested_action: feedback_action(health, rule_id),
      benchmark_hint: benchmark_hint(category, rule_id),
      human_gate_required: true,
      example_session_id: example && example.session_id,
      example_finding_id: example && example.id
    }
  end

  defp feedback_action("red", rule_id),
    do: "Add or run a regression benchmark for #{rule_id} before widening automation."

  defp feedback_action(_health, rule_id),
    do: "Create a lightweight eval case for #{rule_id} and monitor recurrence."

  defp benchmark_hint("security", _rule_id), do: "security-regression"
  defp benchmark_hint("review", _rule_id), do: "governance-gate-regression"
  defp benchmark_hint("integration", _rule_id), do: "integration-continuity-regression"
  defp benchmark_hint(_category, rule_id), do: "#{rule_id}-regression"

  defp problem_recommendation("red", _severity, rule_id),
    do: "Resolve or explicitly approve #{rule_id} before widening automation."

  defp problem_recommendation("yellow", _severity, rule_id),
    do: "Review #{rule_id}, add regression coverage, and confirm the affected sessions."

  defp problem_recommendation(_health, _severity, rule_id),
    do: "Monitor #{rule_id} for recurrence."

  defp problems_recommendations([]), do: ["No active problems detected."]

  defp problems_recommendations(groups) do
    groups
    |> Enum.take(3)
    |> Enum.map(& &1.recommendation)
  end

  defp ensure_preloaded(%Session{workspace: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{tasks: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{findings: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{} = session), do: session

  defp ensure_workspace_preloaded(%Session{workspace: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_with_workspace(session.id)

  defp ensure_workspace_preloaded(%Session{} = session), do: session

  defp budget_status(session) do
    case Budget.status(%{"session_id" => session.id}) do
      {:ok, budget} -> budget
      _ -> %{}
    end
  end

  defp session_summary(session) do
    %{
      id: session.id,
      title: session.title,
      objective: session.objective,
      risk_tier: session.risk_tier,
      status: session.status,
      workspace_id: session.workspace_id,
      workspace_name: session.workspace && session.workspace.name
    }
  end

  defp health(findings, tasks, reviews, budget) do
    active_findings = Enum.filter(findings, &(&1.status in @active_finding_statuses))
    critical = Enum.count(active_findings, &(&1.severity == "critical"))
    high = Enum.count(active_findings, &(&1.severity == "high"))
    blocked = Enum.count(active_findings, &(&1.status == "blocked"))
    pending_reviews = Enum.count(reviews, &(&1.status == "pending"))
    active_tasks = Enum.count(tasks, &(&1.status in @active_task_statuses))

    status =
      cond do
        Map.get(budget, "decision") == "block" or critical > 0 or blocked > 0 -> "red"
        Map.get(budget, "decision") == "warn" or high > 0 or pending_reviews > 0 -> "yellow"
        active_findings != [] or active_tasks > 0 -> "yellow"
        true -> "green"
      end

    %{
      status: status,
      label: health_label(status),
      reasons: health_reasons(status, critical, high, blocked, pending_reviews, budget)
    }
  end

  defp health(
         _findings_total,
         findings_active,
         findings_blocked,
         findings_critical_active,
         tasks_active,
         reviews_pending,
         budget
       ) do
    critical = findings_critical_active
    high = findings_active - findings_critical_active
    blocked = findings_blocked

    status =
      cond do
        Map.get(budget, "decision") == "block" or critical > 0 or blocked > 0 -> "red"
        Map.get(budget, "decision") == "warn" or high > 0 or reviews_pending > 0 -> "yellow"
        findings_active > 0 or tasks_active > 0 -> "yellow"
        true -> "green"
      end

    %{
      status: status,
      label: health_label(status),
      reasons: health_reasons(status, critical, high, blocked, reviews_pending, budget)
    }
  end

  defp health_label("red"), do: "Needs intervention"
  defp health_label("yellow"), do: "Needs attention"
  defp health_label("green"), do: "Healthy"

  defp health_reasons(status, critical, high, blocked, pending_reviews, budget) do
    []
    |> maybe_reason(critical > 0, "#{critical} critical finding(s)")
    |> maybe_reason(blocked > 0, "#{blocked} blocked finding(s)")
    |> maybe_reason(high > 0, "#{high} high finding(s)")
    |> maybe_reason(pending_reviews > 0, "#{pending_reviews} pending review gate(s)")
    |> maybe_reason(
      Map.get(budget, "decision") in ["warn", "block"],
      "budget #{Map.get(budget, "decision")}"
    )
    |> case do
      [] -> [health_label(status)]
      reasons -> reasons
    end
  end

  defp maybe_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_reason(reasons, false, _reason), do: reasons

  defp finding_summary_with_counts(findings, counts) do
    active_findings = Enum.filter(findings, &(&1.status in @active_finding_statuses))

    %{
      total: counts.total,
      active: counts.active,
      blocked: counts.blocked,
      critical: counts.critical_active,
      high: counts.high_active,
      by_severity: frequencies(active_findings, & &1.severity),
      recent:
        findings
        |> Enum.take(5)
        |> Enum.map(fn finding ->
          %{
            id: finding.id,
            title: finding.title,
            severity: finding.severity,
            status: finding.status,
            rule_id: finding.rule_id
          }
        end)
    }
  end

  defp task_summary_with_counts(tasks, counts) do
    %{
      total: counts.total,
      active: counts.active,
      by_status: frequencies(tasks, & &1.status)
    }
  end

  defp gate_summary_with_counts(reviews, counts) do
    %{
      total_reviews: counts.total,
      pending_reviews: counts.pending,
      latest:
        reviews
        |> Enum.take(3)
        |> Enum.map(fn review ->
          %{
            id: review.id,
            status: review.status,
            review_type: review.review_type,
            title: review.title || "Review #{review.id}"
          }
        end)
    }
  end

  defp timeline_summary(events) do
    %{
      count: length(events),
      recent:
        Enum.map(events, fn event ->
          %{
            id: event_value(event, :id),
            event_type: event_value(event, :event_type),
            actor: event_value(event, :actor),
            summary: event_value(event, :summary),
            inserted_at: format_datetime(event_value(event, :inserted_at))
          }
        end)
    }
  end

  defp proof_summary(proofs) when is_map(proofs) do
    %{
      count: map_size(proofs),
      task_ids: Map.keys(proofs)
    }
  end

  defp invocation_summary_with_counts(invocations, counts) do
    %{
      invocations: counts.total,
      estimated_cost_cents: counts.total_cost_cents,
      by_source: frequencies(invocations, &(&1.source || "unknown")),
      by_model: frequencies(invocations, &(&1.model || "unknown")),
      by_tool: frequencies(invocations, &(&1.tool || "unknown"))
    }
  end

  defp recommendations(
         health,
         findings_total,
         _findings_active,
         _findings_critical_active,
         _findings_high_active,
         reviews_pending,
         budget,
         memory_count
       ) do
    []
    |> maybe_reason(
      health.status == "red",
      "Resolve blocked or critical findings before widening automation."
    )
    |> maybe_reason(
      health.status == "yellow",
      "Review active findings, pending gates, or budget warnings before calling the run healthy."
    )
    |> maybe_reason(
      reviews_pending > 0,
      "Finish pending human review gates or narrow the plan."
    )
    |> maybe_reason(
      Map.get(budget, "decision") == "warn",
      "Check cost efficiency before running expensive agent loops."
    )
    |> maybe_reason(
      memory_count == 0,
      "Record key decisions in CK memory so future hosts can resume with context."
    )
    |> maybe_reason(
      findings_total == 0,
      "No findings recorded yet; run validation before shipping."
    )
    |> case do
      [] -> ["Run is observable and no immediate action is required."]
      recommendations -> recommendations
    end
  end

  defp perf_item(label, fun) when is_binary(label) and is_function(fun, 0) do
    handler_id = "controlkeel-perf-snapshot-#{System.unique_integer([:positive])}"

    parent = self()

    handler = fn _event, measurements, _metadata, _config ->
      send(parent, {:perf_query, measurements})
    end

    events = [[:ecto, :repo, :query]]
    _ = :telemetry.detach(handler_id)

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        handler,
        %{}
      )

    {elapsed_us, result} = :timer.tc(fun)

    _ = :telemetry.detach(handler_id)

    {query_count, query_time_us} = drain_query_measurements(0, 0)

    %{
      label: label,
      wall_ms: Float.round(elapsed_us / 1000, 3),
      ecto_query_count: query_count,
      ecto_query_ms: Float.round(query_time_us / 1000, 3),
      payload_bytes: safe_payload_bytes(result)
    }
  end

  defp drain_query_measurements(count, time_us) do
    receive do
      {:perf_query, measurements} ->
        duration = Map.get(measurements, :total_time, 0)
        drain_query_measurements(count + 1, time_us + duration)
    after
      0 ->
        {count, time_us}
    end
  end

  defp safe_payload_bytes(result) do
    try do
      byte_size(:erlang.term_to_binary(result))
    rescue
      _ -> nil
    end
  end

  defp perf_summary(items) do
    %{
      item_count: length(items),
      total_wall_ms: Float.round(Enum.reduce(items, 0.0, &(&1.wall_ms + &2)), 3),
      total_ecto_queries: Enum.reduce(items, 0, &(&1.ecto_query_count + &2)),
      total_payload_bytes:
        Enum.reduce(items, 0, fn item, acc -> acc + (item.payload_bytes || 0) end)
    }
  end

  defp maybe_add_session_perf_items(items, nil, _opts), do: items

  defp maybe_add_session_perf_items(items, session_id, opts) when is_integer(session_id) do
    items ++
      [
        perf_item("observability.session_run", fn -> session_run(session_id, opts) end),
        perf_item("observability.timeline", fn -> timeline(session_id, opts) end),
        perf_item("observability.memory", fn -> memory_context(session_id, opts) end)
      ]
  end

  defp maybe_add_mission_perf_items(items, nil), do: items

  defp maybe_add_mission_perf_items(items, session_id) when is_integer(session_id) do
    items ++
      [
        perf_item("mission.get_session_context.default", fn ->
          Mission.get_session_context(session_id)
        end),
        perf_item("mission.get_session_context.bounded", fn ->
          Mission.get_session_context(session_id,
            findings_limit: 10,
            tasks_limit: 20,
            reviews_limit: 5,
            invocations_limit: 20
          )
        end)
      ]
  end

  defp maybe_add_memory_perf_items(items, nil, _workspace_id, _task_id), do: items

  defp maybe_add_memory_perf_items(items, session_id, workspace_id, task_id)
       when is_integer(session_id) do
    query = "session:#{session_id}"

    items ++
      [
        perf_item("memory.search.slim", fn ->
          Memory.search(query,
            session_id: session_id,
            workspace_id: workspace_id,
            task_id: task_id,
            top_k: 10
          )
        end),
        perf_item("memory.search.with_metadata", fn ->
          Memory.search(query,
            session_id: session_id,
            workspace_id: workspace_id,
            task_id: task_id,
            top_k: 10,
            include_metadata: true
          )
        end),
        perf_item("memory.search.with_body", fn ->
          Memory.search(query,
            session_id: session_id,
            workspace_id: workspace_id,
            task_id: task_id,
            top_k: 10,
            include_body: true,
            include_metadata: true
          )
        end)
      ]
  end

  defp event_value(event, key) when is_map(event),
    do: Map.get(event, key) || Map.get(event, Atom.to_string(key))

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp memory_count(session_id) do
    MemoryRecord
    |> where([r], r.session_id == ^session_id and is_nil(r.archived_at))
    |> Repo.aggregate(:count, :id)
  end

  defp session_context_counts(session_id) do
    %{
      tasks:
        Repo.aggregate(
          from(t in ControlKeel.Mission.Task, where: t.session_id == ^session_id),
          :count,
          :id
        ),
      findings:
        Repo.aggregate(from(f in Finding, where: f.session_id == ^session_id), :count, :id),
      reviews:
        Repo.aggregate(
          from(r in ControlKeel.Mission.Review, where: r.session_id == ^session_id),
          :count,
          :id
        ),
      invocations:
        Repo.aggregate(from(i in Invocation, where: i.session_id == ^session_id), :count, :id)
    }
  end

  defp frequencies(items, fun) do
    items
    |> Enum.map(fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp persist_perf_snapshot(snapshot, opts) do
    workspace_id = snapshot.workspace_id || Keyword.get(opts, :workspace_id)
    session_id = snapshot.session_id || Keyword.get(opts, :session_id)
    task_id = snapshot.task_id || Keyword.get(opts, :task_id)

    attrs = %{
      workspace_id: workspace_id,
      session_id: session_id,
      record_type: "telemetry",
      title: "Performance Snapshot",
      summary: "Performance metrics for observability reports and core functions",
      body: perf_snapshot_to_text(snapshot),
      tags:
        ["perf_snapshot", "telemetry", "observability"]
        |> Enum.concat(if(session_id, do: ["session:#{session_id}"], else: []))
        |> Enum.concat(if(task_id, do: ["task:#{task_id}"], else: [])),
      source_type: "observability",
      source_id: "perf_snapshot:#{System.unique_integer([:positive])}",
      metadata: %{
        "generated_at" => DateTime.to_iso8601(snapshot.generated_at),
        "workspace_id" => workspace_id,
        "session_id" => session_id,
        "task_id" => task_id,
        "item_count" => snapshot.summary.item_count,
        "total_wall_ms" => snapshot.summary.total_wall_ms,
        "total_ecto_queries" => snapshot.summary.total_ecto_queries,
        "total_payload_bytes" => snapshot.summary.total_payload_bytes,
        "items" => snapshot.items
      }
    }

    case Memory.record(attrs) do
      {:ok, _record} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp perf_snapshot_to_text(snapshot) do
    items_text =
      snapshot.items
      |> Enum.map(fn item ->
        "  #{item.label}: wall=#{item.wall_ms}ms, queries=#{item.ecto_query_count}, payload=#{item.payload_bytes}B"
      end)
      |> Enum.join("\n")

    """
    Performance Snapshot - #{DateTime.to_iso8601(snapshot.generated_at)}
    Workspace: #{snapshot.workspace_id || "N/A"}
    Session: #{snapshot.session_id || "N/A"}
    Task: #{snapshot.task_id || "N/A"}

    Summary:
      Items: #{snapshot.summary.item_count}
      Total Wall Time: #{snapshot.summary.total_wall_ms}ms
      Total Queries: #{snapshot.summary.total_ecto_queries}
      Total Payload: #{snapshot.summary.total_payload_bytes}B

    Items:
    #{items_text}
    """
    |> String.trim()
  end
end
