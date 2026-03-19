defmodule ControlKeel.PolicyTraining do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.PolicyTraining.{Artifact, Datasets, Run, Scorer, Trainer}
  alias ControlKeel.Repo

  @artifact_types ~w(router budget_hint)

  def list_training_runs(limit \\ 10) do
    Run
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload(:artifacts)
    |> Repo.all()
  end

  def list_artifacts(opts \\ %{}) do
    opts = stringify_keys(opts)
    limit = normalize_limit(opts["limit"])

    Artifact
    |> maybe_filter_artifact_type(opts["artifact_type"])
    |> maybe_filter_status(opts["status"])
    |> order_by([artifact], desc: artifact.inserted_at, desc: artifact.version)
    |> limit(^limit)
    |> preload(:training_run)
    |> Repo.all()
  end

  def active_artifact(artifact_type) when artifact_type in @artifact_types do
    Artifact
    |> where([artifact], artifact.artifact_type == ^artifact_type and artifact.status == "active")
    |> order_by([artifact], desc: artifact.version, desc: artifact.id)
    |> limit(1)
    |> preload(:training_run)
    |> Repo.one()
  end

  def active_artifact(_artifact_type), do: nil

  def active_artifacts_summary do
    %{
      "router" => active_artifact("router"),
      "budget_hint" => active_artifact("budget_hint")
    }
  end

  def get_artifact(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> get_artifact(parsed)
      _ -> nil
    end
  end

  def get_artifact(id) when is_integer(id) do
    Artifact
    |> Repo.get(id)
    |> case do
      nil -> nil
      artifact -> Repo.preload(artifact, :training_run)
    end
  end

  def start_training(attrs) when is_map(attrs) do
    artifact_type = normalize_artifact_type(Map.get(attrs, "type") || Map.get(attrs, :type))
    baseline_artifact = active_artifact(artifact_type)

    with {:ok, artifact_type} <- validate_artifact_type(artifact_type),
         {:ok, run} <- create_training_run(artifact_type, baseline_artifact),
         :ok <- emit_training_started(run),
         {:ok, bundle} <- Datasets.build(artifact_type),
         {:ok, artifact_payload, trainer_log} <- Trainer.train(training_input(bundle)),
         :ok <- validate_artifact_payload(artifact_payload, artifact_type),
         {:ok, evaluation} <- Datasets.evaluate_artifact(artifact_type, artifact_payload, bundle),
         gates <- promotion_gates(artifact_type, evaluation),
         version <- next_artifact_version(artifact_type),
         {:ok, artifact} <-
           create_artifact(
             run,
             version,
             artifact_type,
             artifact_payload,
             bundle,
             evaluation,
             gates,
             trainer_log,
             baseline_artifact
           ),
         {:ok, updated_run} <-
           finalize_training_run(run, bundle, evaluation, artifact, "trained", nil) do
      :ok = emit_training_completed(updated_run, artifact)
      {:ok, Repo.preload(artifact, :training_run)}
    else
      {:error, reason} ->
        maybe_fail_latest_run(artifact_type, reason)
        {:error, reason}
    end
  end

  def train(attrs), do: start_training(attrs)

  def promote_artifact(id) do
    with %Artifact{} = artifact <- get_artifact(id) || {:error, :not_found},
         gates <- get_in(artifact.metrics, ["gates"]) || %{},
         true <-
           Map.get(gates, "eligible", false) ||
             {:error,
              {:promotion_failed,
               Map.get(gates, "reasons", ["artifact is not eligible for promotion"])}} do
      Multi.new()
      |> Multi.update_all(
        :archive_active,
        from(existing in Artifact,
          where: existing.artifact_type == ^artifact.artifact_type and existing.status == "active"
        ),
        set: [status: "archived", archived_at: now()]
      )
      |> Multi.update(
        :activate_candidate,
        Artifact.changeset(artifact, %{status: "active", activated_at: now(), archived_at: nil})
      )
      |> Multi.update(
        :training_run,
        Run.changeset(artifact.training_run, %{status: "promoted", finished_at: now()})
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{activate_candidate: activated}} ->
          :ok = emit_artifact_promoted(activated)
          {:ok, Repo.preload(activated, :training_run)}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, {:promotion_failed, _reasons}} = error ->
        mark_promotion_failed(id)
        error

      {:error, :not_found} = error ->
        error
    end
  end

  def archive_artifact(id) do
    case get_artifact(id) do
      nil ->
        {:error, :not_found}

      artifact ->
        artifact
        |> Artifact.changeset(%{status: "archived", archived_at: now()})
        |> Repo.update()
    end
  end

  def score_router_candidate(artifact, agent_id, agent_profile, context \\ %{})

  def score_router_candidate(%Artifact{} = artifact, agent_id, agent_profile, context) do
    subject_stats =
      artifact.metadata
      |> Map.get("subject_stats", %{})
      |> Map.get(agent_id, %{})

    features =
      Datasets.router_candidate_features(
        agent_id,
        agent_profile,
        Map.put(stringify_keys(context), "subject_stats", subject_stats)
      )

    case Scorer.score_router(artifact.artifact, features) do
      {:ok, score} ->
        {:ok,
         %{
           score: score,
           policy_source: "learned",
           artifact_version: artifact.version,
           features: features
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def score_router_candidate(_artifact, _agent_id, _agent_profile, _context),
    do: {:error, :no_active_artifact}

  def budget_hint(
        base_result,
        session,
        attrs,
        projected_session,
        projected_daily,
        active_findings_count
      ) do
    decision = Map.get(base_result, "decision") || Map.get(base_result, :decision)

    case active_artifact("budget_hint") do
      %Artifact{} = artifact when decision == "allow" ->
        features =
          Datasets.budget_estimate_features(
            session,
            attrs,
            projected_session,
            projected_daily,
            active_findings_count
          )

        case Scorer.score_budget_hint(artifact.artifact, features) do
          {:ok, probability} ->
            threshold = get_in(artifact.artifact, ["thresholds", "warn_probability"]) || 0.6
            upgrade? = probability >= threshold

            :telemetry.execute(
              [:controlkeel, :budget, :hint_used],
              %{count: 1, probability: probability},
              %{
                artifact_type: "budget_hint",
                artifact_version: artifact.version,
                applied: upgrade?,
                session_id: session.id
              }
            )

            if upgrade? do
              %{
                "decision" => "warn",
                "summary" =>
                  "Advisory: the learned budget policy predicts spend pressure before the hard cap.",
                "hint_source" => "learned",
                "hint_probability" => probability,
                "artifact_version" => artifact.version
              }
            else
              %{
                "decision" => decision,
                "summary" => Map.get(base_result, "summary"),
                "hint_source" => "learned",
                "hint_probability" => probability,
                "artifact_version" => artifact.version
              }
            end

          {:error, _reason} ->
            %{
              "decision" => decision,
              "summary" => Map.get(base_result, "summary"),
              "hint_source" => "heuristic",
              "hint_probability" => nil,
              "artifact_version" => nil
            }
        end

      _ ->
        %{
          "decision" => decision,
          "summary" => Map.get(base_result, "summary"),
          "hint_source" => "heuristic",
          "hint_probability" => nil,
          "artifact_version" => nil
        }
    end
  end

  defp create_training_run(artifact_type, baseline_artifact) do
    %Run{}
    |> Run.changeset(%{
      artifact_type: artifact_type,
      status: "running",
      training_scope: training_scope_for(artifact_type),
      dataset_summary: %{},
      training_metrics: %{},
      validation_metrics: %{},
      held_out_metrics: %{},
      started_at: now(),
      metadata: %{
        "baseline_artifact_version" => baseline_artifact && baseline_artifact.version,
        "controlkeel_version" => ControlKeel.CLI.version(),
        "git_revision" => git_revision()
      }
    })
    |> Repo.insert()
  end

  defp create_artifact(
         %Run{} = run,
         version,
         artifact_type,
         artifact_payload,
         bundle,
         evaluation,
         gates,
         trainer_log,
         baseline_artifact
       ) do
    %Artifact{}
    |> Artifact.changeset(%{
      training_run_id: run.id,
      artifact_type: artifact_type,
      version: version,
      status: "candidate",
      model_family: Map.get(artifact_payload, "model_family"),
      artifact: artifact_payload,
      feature_spec: Map.get(artifact_payload, "feature_spec"),
      metrics: %{
        "train" => evaluation.training_metrics,
        "validation" => evaluation.validation_metrics,
        "held_out" => evaluation.held_out_metrics,
        "baseline" => evaluation.baseline_metrics,
        "gates" => gates
      },
      metadata: %{
        "heuristically_seeded" => Datasets.heuristically_seeded?(bundle),
        "source_suite_slugs" => get_in(bundle, [:metadata, "source_suite_slugs"]) || [],
        "source_run_ids" => get_in(bundle, [:metadata, "source_run_ids"]) || [],
        "source_subject_ids" => get_in(bundle, [:metadata, "subject_ids"]) || [],
        "invocation_sample_size" => get_in(bundle, [:metadata, "invocation_sample_size"]) || 0,
        "training_log" => trainer_log,
        "baseline_artifact_version" => baseline_artifact && baseline_artifact.version,
        "subject_stats" => Map.get(bundle, :subject_stats, %{})
      }
    })
    |> Repo.insert()
  end

  defp finalize_training_run(run, bundle, evaluation, artifact, status, failure_reason) do
    run
    |> Repo.preload(:artifacts)
    |> Run.changeset(%{
      status: status,
      dataset_summary: bundle.dataset_summary,
      training_metrics: evaluation.training_metrics,
      validation_metrics: evaluation.validation_metrics,
      held_out_metrics: evaluation.held_out_metrics,
      failure_reason: failure_reason,
      finished_at: now(),
      metadata:
        run.metadata
        |> Map.put("artifact_id", artifact.id)
        |> Map.put("dataset_metadata", bundle.metadata)
    })
    |> Repo.update()
  end

  defp maybe_fail_latest_run(artifact_type, reason) do
    case latest_running_run(artifact_type) do
      nil ->
        :ok

      run ->
        run
        |> Run.changeset(%{
          status: "failed",
          failure_reason: format_reason(reason),
          finished_at: now()
        })
        |> Repo.update()

        :telemetry.execute(
          [:controlkeel, :policy_training, :failed],
          %{count: 1},
          %{artifact_type: artifact_type, reason: format_reason(reason), run_id: run.id}
        )

        :ok
    end
  end

  defp latest_running_run(artifact_type) do
    Run
    |> where([run], run.artifact_type == ^artifact_type and run.status == "running")
    |> order_by([run], desc: run.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp mark_promotion_failed(id) do
    case get_artifact(id) do
      %Artifact{training_run: %Run{} = run} ->
        run
        |> Run.changeset(%{status: "promotion_failed", finished_at: now()})
        |> Repo.update()

        :ok

      _ ->
        :ok
    end
  end

  defp promotion_gates("router", evaluation) do
    baseline = get_in(evaluation, [:baseline_metrics, "held_out"]) || %{}
    held_out = evaluation.held_out_metrics || %{}
    min_gain = env_float("CONTROLKEEL_POLICY_MIN_HELD_OUT_GAIN", 0.01)
    held_out_reward = Map.get(held_out, "reward", 0.0)
    baseline_reward = Map.get(baseline, "reward", 0.0)
    overhead = Map.get(held_out, "average_overhead_percent", 0.0)
    baseline_overhead = Map.get(baseline, "average_overhead_percent", 0.0)

    reasons =
      []
      |> maybe_gate_reason(
        held_out_reward > baseline_reward + min_gain,
        "held-out reward did not beat the heuristic baseline"
      )
      |> maybe_gate_reason(
        Map.get(held_out, "catch_rate", 0.0) >= Map.get(baseline, "catch_rate", 0.0),
        "held-out catch rate regressed below heuristic baseline"
      )
      |> maybe_gate_reason(
        Map.get(held_out, "expected_rule_hit_rate", 0.0) >=
          Map.get(baseline, "expected_rule_hit_rate", 0.0),
        "held-out expected-rule hit rate regressed below heuristic baseline"
      )
      |> maybe_gate_reason(
        overhead <= baseline_overhead * 1.10 or baseline_overhead == 0.0,
        "held-out average overhead is more than 10% worse than heuristic baseline"
      )

    %{
      "eligible" => reasons == [],
      "reasons" => reasons
    }
  end

  defp promotion_gates("budget_hint", evaluation) do
    held_out = evaluation.held_out_metrics || %{}
    precision_floor = env_float("CONTROLKEEL_POLICY_BUDGET_HINT_PRECISION_FLOOR", 0.6)
    fp_ceiling = env_float("CONTROLKEEL_POLICY_BUDGET_HINT_FP_CEILING", 0.25)

    reasons =
      []
      |> maybe_gate_reason(
        Map.get(held_out, "precision", 0.0) >= precision_floor,
        "held-out precision is below the configured floor"
      )
      |> maybe_gate_reason(
        Map.get(held_out, "false_positive_rate", 1.0) <= fp_ceiling,
        "held-out false-positive rate is above the configured ceiling"
      )

    %{
      "eligible" => reasons == [],
      "reasons" => reasons
    }
  end

  defp validate_artifact_type(type) when type in @artifact_types, do: {:ok, type}
  defp validate_artifact_type(_type), do: {:error, :unknown_artifact_type}

  defp validate_artifact_payload(payload, artifact_type) when is_map(payload) do
    required =
      ~w(schema_version artifact_type model_family feature_spec categorical_vocab normalization network thresholds metrics)

    case Enum.reject(required, &Map.has_key?(payload, &1)) do
      [] ->
        if payload["artifact_type"] == artifact_type do
          :ok
        else
          {:error, :artifact_type_mismatch}
        end

      missing ->
        {:error, {:invalid_artifact, missing}}
    end
  end

  defp validate_artifact_payload(_payload, _artifact_type), do: {:error, :invalid_artifact}

  defp next_artifact_version(artifact_type) do
    Artifact
    |> where([artifact], artifact.artifact_type == ^artifact_type)
    |> select([artifact], max(artifact.version))
    |> Repo.one()
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  defp training_input(bundle) do
    %{
      "artifact_type" => bundle.artifact_type,
      "feature_spec" => bundle.feature_spec,
      "rows" => bundle.rows
    }
  end

  defp training_scope_for("router"), do: "benchmark_matrix"
  defp training_scope_for("budget_hint"), do: "invocation_history"

  defp maybe_filter_artifact_type(query, nil), do: query

  defp maybe_filter_artifact_type(query, artifact_type),
    do: where(query, [artifact], artifact.artifact_type == ^artifact_type)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: where(query, [artifact], artifact.status == ^status)

  defp normalize_artifact_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_artifact_type(value) when is_binary(value), do: String.trim(value)
  defp normalize_artifact_type(_value), do: nil

  defp normalize_limit(nil), do: 20
  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_limit), do: 20

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp stringify_keys(other), do: other

  defp maybe_gate_reason(reasons, true, _reason), do: reasons
  defp maybe_gate_reason(reasons, false, reason), do: [reason | reasons]

  defp env_float(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {parsed, _rest} -> parsed
          :error -> default
        end
    end
  end

  defp emit_training_started(run) do
    :telemetry.execute(
      [:controlkeel, :policy_training, :started],
      %{count: 1},
      %{artifact_type: run.artifact_type, run_id: run.id}
    )

    :ok
  end

  defp emit_training_completed(run, artifact) do
    :telemetry.execute(
      [:controlkeel, :policy_training, :completed],
      %{count: 1},
      %{artifact_type: run.artifact_type, run_id: run.id, artifact_id: artifact.id}
    )

    :ok
  end

  defp emit_artifact_promoted(artifact) do
    :telemetry.execute(
      [:controlkeel, :policy_artifact, :promoted],
      %{count: 1},
      %{
        artifact_type: artifact.artifact_type,
        artifact_id: artifact.id,
        version: artifact.version
      }
    )

    :ok
  end

  defp git_revision do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> "unknown"
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
