defmodule ControlKeel.Runtime.BoundedLoopReviewPolicy do
  @moduledoc false

  alias ControlKeel.Mission

  def worker_identity(arguments, ids) do
    with {:ok, value} <- required_map(arguments, "worker_identity"),
         {:ok, agent_id} <- required_string(value, "agent_id"),
         {:ok, invocation_id} <- positive_integer(value, "invocation_id"),
         {:ok, identity} <- trusted_identity(ids, invocation_id, agent_id) do
      {:ok, identity}
    end
  end

  def approved_review(ids, review_id, stop, contract) do
    case Mission.get_review(review_id) do
      %{
        session_id: session_id,
        task_id: task_id,
        status: "approved",
        review_type: type,
        submitted_by: submitted_by,
        reviewed_by: reviewed_by,
        responded_at: responded_at,
        annotations: annotations
      }
      when session_id == ids.session_id and task_id == ids.task_id and
             type in ["diff", "completion"] and is_binary(reviewed_by) and reviewed_by != "" and
             reviewed_by != submitted_by and not is_nil(responded_at) ->
        with true <-
               DateTime.compare(responded_at, stop.inserted_at) in [:eq, :gt] ||
                 {:error, {:invalid_arguments, "Review predates the target iteration"}},
             :ok <- ownership_attestations(contract.payload, stop, annotations, reviewed_by, ids) do
          :ok
        end

      nil ->
        {:error, {:invalid_arguments, "Review not found"}}

      _ ->
        {:error,
         {:invalid_arguments,
          "Promotion requires an approved independent diff or completion review for this task"}}
    end
  end

  defp ownership_attestations(
         %{"artifact_class" => "lasting_code"},
         stop,
         annotations,
         reviewed_by,
         ids
       ) do
    required =
      ~w(architecture_understandable complexity_proportional invariants_mechanical ownership_accepted longevity_justified)

    attestations = get_in(annotations || %{}, ["lasting_code_attestations"])

    cond do
      not is_map(attestations) ->
        {:error, {:invalid_arguments, "Lasting-code review requires ownership attestations"}}

      annotations["bounded_loop_stop_id"] != stop.id ->
        {:error,
         {:invalid_arguments, "Review attestations must reference the target stop checkpoint"}}

      not Enum.all?(required, &(attestations[&1] == true)) ->
        {:error, {:invalid_arguments, "All lasting-code ownership attestations must be true"}}

      true ->
        validate(stop, annotations, reviewed_by, ids)
    end
  end

  defp ownership_attestations(_contract, _stop, _annotations, _reviewed_by, _ids), do: :ok

  def validate(stop, annotations, reviewed_by, ids) do
    packet = stop.payload["promotion_packet"] || %{}
    worker = packet["worker_identity"] || %{}
    reviewers = annotations["reviewer_identities"]
    policy = packet["review_policy"] || %{}

    with true <-
           (is_list(reviewers) and length(reviewers) == 1) ||
             {:error,
              {:invalid_arguments,
               "Lasting-code review requires exactly one attributable reviewer identity"}},
         {:ok, reviewers} <- reviewer_identities(reviewers, ids),
         :ok <- attributable_reviewer(reviewers, reviewed_by),
         :ok <- distinct_reviewer_agents(worker, reviewers),
         :ok <- required_personas(policy, reviewers),
         :ok <- model_diversity(policy, worker, reviewers) do
      :ok
    end
  end

  defp attributable_reviewer([reviewer], reviewed_by) do
    if reviewer["agent_id"] == reviewed_by,
      do: :ok,
      else: {:error, {:invalid_arguments, "Reviewer identity must match reviewed_by"}}
  end

  defp reviewer_identities(reviewers, ids) do
    Enum.reduce_while(reviewers, {:ok, []}, fn reviewer, {:ok, acc} ->
      with true <-
             is_map(reviewer) ||
               {:error, {:invalid_arguments, "reviewer identities must be objects"}},
           {:ok, agent_id} <- required_string(reviewer, "agent_id"),
           {:ok, invocation_id} <- positive_integer(reviewer, "invocation_id"),
           {:ok, trusted} <- trusted_identity(ids, invocation_id, agent_id),
           {:ok, personas} <- string_list(reviewer, "personas") do
        identity = Map.put(trusted, "personas", personas)

        {:cont, {:ok, [identity | acc]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp distinct_reviewer_agents(worker, reviewers) do
    if Enum.any?(reviewers, &(&1["agent_id"] == worker["agent_id"])),
      do: {:error, {:invalid_arguments, "Reviewer agent must differ from the worker agent"}},
      else: :ok
  end

  defp required_personas(policy, reviewers) do
    covered = reviewers |> Enum.flat_map(& &1["personas"]) |> MapSet.new()
    missing = Enum.reject(policy["required_review_personas"] || [], &MapSet.member?(covered, &1))

    if missing == [],
      do: :ok,
      else:
        {:error,
         {:invalid_arguments, "Review is missing required personas: #{Enum.join(missing, ", ")}"}}
  end

  defp model_diversity(%{"review_risk" => "standard"}, _worker, _reviewers), do: :ok

  defp model_diversity(%{"review_risk" => "high"}, worker, reviewers) do
    if Enum.any?(reviewers, &(not same_model?(&1, worker))),
      do: :ok,
      else: {:error, {:invalid_arguments, "High-risk review requires a different model"}}
  end

  defp model_diversity(%{"review_risk" => "critical"}, worker, reviewers) do
    if Enum.all?(reviewers, &(not same_model?(&1, worker))),
      do: :ok,
      else: {:error, {:invalid_arguments, "Critical review forbids same-model reviewers"}}
  end

  defp model_diversity(_policy, _worker, _reviewers),
    do: {:error, {:invalid_arguments, "Promotion packet has no review policy"}}

  defp same_model?(reviewer, worker) do
    normalize_model(reviewer["canonical_model_id"]) ==
      normalize_model(worker["canonical_model_id"])
  end

  defp normalize_model(model), do: model |> String.trim() |> String.downcase()

  defp trusted_identity(ids, invocation_id, agent_id) do
    case Mission.get_invocation(invocation_id) do
      %{
        session_id: session_id,
        task_id: task_id,
        source: ^agent_id,
        provider: provider,
        model: model
      }
      when session_id == ids.session_id and task_id == ids.task_id and is_binary(provider) and
             provider != "" and is_binary(model) and model != "" ->
        canonical_model_id = derive_canonical_model_id(provider, model)

        {:ok,
         %{
           "agent_id" => agent_id,
           "invocation_id" => invocation_id,
           "provider" => provider,
           "model" => model,
           "canonical_model_id" => canonical_model_id
         }}

      _ ->
        {:error,
         {:invalid_arguments,
          "Model identity must reference an attributable invocation for this session and task"}}
    end
  end

  # Derives the canonical model identity from the invocation's first-class
  # schema fields (provider + model), never from free-form metadata. These
  # fields are set by the CK runtime when recording invocations, not by the
  # caller.
  defp derive_canonical_model_id(provider, model) do
    (normalize_model(provider) <> "/" <> normalize_model(model))
    |> String.replace(~r/[^a-z0-9._\/-]/, "")
  end

  defp positive_integer(arguments, key) do
    case Map.get(arguments, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      value when is_binary(value) -> parse_positive_integer(value, key)
      _ -> {:error, {:invalid_arguments, "#{key} must be a positive integer"}}
    end
  end

  defp parse_positive_integer(value, key) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, {:invalid_arguments, "#{key} must be a positive integer"}}
    end
  end

  defp required_string(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} is required"}}
    end
  end

  defp required_map(arguments, key) do
    case Map.get(arguments, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "#{key} must be an object"}}
    end
  end

  defp string_list(arguments, key) do
    case Map.get(arguments, key) do
      values when is_list(values) and values != [] ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")),
          do: {:ok, Enum.uniq(values)},
          else: {:error, {:invalid_arguments, "#{key} must contain non-empty strings"}}

      _ ->
        {:error, {:invalid_arguments, "#{key} must be a non-empty array"}}
    end
  end
end
