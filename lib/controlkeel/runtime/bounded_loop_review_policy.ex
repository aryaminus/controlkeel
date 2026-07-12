defmodule ControlKeel.Runtime.BoundedLoopReviewPolicy do
  @moduledoc false

  alias ControlKeel.Mission

  def worker_identity(arguments) do
    with {:ok, value} <- required_map(arguments, "worker_identity"),
         {:ok, agent_id} <- required_string(value, "agent_id"),
         {:ok, provider} <- required_string(value, "provider"),
         {:ok, model} <- required_string(value, "model"),
         {:ok, canonical_model_id} <- required_string(value, "canonical_model_id"),
         :ok <- canonical_model_id(provider, canonical_model_id) do
      {:ok,
       %{
         "agent_id" => agent_id,
         "provider" => provider,
         "model" => model,
         "canonical_model_id" => canonical_model_id
       }}
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
             :ok <- ownership_attestations(contract.payload, stop, annotations, reviewed_by) do
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
         reviewed_by
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
        validate(stop, annotations, reviewed_by)
    end
  end

  defp ownership_attestations(_contract, _stop, _annotations, _reviewed_by), do: :ok

  def validate(stop, annotations, reviewed_by) do
    packet = stop.payload["promotion_packet"] || %{}
    worker = packet["worker_identity"] || %{}
    reviewers = annotations["reviewer_identities"]
    policy = packet["review_policy"] || %{}

    with true <-
           (is_list(reviewers) and length(reviewers) == 1) ||
             {:error,
              {:invalid_arguments,
               "Lasting-code review requires exactly one attributable reviewer identity"}},
         {:ok, reviewers} <- reviewer_identities(reviewers),
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

  defp reviewer_identities(reviewers) do
    Enum.reduce_while(reviewers, {:ok, []}, fn reviewer, {:ok, acc} ->
      with true <-
             is_map(reviewer) ||
               {:error, {:invalid_arguments, "reviewer identities must be objects"}},
           {:ok, agent_id} <- required_string(reviewer, "agent_id"),
           {:ok, provider} <- required_string(reviewer, "provider"),
           {:ok, model} <- required_string(reviewer, "model"),
           {:ok, canonical_model_id} <- required_string(reviewer, "canonical_model_id"),
           :ok <- canonical_model_id(provider, canonical_model_id),
           {:ok, personas} <- string_list(reviewer, "personas") do
        identity = %{
          "agent_id" => agent_id,
          "provider" => provider,
          "model" => model,
          "canonical_model_id" => canonical_model_id,
          "personas" => personas
        }

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

  defp canonical_model_id(provider, model_id) do
    normalized_provider = provider |> String.trim() |> String.downcase()

    if model_id == String.downcase(String.trim(model_id)) and
         String.starts_with?(model_id, normalized_provider <> "/") and
         model_id != normalized_provider <> "/" do
      :ok
    else
      {:error,
       {:invalid_arguments,
        "canonical_model_id must be a lowercase provider/model identifier matching provider"}}
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
