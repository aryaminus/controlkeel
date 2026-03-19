defmodule ControlKeel.PolicyTraining.Datasets do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.AgentRouter
  alias ControlKeel.Benchmark
  alias ControlKeel.Benchmark.{Metadata, Result, Run, SubjectLoader, Suite}
  alias ControlKeel.Budget
  alias ControlKeel.Mission.{Invocation, Session}
  alias ControlKeel.PolicyTraining.Scorer
  alias ControlKeel.Repo

  @router_numeric_features [
    "local",
    "cost_tier_value",
    "security_tier_value",
    "swe_bench_score",
    "cap_repo_edit",
    "cap_file_write",
    "cap_bash",
    "cap_mcp",
    "cap_git",
    "cap_deploy",
    "cap_code_review",
    "cap_spec_gen",
    "cap_multi_agent",
    "cap_workflow",
    "historical_catch_rate",
    "historical_block_rate",
    "expected_rule_hit_rate",
    "median_latency_ms",
    "average_overhead_percent"
  ]
  @router_categorical_features [
    "task_type",
    "risk_tier",
    "domain_pack",
    "budget_tier",
    "subject_id",
    "subject_type"
  ]

  @budget_numeric_features [
    "input_tokens",
    "output_tokens",
    "cached_input_tokens",
    "estimated_cost_cents",
    "session_spend_ratio",
    "rolling_24h_spend_ratio",
    "active_findings_count"
  ]
  @budget_categorical_features [
    "source",
    "tool",
    "provider",
    "model",
    "domain_pack",
    "risk_tier"
  ]

  @public_suite_slug "vibe_failures_v1"
  @holdout_suite_slug "policy_holdout_v1"

  def build("router"), do: build_router_dataset()
  def build("budget_hint"), do: build_budget_dataset()
  def build(_artifact_type), do: {:error, :unknown_artifact_type}

  def evaluate_artifact("router", artifact_payload, bundle) do
    rows = Map.get(bundle, :rows, [])

    {:ok,
     %{
       training_metrics: evaluate_router_split(rows, "train", artifact_payload),
       validation_metrics: evaluate_router_split(rows, "validation", artifact_payload),
       held_out_metrics: evaluate_router_split(rows, "held_out", artifact_payload),
       baseline_metrics: %{
         "held_out" => evaluate_router_split(rows, "held_out", :heuristic)
       }
     }}
  end

  def evaluate_artifact("budget_hint", artifact_payload, bundle) do
    rows = Map.get(bundle, :rows, [])

    {:ok,
     %{
       training_metrics: evaluate_budget_split(rows, "train", artifact_payload),
       validation_metrics: evaluate_budget_split(rows, "validation", artifact_payload),
       held_out_metrics: evaluate_budget_split(rows, "held_out", artifact_payload),
       baseline_metrics: %{}
     }}
  end

  def router_candidate_features(agent_id, agent_profile, context \\ %{}) do
    context = stringify_keys(context)
    subject_stats = Map.get(context, "subject_stats", %{})
    task_type = normalize_task_type(Map.get(context, "task_type", "backend"))
    risk_tier = normalize_risk_tier(Map.get(context, "risk_tier", "moderate"))
    domain_pack = normalize_domain_pack(Map.get(context, "domain_pack", "software"))
    budget_tier = normalize_budget_tier(Map.get(context, "budget_tier", "medium"))
    subject_type = Map.get(context, "subject_type") || infer_subject_type(agent_id, agent_profile)
    capabilities = Map.get(agent_profile, :capabilities, [])

    %{
      "task_type" => task_type,
      "risk_tier" => risk_tier,
      "domain_pack" => domain_pack,
      "budget_tier" => budget_tier,
      "subject_id" => agent_id,
      "subject_type" => subject_type,
      "local" => if(Map.get(agent_profile, :local, false), do: 1.0, else: 0.0),
      "cost_tier_value" => cost_tier_value(Map.get(agent_profile, :cost_tier, :medium)),
      "security_tier_value" =>
        security_tier_value(Map.get(agent_profile, :security_tier, :medium)),
      "swe_bench_score" => Map.get(agent_profile, :swe_bench_score, 0.5),
      "cap_repo_edit" => flag(capabilities, :repo_edit),
      "cap_file_write" => flag(capabilities, :file_write),
      "cap_bash" => flag(capabilities, :bash),
      "cap_mcp" => flag(capabilities, :mcp),
      "cap_git" => flag(capabilities, :git),
      "cap_deploy" => flag(capabilities, :deploy),
      "cap_code_review" => flag(capabilities, :code_review),
      "cap_spec_gen" => flag(capabilities, :spec_gen),
      "cap_multi_agent" => flag(capabilities, :multi_agent),
      "cap_workflow" => flag(capabilities, :workflow),
      "historical_catch_rate" =>
        Map.get(
          subject_stats,
          "historical_catch_rate",
          Map.get(agent_profile, :swe_bench_score, 0.5)
        ),
      "historical_block_rate" => Map.get(subject_stats, "historical_block_rate", 0.0),
      "expected_rule_hit_rate" => Map.get(subject_stats, "expected_rule_hit_rate", 0.5),
      "median_latency_ms" =>
        Map.get(
          subject_stats,
          "median_latency_ms",
          if(Map.get(agent_profile, :local, false), do: 350, else: 850)
        ),
      "average_overhead_percent" =>
        Map.get(
          subject_stats,
          "average_overhead_percent",
          if(Map.get(agent_profile, :local, false), do: 4.0, else: 11.0)
        )
    }
  end

  def budget_estimate_features(
        %Session{} = session,
        attrs,
        projected_session_spend,
        projected_daily_spend,
        active_findings_count
      ) do
    attrs = stringify_keys(attrs)

    %{
      "source" => Map.get(attrs, "source", "mcp"),
      "tool" => Map.get(attrs, "tool", "ck_budget"),
      "provider" => Map.get(attrs, "provider", "unknown"),
      "model" => Map.get(attrs, "model", "unknown"),
      "input_tokens" => Map.get(attrs, "input_tokens", 0),
      "output_tokens" => Map.get(attrs, "output_tokens", 0),
      "cached_input_tokens" => Map.get(attrs, "cached_input_tokens", 0),
      "estimated_cost_cents" => Map.get(attrs, "estimated_cost_cents", 0),
      "session_spend_ratio" => ratio(projected_session_spend, session.budget_cents),
      "rolling_24h_spend_ratio" => ratio(projected_daily_spend, session.daily_budget_cents),
      "domain_pack" =>
        normalize_domain_pack(
          get_in(session.execution_brief || %{}, ["domain_pack"]) || "software"
        ),
      "risk_tier" => normalize_risk_tier(session.risk_tier || "moderate"),
      "active_findings_count" => active_findings_count
    }
  end

  def heuristically_seeded?(bundle), do: Map.get(bundle, :heuristically_seeded, false)

  def build_router_dataset do
    {:ok, _public_run_ids} = ensure_suite_runs(@public_suite_slug)
    {:ok, _holdout_run_ids} = ensure_suite_runs(@holdout_suite_slug)

    results = router_training_results()
    historical_stats = subject_stats(Enum.reject(results, &(scenario_split(&1) == "held_out")))

    rows =
      Enum.map(results, fn result ->
        router_row(result, Map.get(historical_stats, result.subject, %{}))
      end)

    suite_slugs =
      results
      |> Enum.map(& &1.run.suite.slug)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok,
     %{
       artifact_type: "router",
       training_scope: "benchmark_runs",
       feature_spec: %{
         "numeric_features" => @router_numeric_features,
         "categorical_features" => @router_categorical_features
       },
       rows: rows,
       dataset_summary: %{
         "rows" => length(rows),
         "train_rows" => Enum.count(rows, &(&1["split"] == "train")),
         "validation_rows" => Enum.count(rows, &(&1["split"] == "validation")),
         "held_out_rows" => Enum.count(rows, &(&1["split"] == "held_out")),
         "suite_slugs" => suite_slugs
       },
       metadata: %{
         "source_suite_slugs" => suite_slugs,
         "source_run_ids" => Enum.map(results, & &1.run_id) |> Enum.uniq() |> Enum.sort(),
         "subject_ids" => Enum.map(results, & &1.subject) |> Enum.uniq() |> Enum.sort(),
         "invocation_sample_size" => 0
       },
       subject_stats: historical_stats
     }}
  end

  def build_budget_dataset do
    invocations = budget_invocations()

    {rows, seeded?} =
      if invocations == [] do
        {heuristic_seed_rows(), true}
      else
        {Enum.map(invocations, &budget_row/1), false}
      end

    {:ok,
     %{
       artifact_type: "budget_hint",
       training_scope: if(seeded?, do: "heuristic_bootstrap", else: "invocation_history"),
       feature_spec: %{
         "numeric_features" => @budget_numeric_features,
         "categorical_features" => @budget_categorical_features
       },
       rows: rows,
       heuristically_seeded: seeded?,
       dataset_summary: %{
         "rows" => length(rows),
         "train_rows" => Enum.count(rows, &(&1["split"] == "train")),
         "validation_rows" => Enum.count(rows, &(&1["split"] == "validation")),
         "held_out_rows" => Enum.count(rows, &(&1["split"] == "held_out")),
         "heuristically_seeded" => seeded?
       },
       metadata: %{
         "source_suite_slugs" => [],
         "source_run_ids" => [],
         "subject_ids" => [],
         "invocation_sample_size" => length(invocations)
       }
     }}
  end

  defp ensure_suite_runs(slug) do
    suite = Benchmark.get_suite_by_slug(slug)

    case suite do
      %Suite{id: suite_id} ->
        existing_run_ids =
          Run
          |> where([run], run.suite_id == ^suite_id)
          |> select([run], run.id)
          |> Repo.all()

        case existing_run_ids do
          [] ->
            subjects =
              get_in(suite.metadata || %{}, ["default_subjects"]) ||
                SubjectLoader.default_subject_ids()

            subject_string =
              case subjects do
                value when is_list(value) -> Enum.join(value, ",")
                value when is_binary(value) -> value
                _ -> Enum.join(SubjectLoader.default_subject_ids(), ",")
              end

            baseline =
              get_in(suite.metadata || %{}, ["default_subjects"])
              |> List.wrap()
              |> List.first() || "controlkeel_validate"

            case Benchmark.run_suite(%{
                   "suite" => slug,
                   "subjects" => subject_string,
                   "baseline_subject" => baseline
                 }) do
              {:ok, run} -> {:ok, [run.id]}
              {:error, reason} -> {:error, reason}
            end

          ids ->
            {:ok, ids}
        end

      nil ->
        {:error, :suite_not_found}
    end
  end

  defp router_training_results do
    Result
    |> join(:inner, [result], run in assoc(result, :run))
    |> join(:inner, [_result, run], suite in assoc(run, :suite))
    |> where([_result, _run, suite], suite.slug in [^@public_suite_slug, ^@holdout_suite_slug])
    |> order_by([result, _run, _suite], asc: result.id)
    |> preload([result, run, suite], run: {run, suite: suite}, scenario: [])
    |> Repo.all()
  end

  defp budget_invocations do
    Invocation
    |> order_by([invocation], asc: invocation.id)
    |> preload(session: [:findings])
    |> Repo.all()
    |> Enum.filter(& &1.session)
  end

  defp router_row(result, subject_stats) do
    scenario = result.scenario
    metadata = Map.merge(Metadata.default_metadata(), scenario.metadata || %{})
    profile = subject_profile(result.subject, result.subject_type)
    split = scenario_split(result)

    %{
      "id" => "#{result.run.suite.slug}:#{scenario.slug}:#{result.subject}",
      "split" => split,
      "target" => router_target(result),
      "features" =>
        router_candidate_features(result.subject, profile, %{
          "task_type" => metadata["task_type"],
          "risk_tier" => metadata["risk_tier"],
          "domain_pack" => metadata["domain_pack"],
          "budget_tier" => metadata["budget_tier"],
          "subject_type" => result.subject_type,
          "subject_stats" => subject_stats
        }),
      "meta" => %{
        "scenario_slug" => scenario.slug,
        "suite_slug" => result.run.suite.slug,
        "decision" => result.decision,
        "expected_decision" => scenario.expected_decision,
        "findings_count" => result.findings_count,
        "matched_expected" => result.matched_expected,
        "overhead_percent" => result.overhead_percent || 0.0,
        "latency_ms" => result.latency_ms || 0,
        "subject" => result.subject
      }
    }
  end

  defp budget_row(invocation) do
    session = invocation.session
    rolling = Budget.rolling_24h_spend_cents(session.id)

    active_findings_count =
      Enum.count(session.findings || [], &(&1.status in ["open", "blocked", "escalated"]))

    split =
      case bucket(invocation.id) do
        bucket when bucket < 2 -> "held_out"
        bucket when bucket < 4 -> "validation"
        _ -> "train"
      end

    label =
      if invocation.decision in ["warn", "block"] do
        1.0
      else
        if ratio(session.spent_cents || 0, session.budget_cents) >= 0.7 or
             ratio(rolling, session.daily_budget_cents) >= 0.7 do
          1.0
        else
          0.0
        end
      end

    %{
      "id" => "invocation:#{invocation.id}",
      "split" => split,
      "target" => label,
      "features" =>
        budget_estimate_features(
          session,
          %{
            "source" => invocation.source,
            "tool" => invocation.tool,
            "provider" => invocation.provider,
            "model" => invocation.model,
            "input_tokens" => invocation.input_tokens || 0,
            "output_tokens" => invocation.output_tokens || 0,
            "cached_input_tokens" => invocation.cached_input_tokens || 0,
            "estimated_cost_cents" => invocation.estimated_cost_cents || 0
          },
          session.spent_cents || 0,
          rolling,
          active_findings_count
        ),
      "meta" => %{
        "invocation_id" => invocation.id,
        "session_id" => session.id,
        "decision" => invocation.decision,
        "source" => invocation.source
      }
    }
  end

  defp heuristic_seed_rows do
    base_rows = [
      %{
        "ratio" => 0.18,
        "daily" => 0.14,
        "cost" => 18,
        "label" => 0.0,
        "provider" => "anthropic",
        "model" => "claude-sonnet-4-5"
      },
      %{
        "ratio" => 0.34,
        "daily" => 0.28,
        "cost" => 32,
        "label" => 0.0,
        "provider" => "openai",
        "model" => "gpt-5.4-mini"
      },
      %{
        "ratio" => 0.72,
        "daily" => 0.61,
        "cost" => 74,
        "label" => 1.0,
        "provider" => "anthropic",
        "model" => "claude-opus-4-6"
      },
      %{
        "ratio" => 0.83,
        "daily" => 0.77,
        "cost" => 95,
        "label" => 1.0,
        "provider" => "openai",
        "model" => "gpt-5.4"
      },
      %{
        "ratio" => 0.92,
        "daily" => 0.94,
        "cost" => 110,
        "label" => 1.0,
        "provider" => "anthropic",
        "model" => "claude-sonnet-4-6"
      },
      %{
        "ratio" => 0.44,
        "daily" => 0.38,
        "cost" => 40,
        "label" => 0.0,
        "provider" => "openai",
        "model" => "gpt-5.4-nano"
      }
    ]

    Enum.with_index(base_rows, 1)
    |> Enum.map(fn {row, index} ->
      split =
        case rem(index, 5) do
          0 -> "held_out"
          1 -> "validation"
          _ -> "train"
        end

      %{
        "id" => "seed:#{index}",
        "split" => split,
        "target" => row["label"],
        "features" => %{
          "source" => "seed",
          "tool" => "ck_budget",
          "provider" => row["provider"],
          "model" => row["model"],
          "input_tokens" => 1_200 + index * 100,
          "output_tokens" => 300 + index * 20,
          "cached_input_tokens" => 0,
          "estimated_cost_cents" => row["cost"],
          "session_spend_ratio" => row["ratio"],
          "rolling_24h_spend_ratio" => row["daily"],
          "domain_pack" => "software",
          "risk_tier" => "moderate",
          "active_findings_count" => if(row["label"] == 1.0, do: 3, else: 0)
        },
        "meta" => %{"seed" => true}
      }
    end)
  end

  defp evaluate_router_split(rows, split, artifact_payload_or_mode) do
    candidates =
      rows
      |> Enum.filter(&(&1["split"] == split))
      |> Enum.group_by(&get_in(&1, ["meta", "scenario_slug"]))

    selected =
      Enum.flat_map(candidates, fn {_scenario_slug, scenario_rows} ->
        case choose_router_row(scenario_rows, artifact_payload_or_mode) do
          nil -> []
          row -> [row]
        end
      end)

    reward_values = Enum.map(selected, &(&1["target"] || 0.0))
    count = length(selected)

    %{
      "count" => count,
      "reward" => average(reward_values),
      "catch_rate" =>
        ratio(Enum.count(selected, &(get_in(&1, ["meta", "findings_count"]) > 0)), count),
      "block_rate" =>
        ratio(Enum.count(selected, &(get_in(&1, ["meta", "decision"]) == "block")), count),
      "expected_rule_hit_rate" =>
        ratio(Enum.count(selected, &get_in(&1, ["meta", "matched_expected"])), count),
      "median_latency_ms" => median(Enum.map(selected, &get_in(&1, ["meta", "latency_ms"]))),
      "average_overhead_percent" =>
        average(Enum.map(selected, &get_in(&1, ["meta", "overhead_percent"])))
    }
  end

  defp choose_router_row([], _mode), do: nil

  defp choose_router_row(rows, :heuristic) do
    Enum.max_by(rows, &heuristic_router_score(&1["features"]))
  end

  defp choose_router_row(rows, artifact_payload) do
    Enum.max_by(rows, fn row ->
      case Scorer.score_router(artifact_payload, row["features"]) do
        {:ok, value} -> value
        {:error, _reason} -> heuristic_router_score(row["features"])
      end
    end)
  end

  defp evaluate_budget_split(rows, split, artifact_payload) do
    rows = Enum.filter(rows, &(&1["split"] == split))
    threshold = get_in(artifact_payload, ["thresholds", "warn_probability"]) || 0.6

    counts =
      Enum.reduce(rows, %{tp: 0, fp: 0, tn: 0, fn: 0, warned: 0}, fn row, acc ->
        probability =
          case Scorer.score_budget_hint(artifact_payload, row["features"]) do
            {:ok, value} -> value
            {:error, _reason} -> 0.0
          end

        predicted_warn? = probability >= threshold
        actual_warn? = (row["target"] || 0.0) >= 0.5

        acc
        |> Map.update!(:warned, &(&1 + if(predicted_warn?, do: 1, else: 0)))
        |> increment_confusion(predicted_warn?, actual_warn?)
      end)

    total = length(rows)
    warned = counts.warned
    tp = counts.tp
    fp = counts.fp
    tn = counts.tn
    fn_count = counts.fn

    %{
      "count" => total,
      "precision" => safe_div(tp, tp + fp),
      "recall" => safe_div(tp, tp + fn_count),
      "false_positive_rate" => safe_div(fp, fp + tn),
      "warn_rate" => safe_div(warned, total)
    }
  end

  defp increment_confusion(acc, true, true), do: Map.update!(acc, :tp, &(&1 + 1))
  defp increment_confusion(acc, true, false), do: Map.update!(acc, :fp, &(&1 + 1))
  defp increment_confusion(acc, false, true), do: Map.update!(acc, :fn, &(&1 + 1))
  defp increment_confusion(acc, false, false), do: Map.update!(acc, :tn, &(&1 + 1))

  defp router_target(result) do
    decision_bonus =
      if result.decision && result.decision == result.scenario.expected_decision,
        do: 1.0,
        else: 0.0

    protection_bonus =
      cond do
        result.matched_expected -> 2.2
        result.findings_count > 0 -> 1.2
        true -> 0.0
      end

    latency_penalty = min((result.latency_ms || 0) / 2_000, 1.0) * 0.35
    overhead_penalty = min((result.overhead_percent || 0.0) / 100, 1.0) * 0.5

    Float.round(
      protection_bonus + decision_bonus + min(result.findings_count * 0.15, 0.6) -
        latency_penalty - overhead_penalty,
      4
    )
  end

  defp heuristic_router_score(features) do
    security_bonus =
      case {features["security_tier_value"], features["risk_tier"]} do
        {4.0, _risk} -> 0.3
        {3.0, "high"} -> 0.2
        {3.0, "critical"} -> 0.1
        _ -> 0.0
      end

    local_bonus = if features["local"] >= 0.5, do: 0.1, else: 0.0

    task_bonus =
      case features["task_type"] do
        "ui" -> if(features["cap_repo_edit"] >= 0.5, do: 0.05, else: 0.0)
        "review" -> if(features["cap_code_review"] >= 0.5, do: 0.2, else: 0.0)
        "spec" -> if(features["cap_spec_gen"] >= 0.5, do: 0.2, else: 0.0)
        "workflow" -> if(features["cap_workflow"] >= 0.5, do: 0.2, else: 0.0)
        _ -> 0.0
      end

    (features["swe_bench_score"] || 0.5) + security_bonus + local_bonus + task_bonus
  end

  defp subject_stats(results) do
    Enum.group_by(results, & &1.subject)
    |> Enum.into(%{}, fn {subject, subject_results} ->
      count = max(length(subject_results), 1)

      latency_values =
        subject_results
        |> Enum.map(& &1.latency_ms)
        |> Enum.reject(&is_nil/1)

      overhead_values =
        subject_results
        |> Enum.map(& &1.overhead_percent)
        |> Enum.reject(&is_nil/1)

      {subject,
       %{
         "historical_catch_rate" => Enum.count(subject_results, &(&1.findings_count > 0)) / count,
         "historical_block_rate" =>
           Enum.count(subject_results, &(&1.decision == "block")) / count,
         "expected_rule_hit_rate" => Enum.count(subject_results, & &1.matched_expected) / count,
         "median_latency_ms" => median(latency_values) || 0,
         "average_overhead_percent" => average(overhead_values)
       }}
    end)
  end

  defp scenario_split(result) do
    case result.scenario.split do
      "held_out" ->
        "held_out"

      _ ->
        if(bucket("#{result.scenario.slug}:#{result.subject}") < 2,
          do: "validation",
          else: "train"
        )
    end
  end

  defp subject_profile(subject_id, subject_type) do
    case AgentRouter.get_agent(subject_id) do
      nil -> synthetic_subject_profile(subject_id, subject_type)
      profile -> profile
    end
  end

  defp synthetic_subject_profile(_subject_id, "controlkeel_validate") do
    %{
      capabilities: [:repo_edit, :code_review, :mcp],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.64,
      local: true
    }
  end

  defp synthetic_subject_profile(_subject_id, "controlkeel_proxy") do
    %{
      capabilities: [:llm_provider, :deploy],
      cost_tier: :low,
      security_tier: :high,
      swe_bench_score: 0.61,
      local: false
    }
  end

  defp synthetic_subject_profile(_subject_id, "shell") do
    %{
      capabilities: [:repo_edit, :bash, :file_write],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.52,
      local: true
    }
  end

  defp synthetic_subject_profile(_subject_id, _subject_type) do
    %{
      capabilities: [:repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.5,
      local: true
    }
  end

  defp infer_subject_type(subject_id, _agent_profile) do
    cond do
      subject_id in SubjectLoader.builtin_subject_ids() -> subject_id
      true -> "agent"
    end
  end

  defp normalize_task_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_task_type(value) when is_binary(value), do: String.downcase(value)
  defp normalize_task_type(_value), do: "backend"

  defp normalize_risk_tier("medium"), do: "moderate"

  defp normalize_risk_tier(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_risk_tier()

  defp normalize_risk_tier(value) when is_binary(value), do: String.downcase(value)
  defp normalize_risk_tier(_value), do: "moderate"

  defp normalize_domain_pack(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_domain_pack(value) when is_binary(value), do: String.downcase(value)
  defp normalize_domain_pack(_value), do: "software"

  defp normalize_budget_tier(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_budget_tier(value) when is_binary(value), do: String.downcase(value)
  defp normalize_budget_tier(_value), do: "medium"

  defp cost_tier_value(:free), do: 0.0
  defp cost_tier_value(:low), do: 1.0
  defp cost_tier_value(:medium), do: 2.0
  defp cost_tier_value(:high), do: 3.0

  defp cost_tier_value(value) when is_binary(value) do
    case String.downcase(value) do
      "free" -> 0.0
      "low" -> 1.0
      "medium" -> 2.0
      "high" -> 3.0
      _ -> 2.0
    end
  end

  defp cost_tier_value(_value), do: 2.0

  defp security_tier_value(:low), do: 1.0
  defp security_tier_value(:medium), do: 2.0
  defp security_tier_value(:high), do: 3.0
  defp security_tier_value(:critical), do: 4.0

  defp security_tier_value(value) when is_binary(value) do
    case value do
      "low" -> 1.0
      "medium" -> 2.0
      "moderate" -> 2.0
      "high" -> 3.0
      "critical" -> 4.0
      _ -> 2.0
    end
  end

  defp security_tier_value(_value), do: 2.0

  defp flag(capabilities, capability), do: if(capability in capabilities, do: 1.0, else: 0.0)

  defp bucket(value) do
    :erlang.phash2(value, 10)
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp stringify_keys(other), do: other

  defp ratio(_value, nil), do: 0.0
  defp ratio(_value, 0), do: 0.0
  defp ratio(value, limit), do: value / limit

  defp safe_div(_left, 0), do: 0.0
  defp safe_div(left, right), do: left / right

  defp average([]), do: 0.0
  defp average(values), do: Float.round(Enum.sum(values) / length(values), 4)

  defp median([]), do: 0

  defp median(values) do
    values = Enum.sort(values)
    middle = div(length(values), 2)

    case rem(length(values), 2) do
      0 ->
        left = Enum.at(values, middle - 1) || 0
        right = Enum.at(values, middle) || 0
        trunc((left + right) / 2)

      _ ->
        Enum.at(values, middle) || 0
    end
  end
end
