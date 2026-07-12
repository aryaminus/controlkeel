defmodule ControlKeel.Runtime.BoundedLoop do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Runtime.BoundedLoopReviewPolicy

  @contract_type "bounded_loop_contract"
  @iteration_type "bounded_loop_iteration"
  @stop_type "bounded_loop_stop"
  @max_iterations 100
  @max_duration_seconds 86_400
  @artifact_classes ~w(ephemeral_experiment mechanical_transformation research security_triage lasting_code)
  @complexity_keys ~w(fallback_branches dependencies public_interfaces cyclomatic_complexity changed_lines)

  def create(arguments) do
    with {:ok, ids} <- ids(arguments),
         :ok <- task_belongs_to_session(ids),
         :ok <- no_blocked_findings(ids.session_id),
         {:ok, root} <- project_root(arguments),
         {:ok, mutable_paths} <- paths(arguments, "mutable_paths", root, false),
         {:ok, verifier_paths} <- paths(arguments, "verifier_paths", root, true),
         :ok <- disjoint_paths(mutable_paths, verifier_paths),
         {:ok, limits} <- limits(arguments),
         {:ok, sandbox_policy} <- sandbox_policy(arguments),
         {:ok, metric} <- metric(arguments),
         {:ok, longevity_policy} <- longevity_policy(arguments),
         {:ok, verifier_command} <- required_string(arguments, "verifier_command"),
         :ok <- no_active_contract(ids),
         {:ok, hashes} <- verifier_hashes(root, verifier_paths),
         now <- DateTime.utc_now() |> DateTime.truncate(:second),
         payload <-
           Map.merge(limits, metric)
           |> Map.merge(sandbox_policy)
           |> Map.merge(longevity_policy)
           |> Map.merge(%{
             "version" => 2,
             "status" => "active",
             "project_root" => root,
             "mutable_paths" => mutable_paths,
             "verifier_paths" => verifier_paths,
             "verifier_hashes" => hashes,
             "verifier_command" => verifier_command,
             "started_at" => DateTime.to_iso8601(now)
           }),
         {:ok, checkpoint} <- checkpoint(ids, @contract_type, "Bounded loop contract", payload) do
      {:ok, status(ids, checkpoint, [], nil)}
    end
  end

  def record(arguments) do
    with {:ok, ids} <- ids(arguments),
         :ok <- task_belongs_to_session(ids),
         {:ok, contract, iterations, stop} <- state(ids),
         :ok <- active(stop),
         {:ok, index} <- positive_integer(arguments, "iteration"),
         :ok <- next_iteration(index, iterations),
         {:ok, value} <- number(arguments, "metric_value"),
         {:ok, promotion_packet} <- promotion_packet(arguments, ids, contract.payload, value),
         {:ok, cost} <- non_negative_integer(arguments, "cost_cents", 0),
         {:ok, changed_paths} <- changed_paths(arguments, contract.payload),
         {:ok, sandbox} <- sandbox_evidence(arguments, contract.payload, iterations),
         {:ok, comprehension} <- comprehension_evidence(arguments),
         {:ok, longevity} <- longevity_evidence(arguments, contract.payload),
         {:ok, current_hashes} <-
           verifier_hashes(contract.payload["project_root"], contract.payload["verifier_paths"]),
         decision <-
           decide(contract.payload, iterations, index, value, cost, current_hashes, arguments),
         payload <-
           Map.merge(sandbox, comprehension)
           |> Map.merge(longevity)
           |> Map.merge(promotion_packet)
           |> Map.merge(%{
             "iteration" => index,
             "metric_value" => value,
             "cost_cents" => cost,
             "changed_paths" => changed_paths,
             "verifier_passed" => Map.get(arguments, "verifier_passed", true) == true,
             "verifier_hashes" => current_hashes,
             "decision" => decision["status"],
             "reason" => decision["reason"],
             "rollback_required" => decision["rollback_required"],
             "improved" => decision["improved"],
             "summary" => to_string(Map.get(arguments, "summary", ""))
           }),
         {:ok, iteration} <-
           checkpoint(ids, @iteration_type, "Bounded loop iteration #{index}", payload),
         {:ok, stop_checkpoint} <- maybe_stop(ids, decision, payload) do
      all_iterations = [iteration | iterations]

      {:ok,
       status(ids, contract, all_iterations, stop_checkpoint) |> Map.put("decision", decision)}
    end
  end

  def status(arguments) do
    with {:ok, ids} <- ids(arguments),
         :ok <- task_belongs_to_session(ids),
         {:ok, contract, iterations, stop} <- state(ids) do
      {:ok, status(ids, contract, iterations, stop)}
    end
  end

  def stop(arguments) do
    with {:ok, ids} <- ids(arguments),
         :ok <- task_belongs_to_session(ids),
         {:ok, contract, iterations, stop} <- state(ids),
         :ok <- active(stop),
         reason <- to_string(Map.get(arguments, "reason", "operator_stopped")),
         {:ok, stop_checkpoint} <- stop_checkpoint(ids, "stopped", reason) do
      {:ok, status(ids, contract, iterations, stop_checkpoint)}
    end
  end

  def promote(arguments) do
    with {:ok, ids} <- ids(arguments),
         :ok <- task_belongs_to_session(ids),
         {:ok, contract, iterations, stop} <- state(ids),
         :ok <- awaiting_review(stop),
         {:ok, review_id} <- positive_integer(arguments, "review_id"),
         :ok <- promotion_packet_fresh(contract.payload, stop),
         :ok <- BoundedLoopReviewPolicy.approved_review(ids, review_id, stop, contract),
         {:ok, promoted} <-
           checkpoint(ids, @stop_type, "Bounded loop promoted", %{
             "status" => "succeeded",
             "reason" => "independent_review_approved",
             "review_id" => review_id
           }) do
      {:ok, status(ids, contract, iterations, promoted)}
    end
  end

  defp decide(contract, iterations, index, value, cost, hashes, arguments) do
    total_cost = cost + Enum.sum(Enum.map(iterations, &(&1.payload["cost_cents"] || 0)))
    previous_values = Enum.map(iterations, & &1.payload["metric_value"])
    best = best_value(previous_values, contract["direction"])
    improved = is_nil(best) or better?(value, best, contract["direction"])
    no_progress = consecutive_no_progress(iterations) + if(improved, do: 0, else: 1)
    elapsed = elapsed_seconds(contract["started_at"])
    verifier_passed = Map.get(arguments, "verifier_passed", true) == true
    longevity_decision = longevity_decision(contract, iterations, arguments)

    cond do
      hashes != contract["verifier_hashes"] ->
        decision("blocked", "verifier_drift", false, true)

      blocked_findings?(contract, arguments) ->
        decision("blocked", "blocked_finding", false, true)

      not verifier_passed ->
        terminal_or_reject(
          contract,
          index,
          total_cost,
          elapsed,
          no_progress,
          false,
          "verifier_failed"
        )

      longevity_decision != nil ->
        longevity_decision

      total_cost > contract["max_cost_cents"] ->
        decision("stopped", "cost_limit", improved, not improved)

      elapsed > contract["max_duration_seconds"] ->
        decision("stopped", "deadline", improved, not improved)

      target_met?(value, contract) ->
        decision("awaiting_review", "target_met", improved)

      index >= contract["max_iterations"] ->
        decision("stopped", "iteration_limit", improved, not improved)

      no_progress >= contract["no_progress_limit"] ->
        decision("stopped", "no_progress_limit", improved, not improved)

      improved ->
        decision("accept", "metric_improved", true)

      true ->
        decision("reject", "metric_not_improved", false, true)
    end
  end

  defp terminal_or_reject(contract, index, cost, elapsed, no_progress, improved, reason) do
    cond do
      cost > contract["max_cost_cents"] ->
        decision("stopped", "cost_limit", improved, not improved)

      elapsed > contract["max_duration_seconds"] ->
        decision("stopped", "deadline", improved, not improved)

      index >= contract["max_iterations"] ->
        decision("stopped", "iteration_limit", improved, not improved)

      no_progress >= contract["no_progress_limit"] ->
        decision("stopped", "no_progress_limit", improved, not improved)

      true ->
        decision("reject", reason, improved, true)
    end
  end

  defp decision(status, reason, improved, rollback_required \\ false),
    do: %{
      "status" => status,
      "reason" => reason,
      "improved" => improved,
      "rollback_required" => rollback_required
    }

  defp maybe_stop(ids, %{"status" => status, "reason" => reason}, iteration)
       when status in ["awaiting_review", "stopped", "blocked"],
       do: stop_checkpoint(ids, status, reason, iteration)

  defp maybe_stop(_ids, _decision, _iteration), do: {:ok, nil}

  defp stop_checkpoint(ids, status, reason, iteration \\ %{}) do
    payload = %{"status" => status, "reason" => reason}

    payload =
      if status == "awaiting_review" and is_map(iteration["promotion_packet"]),
        do: Map.put(payload, "promotion_packet", iteration["promotion_packet"]),
        else: payload

    checkpoint(ids, @stop_type, "Bounded loop #{status}", payload)
  end

  defp checkpoint(ids, type, summary, payload) do
    Mission.create_task_checkpoint(%{
      session_id: ids.session_id,
      task_id: ids.task_id,
      checkpoint_type: type,
      summary: summary,
      payload: payload,
      created_by: "ck_loop"
    })
  end

  defp state(ids) do
    checkpoints = Mission.list_task_checkpoints(ids.session_id, ids.task_id)
    contract = Enum.find(checkpoints, &(&1.checkpoint_type == @contract_type))

    if contract do
      iterations =
        checkpoints
        |> Enum.filter(&(&1.checkpoint_type == @iteration_type and &1.id > contract.id))
        |> Enum.sort_by(& &1.payload["iteration"], :desc)

      stop = Enum.find(checkpoints, &(&1.checkpoint_type == @stop_type and &1.id > contract.id))
      {:ok, contract, iterations, stop}
    else
      {:error, {:invalid_arguments, "No bounded loop contract exists for this task"}}
    end
  end

  defp status(ids, contract, iterations, stop) do
    values = Enum.map(iterations, & &1.payload["metric_value"])

    %{
      "session_id" => ids.session_id,
      "task_id" => ids.task_id,
      "contract_id" => contract.id,
      "status" => if(stop, do: stop.payload["status"], else: "active"),
      "stop_reason" => if(stop, do: stop.payload["reason"], else: nil),
      "contract" => contract.payload,
      "iteration_count" => length(iterations),
      "cost_cents" => Enum.sum(Enum.map(iterations, &(&1.payload["cost_cents"] || 0))),
      "best_metric" => best_value(values, contract.payload["direction"]),
      "iterations" => Enum.map(iterations, & &1.payload)
    }
  end

  defp ids(arguments) do
    with {:ok, session_id} <- positive_integer(arguments, "session_id"),
         {:ok, task_id} <- positive_integer(arguments, "task_id") do
      {:ok, %{session_id: session_id, task_id: task_id}}
    end
  end

  defp task_belongs_to_session(ids) do
    case Mission.get_task(ids.task_id) do
      %{session_id: session_id} when session_id == ids.session_id -> :ok
      nil -> {:error, {:invalid_arguments, "Task not found"}}
      _ -> {:error, {:invalid_arguments, "Task does not belong to the current session"}}
    end
  end

  defp no_active_contract(ids) do
    case state(ids) do
      {:error, _} ->
        :ok

      {:ok, _contract, _iterations, nil} ->
        {:error, {:invalid_arguments, "An active bounded loop already exists for this task"}}

      {:ok, _contract, _iterations, _stop} ->
        :ok
    end
  end

  defp project_root(arguments) do
    root = Map.get(arguments, "project_root", File.cwd!()) |> Path.expand()

    if File.dir?(root),
      do: {:ok, root},
      else: {:error, {:invalid_arguments, "project_root must exist"}}
  end

  defp paths(arguments, key, root, must_exist) do
    values = Map.get(arguments, key, [])

    if is_list(values) and values != [] do
      values
      |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
        case normalize_path(value, root, must_exist) do
          {:ok, path} -> {:cont, {:ok, [path | acc]}}
          error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, normalized} -> {:ok, normalized |> Enum.uniq() |> Enum.sort()}
        error -> error
      end)
    else
      {:error, {:invalid_arguments, "#{key} must be a non-empty array"}}
    end
  end

  defp normalize_path(value, root, must_exist) when is_binary(value) do
    expanded = Path.expand(value, root)
    relative = Path.relative_to(expanded, root)

    cond do
      Path.type(value) == :absolute or relative == "." or String.starts_with?(relative, "..") ->
        {:error,
         {:invalid_arguments, "Loop paths must be relative and remain inside project_root"}}

      symlink_in_path?(root, relative) ->
        {:error, {:invalid_arguments, "Loop paths may not contain symlinks"}}

      must_exist and not File.exists?(expanded) ->
        {:error, {:invalid_arguments, "Verifier path does not exist: #{relative}"}}

      true ->
        {:ok, relative}
    end
  end

  defp normalize_path(_, _root, _must_exist),
    do: {:error, {:invalid_arguments, "Loop paths must be strings"}}

  defp symlink_in_path?(root, relative) do
    relative
    |> Path.split()
    |> Enum.reduce_while(root, fn part, current ->
      next = Path.join(current, part)

      if match?({:ok, %{type: :symlink}}, File.lstat(next)),
        do: {:halt, true},
        else: {:cont, next}
    end)
    |> then(&(&1 == true))
  end

  defp disjoint_paths(mutable, verifier) do
    overlap? = Enum.any?(mutable, fn left -> Enum.any?(verifier, &paths_overlap?(left, &1)) end)

    if overlap?,
      do: {:error, {:invalid_arguments, "mutable_paths and verifier_paths must be disjoint"}},
      else: :ok
  end

  defp paths_overlap?(left, right),
    do:
      left == right or String.starts_with?(left, right <> "/") or
        String.starts_with?(right, left <> "/")

  defp limits(arguments) do
    with {:ok, iterations} <- bounded_integer(arguments, "max_iterations", 10, 1, @max_iterations),
         {:ok, cost} <- bounded_integer(arguments, "max_cost_cents", 100, 1, 1_000_000),
         {:ok, duration} <-
           bounded_integer(arguments, "max_duration_seconds", 3_600, 1, @max_duration_seconds),
         {:ok, no_progress} <- bounded_integer(arguments, "no_progress_limit", 3, 1, 20) do
      {:ok,
       %{
         "max_iterations" => iterations,
         "max_cost_cents" => cost,
         "max_duration_seconds" => duration,
         "no_progress_limit" => no_progress
       }}
    end
  end

  defp metric(arguments) do
    direction = Map.get(arguments, "direction")

    with {:ok, name} <- required_string(arguments, "metric_name"),
         true <-
           direction in ["maximize", "minimize"] ||
             {:error, {:invalid_arguments, "direction must be maximize or minimize"}},
         {:ok, target} <- number(arguments, "target") do
      {:ok, %{"metric_name" => name, "direction" => direction, "target" => target}}
    end
  end

  defp verifier_hashes(root, paths) do
    paths
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, hashes} ->
      case hash_path(root, path) do
        {:ok, hash} -> {:cont, {:ok, Map.put(hashes, path, hash)}}
        error -> {:halt, error}
      end
    end)
  end

  defp hash_path(root, relative) do
    full = Path.join(root, relative)

    cond do
      not File.exists?(full) ->
        {:error, {:invalid_arguments, "Verifier path no longer exists: #{relative}"}}

      symlink_in_path?(root, relative) ->
        {:error, {:invalid_arguments, "Verifier path contains a symlink: #{relative}"}}

      true ->
        files =
          if File.dir?(full) do
            full
            |> Path.join("**/*")
            |> Path.wildcard(match_dot: true)
            |> Enum.filter(&File.regular?/1)
          else
            [full]
          end

        if Enum.any?(files, &match?({:ok, %{type: :symlink}}, File.lstat(&1))) do
          {:error, {:invalid_arguments, "Verifier directory contains a symlink: #{relative}"}}
        else
          hash_files(files, root)
        end
    end
  end

  defp hash_files(files, root) do
    files
    |> Enum.sort()
    |> Enum.reduce_while({:ok, :crypto.hash_init(:sha256)}, fn file, {:ok, context} ->
      case File.read(file) do
        {:ok, content} ->
          rel = Path.relative_to(file, root)
          {:cont, {:ok, :crypto.hash_update(context, rel <> "\0" <> content)}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_arguments, "Cannot read verifier path: #{inspect(reason)}"}}}
      end
    end)
    |> then(fn
      {:ok, context} -> {:ok, context |> :crypto.hash_final() |> Base.encode16(case: :lower)}
      error -> error
    end)
  end

  defp changed_paths(arguments, contract) do
    with {:ok, paths} <-
           paths(arguments, "changed_paths", contract["project_root"], false),
         true <-
           Enum.all?(paths, fn path ->
             Enum.any?(contract["mutable_paths"], &path_covered_by?(path, &1))
           end) || {:error, {:invalid_arguments, "changed_paths exceed mutable_paths"}} do
      {:ok, paths}
    end
  end

  defp path_covered_by?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp sandbox_policy(arguments) do
    adapters = Map.get(arguments, "allowed_sandbox_adapters", ["docker"])

    cond do
      not is_list(adapters) or adapters == [] or
          Enum.any?(adapters, &(&1 not in ["docker", "e2b", "nono"])) ->
        {:error,
         {:invalid_arguments, "allowed_sandbox_adapters must contain only docker, e2b, or nono"}}

      Map.get(arguments, "require_ephemeral_environment", true) != true ->
        {:error, {:invalid_arguments, "require_ephemeral_environment must be true"}}

      true ->
        {:ok,
         %{
           "allowed_sandbox_adapters" => Enum.sort(Enum.uniq(adapters)),
           "require_ephemeral_environment" => true
         }}
    end
  end

  defp sandbox_evidence(arguments, contract, iterations) do
    with {:ok, adapter} <- required_string(arguments, "sandbox_adapter"),
         true <-
           adapter in contract["allowed_sandbox_adapters"] ||
             {:error, {:invalid_arguments, "sandbox_adapter is not allowed by the contract"}},
         {:ok, environment_id} <- required_string(arguments, "environment_id"),
         :ok <- unique_environment(environment_id, iterations) do
      {:ok, %{"sandbox_adapter" => adapter, "environment_id" => environment_id}}
    end
  end

  defp unique_environment(environment_id, iterations) do
    if Enum.any?(iterations, &(&1.payload["environment_id"] == environment_id)),
      do: {:error, {:invalid_arguments, "environment_id must be unique for every iteration"}},
      else: :ok
  end

  defp comprehension_evidence(arguments) do
    with {:ok, hypothesis} <- required_string(arguments, "hypothesis"),
         {:ok, mechanism} <- required_string(arguments, "mechanism"),
         {:ok, observed_effect} <- required_string(arguments, "observed_effect"),
         {:ok, documentation_impact} <- required_string(arguments, "documentation_impact") do
      {:ok,
       %{
         "hypothesis" => hypothesis,
         "mechanism" => mechanism,
         "observed_effect" => observed_effect,
         "documentation_impact" => documentation_impact
       }}
    end
  end

  defp longevity_policy(arguments) do
    artifact_class = Map.get(arguments, "artifact_class")

    cond do
      artifact_class not in @artifact_classes ->
        {:error,
         {:invalid_arguments,
          "artifact_class must be ephemeral_experiment, mechanical_transformation, research, security_triage, or lasting_code"}}

      artifact_class == "lasting_code" ->
        lasting_code_policy(arguments)

      true ->
        {:ok, %{"artifact_class" => artifact_class}}
    end
  end

  defp lasting_code_policy(arguments) do
    with {:ok, invariant_boundaries} <- string_list(arguments, "invariant_boundaries", false),
         {:ok, allowed_changes} <- string_list(arguments, "allowed_semantic_changes", true),
         {:ok, forbidden_changes} <- string_list(arguments, "forbidden_semantic_changes", false),
         {:ok, independence} <-
           string_list(arguments, "machine_independence_requirements", false),
         {:ok, review_risk} <- enum(arguments, "review_risk", ~w(standard high critical)),
         {:ok, required_review_personas} <-
           string_list(arguments, "required_review_personas", false),
         {:ok, complexity_budget} <-
           integer_map(arguments, "complexity_budget", 0, 1_000_000),
         :ok <- exact_keys(complexity_budget, @complexity_keys, "complexity_budget"),
         {:ok, local_defense_limit} <-
           bounded_integer(arguments, "local_defense_limit", nil, 1, 20),
         true <-
           Map.get(arguments, "human_promotion_required") == true ||
             {:error,
              {:invalid_arguments, "human_promotion_required must be true for lasting_code"}} do
      {:ok,
       %{
         "artifact_class" => "lasting_code",
         "invariant_boundaries" => invariant_boundaries,
         "allowed_semantic_changes" => allowed_changes,
         "forbidden_semantic_changes" => forbidden_changes,
         "machine_independence_requirements" => independence,
         "review_risk" => review_risk,
         "required_review_personas" => required_review_personas,
         "complexity_budget" => complexity_budget,
         "local_defense_limit" => local_defense_limit,
         "human_promotion_required" => true
       }}
    end
  end

  defp longevity_evidence(arguments, %{"artifact_class" => "lasting_code"} = contract) do
    with {:ok, invariant_effect} <-
           enum(
             arguments,
             "invariant_effect",
             ~w(strengthened preserved local_defense_added unknown)
           ),
         {:ok, invariant_evidence} <- required_string(arguments, "invariant_evidence"),
         {:ok, semantic_changes} <- string_list(arguments, "semantic_changes", true),
         :ok <- semantic_changes_allowed(semantic_changes, contract),
         {:ok, complexity_delta} <-
           integer_map(arguments, "complexity_delta", -1_000_000, 1_000_000),
         :ok <- exact_keys(complexity_delta, @complexity_keys, "complexity_delta"),
         {:ok, machine_independence_verified} <-
           boolean(arguments, "machine_independence_verified"),
         {:ok, machine_independence_evidence} <-
           required_string(arguments, "machine_independence_evidence"),
         {:ok, call_graph} <- required_string(arguments, "call_graph"),
         {:ok, diagnosis_path} <- required_string(arguments, "diagnosis_path"),
         {:ok, rollback_path} <- required_string(arguments, "rollback_path"),
         {:ok, maintenance_without_model} <-
           required_string(arguments, "maintenance_without_model") do
      {:ok,
       %{
         "invariant_effect" => invariant_effect,
         "invariant_evidence" => invariant_evidence,
         "semantic_changes" => semantic_changes,
         "complexity_delta" => complexity_delta,
         "machine_independence_verified" => machine_independence_verified,
         "machine_independence_evidence" => machine_independence_evidence,
         "call_graph" => call_graph,
         "diagnosis_path" => diagnosis_path,
         "rollback_path" => rollback_path,
         "maintenance_without_model" => maintenance_without_model
       }}
    end
  end

  defp longevity_evidence(_arguments, _contract), do: {:ok, %{}}

  defp longevity_decision(%{"artifact_class" => "lasting_code"} = contract, iterations, arguments) do
    effect = arguments["invariant_effect"]

    cond do
      effect == "unknown" ->
        decision("reject", "invariant_effect_unknown", false, true)

      effect == "local_defense_added" and
          local_defense_count(iterations) + 1 >= contract["local_defense_limit"] ->
        decision("stopped", "local_defense_limit", false, true)

      effect == "local_defense_added" ->
        decision("reject", "local_defense_added", false, true)

      arguments["machine_independence_verified"] != true ->
        decision("reject", "machine_independence_failed", false, true)

      complexity_exceeded?(contract, iterations, arguments["complexity_delta"]) ->
        decision("reject", "complexity_budget_exceeded", false, true)

      true ->
        nil
    end
  end

  defp longevity_decision(_contract, _iterations, _arguments), do: nil

  defp local_defense_count(iterations) do
    Enum.count(iterations, &(&1.payload["invariant_effect"] == "local_defense_added"))
  end

  defp complexity_exceeded?(contract, iterations, candidate) do
    accepted = Enum.filter(iterations, &(&1.payload["decision"] == "accept"))

    Enum.any?(@complexity_keys, fn key ->
      total =
        Enum.reduce(accepted, candidate[key], fn iteration, sum ->
          sum + get_in(iteration.payload, ["complexity_delta", key])
        end)

      max(total, 0) > contract["complexity_budget"][key]
    end)
  end

  defp semantic_changes_allowed(changes, contract) do
    allowed = contract["allowed_semantic_changes"]
    forbidden = contract["forbidden_semantic_changes"]

    cond do
      Enum.any?(changes, &(&1 in forbidden)) ->
        {:error, {:invalid_arguments, "semantic_changes include a forbidden change"}}

      Enum.any?(changes, &(&1 not in allowed)) ->
        {:error, {:invalid_arguments, "semantic_changes exceed allowed_semantic_changes"}}

      true ->
        :ok
    end
  end

  defp string_list(arguments, key, allow_empty) do
    case Map.get(arguments, key) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) and (allow_empty or values != []),
          do: {:ok, Enum.uniq(values)},
          else: {:error, {:invalid_arguments, "#{key} must contain non-empty strings"}}

      _ ->
        {:error, {:invalid_arguments, "#{key} must be an array"}}
    end
  end

  defp integer_map(arguments, key, min, max) do
    case Map.get(arguments, key) do
      value when is_map(value) ->
        if Enum.all?(value, fn {k, v} ->
             is_binary(k) and is_integer(v) and v >= min and v <= max
           end),
           do: {:ok, value},
           else:
             {:error,
              {:invalid_arguments, "#{key} values must be integers between #{min} and #{max}"}}

      _ ->
        {:error, {:invalid_arguments, "#{key} must be an object"}}
    end
  end

  defp exact_keys(map, keys, name) do
    if Enum.sort(Map.keys(map)) == Enum.sort(keys),
      do: :ok,
      else: {:error, {:invalid_arguments, "#{name} must define exactly #{Enum.join(keys, ", ")}"}}
  end

  defp enum(arguments, key, allowed) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        if value in allowed,
          do: {:ok, value},
          else:
            {:error, {:invalid_arguments, "#{key} must be one of #{Enum.join(allowed, ", ")}"}}

      _ ->
        {:error, {:invalid_arguments, "#{key} must be one of #{Enum.join(allowed, ", ")}"}}
    end
  end

  defp boolean(arguments, key) do
    case Map.fetch(arguments, key) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} must be a boolean"}}
    end
  end

  defp promotion_packet(arguments, ids, %{"artifact_class" => "lasting_code"} = contract, value) do
    if target_met?(value, contract) do
      with {:ok, packet} <- required_map(arguments, "promotion_packet"),
           {:ok, worker_identity} <- BoundedLoopReviewPolicy.worker_identity(packet, ids),
           {:ok, changed_behavior} <- required_string(packet, "changed_behavior"),
           {:ok, owning_invariant} <- required_string(packet, "owning_invariant"),
           :ok <- declared_invariant(owning_invariant, contract),
           {:ok, bad_state} <- required_string(packet, "bad_state_made_impossible"),
           {:ok, fallbacks_removed} <- string_list(packet, "fallbacks_removed", true),
           {:ok, affected_interfaces} <- string_list(packet, "affected_interfaces", false),
           {:ok, code_citations} <- citations(packet, "code_citations"),
           {:ok, test_citations} <- citations(packet, "test_citations"),
           {:ok, test_commands} <- string_list(packet, "test_commands", false),
           {:ok, build_commands} <- string_list(packet, "build_commands", false),
           {:ok, diagnosis_commands} <- string_list(packet, "diagnosis_commands", false),
           {:ok, rollback_commands} <- string_list(packet, "rollback_commands", false),
           {:ok, documentation_paths} <- relative_paths(packet, "documentation_paths"),
           {:ok, evidence_hashes} <-
             evidence_snapshot(
               contract["project_root"],
               code_citations,
               test_citations,
               documentation_paths
             ) do
        {:ok,
         %{
           "promotion_packet" => %{
             "worker_identity" => worker_identity,
             "review_policy" => %{
               "review_risk" => contract["review_risk"],
               "required_review_personas" => contract["required_review_personas"]
             },
             "changed_behavior" => changed_behavior,
             "owning_invariant" => owning_invariant,
             "bad_state_made_impossible" => bad_state,
             "fallbacks_removed" => fallbacks_removed,
             "affected_interfaces" => affected_interfaces,
             "code_citations" => code_citations,
             "test_citations" => test_citations,
             "test_commands" => test_commands,
             "build_commands" => build_commands,
             "diagnosis_commands" => diagnosis_commands,
             "rollback_commands" => rollback_commands,
             "documentation_paths" => documentation_paths,
             "evidence_hashes" => evidence_hashes
           }
         }}
      end
    else
      {:ok, %{}}
    end
  end

  defp promotion_packet(_arguments, _ids, _contract, _value), do: {:ok, %{}}

  defp required_map(arguments, key) do
    case Map.get(arguments, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} must be an object"}}
    end
  end

  defp declared_invariant(invariant, contract) do
    if invariant in contract["invariant_boundaries"],
      do: :ok,
      else: {:error, {:invalid_arguments, "owning_invariant must name a declared invariant"}}
  end

  defp citations(arguments, key) do
    with {:ok, values} <- string_list(arguments, key, false),
         true <-
           Enum.all?(values, &valid_citation?/1) ||
             {:error, {:invalid_arguments, "#{key} must use path:line or path:start-end"}} do
      {:ok, values}
    end
  end

  defp valid_citation?(citation) do
    case Regex.run(~r/^(.+):\d+(?:-\d+)?$/, citation, capture: :all_but_first) do
      [path] -> relative_path?(path)
      _ -> false
    end
  end

  defp relative_paths(arguments, key) do
    with {:ok, values} <- string_list(arguments, key, false),
         true <-
           Enum.all?(values, &relative_path?/1) ||
             {:error, {:invalid_arguments, "#{key} must contain relative paths"}} do
      {:ok, values}
    end
  end

  defp relative_path?(value) do
    Path.type(value) == :relative and value != "." and
      not Enum.member?(Path.split(value), "..")
  end

  defp evidence_snapshot(root, code_citations, test_citations, documentation_paths) do
    citations = code_citations ++ test_citations

    with :ok <- validate_citation_lines(root, citations),
         paths <-
           (Enum.map(citations, &citation_path/1) ++ documentation_paths)
           |> Enum.uniq()
           |> Enum.sort(),
         :ok <- regular_evidence_files(root, paths),
         {:ok, hashes} <- verifier_hashes(root, paths) do
      {:ok, hashes}
    end
  end

  defp validate_citation_lines(root, citations) do
    Enum.reduce_while(citations, :ok, fn citation, :ok ->
      {path, first, last} = citation_parts(citation)

      case File.read(Path.join(root, path)) do
        {:ok, content} ->
          line_count =
            if content == "" do
              0
            else
              length(:binary.matches(content, "\n")) +
                if(String.ends_with?(content, "\n"), do: 0, else: 1)
            end

          if first <= last and last <= line_count,
            do: {:cont, :ok},
            else:
              {:halt, {:error, {:invalid_arguments, "Citation is outside the file: #{citation}"}}}

        {:error, _reason} ->
          {:halt, {:error, {:invalid_arguments, "Cited file does not exist: #{path}"}}}
      end
    end)
  end

  defp regular_evidence_files(root, paths) do
    case Enum.find(paths, fn path -> not File.regular?(Path.join(root, path)) end) do
      nil -> :ok
      path -> {:error, {:invalid_arguments, "Evidence path must be a file: #{path}"}}
    end
  end

  defp citation_path(citation) do
    {path, _first, _last} = citation_parts(citation)
    path
  end

  defp citation_parts(citation) do
    case Regex.run(~r/^(.+):(\d+)(?:-(\d+))?$/, citation, capture: :all_but_first) do
      [path, line] ->
        line = String.to_integer(line)
        {path, line, line}

      [path, first, last] ->
        {path, String.to_integer(first), String.to_integer(last)}
    end
  end

  defp promotion_packet_fresh(%{"artifact_class" => "lasting_code"} = contract, stop) do
    packet = stop.payload["promotion_packet"] || %{}
    expected = packet["evidence_hashes"] || %{}

    with true <-
           map_size(expected) > 0 ||
             {:error, {:invalid_arguments, "Promotion packet has no evidence snapshot"}},
         {:ok, current} <- verifier_hashes(contract["project_root"], Map.keys(expected)),
         true <-
           current == expected ||
             {:error, {:invalid_arguments, "Promotion evidence changed after target review"}} do
      :ok
    end
  end

  defp promotion_packet_fresh(_contract, _stop), do: :ok

  defp next_iteration(index, iterations) do
    expected = length(iterations) + 1

    if index == expected,
      do: :ok,
      else: {:error, {:invalid_arguments, "iteration must be #{expected}"}}
  end

  defp active(nil), do: :ok
  defp active(_), do: {:error, {:invalid_arguments, "Bounded loop is no longer active"}}

  defp awaiting_review(%{payload: %{"status" => "awaiting_review"}}), do: :ok

  defp awaiting_review(_),
    do: {:error, {:invalid_arguments, "Bounded loop is not awaiting promotion review"}}

  defp blocked_findings?(_contract, arguments) do
    session_id = Map.get(arguments, "session_id")
    Mission.list_findings_for_session(session_id) |> Enum.any?(&(&1.status == "blocked"))
  end

  defp no_blocked_findings(session_id) do
    if Mission.list_findings_for_session(session_id) |> Enum.any?(&(&1.status == "blocked")),
      do: {:error, {:invalid_arguments, "Session has blocked findings"}},
      else: :ok
  end

  defp better?(value, best, "maximize"), do: value > best
  defp better?(value, best, "minimize"), do: value < best
  defp target_met?(value, %{"direction" => "maximize", "target" => target}), do: value >= target
  defp target_met?(value, %{"direction" => "minimize", "target" => target}), do: value <= target
  defp best_value([], _direction), do: nil
  defp best_value(values, "maximize"), do: Enum.max(values)
  defp best_value(values, "minimize"), do: Enum.min(values)

  defp consecutive_no_progress(iterations) do
    iterations
    |> Enum.take_while(&(&1.payload["improved"] == false))
    |> length()
  end

  defp elapsed_seconds(started_at) do
    with {:ok, started, _offset} <- DateTime.from_iso8601(started_at) do
      DateTime.diff(DateTime.utc_now(), started, :second)
    else
      _ -> @max_duration_seconds + 1
    end
  end

  defp required_string(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} is required"}}
    end
  end

  defp number(arguments, key) do
    case Map.get(arguments, key) do
      value when is_number(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} must be a number"}}
    end
  end

  defp positive_integer(arguments, key) do
    value = Map.get(arguments, key)
    parsed = if is_binary(value), do: Integer.parse(value), else: {value, ""}

    case parsed do
      {integer, ""} when is_integer(integer) ->
        bounded_integer(Map.put(arguments, key, integer), key, nil, 1, 2_147_483_647)

      _ ->
        bounded_integer(arguments, key, nil, 1, 2_147_483_647)
    end
  end

  defp non_negative_integer(arguments, key, default),
    do: bounded_integer(arguments, key, default, 0, 1_000_000)

  defp bounded_integer(arguments, key, default, min, max) do
    value = Map.get(arguments, key, default)

    if is_integer(value) and value >= min and value <= max,
      do: {:ok, value},
      else: {:error, {:invalid_arguments, "#{key} must be an integer between #{min} and #{max}"}}
  end
end
