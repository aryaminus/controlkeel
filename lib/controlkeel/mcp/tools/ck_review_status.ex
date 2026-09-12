defmodule ControlKeel.MCP.Tools.CkReviewStatus do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.MCP.Tools.ReviewHelpers

  @wait_timeout_seconds 1

  def call(arguments) when is_map(arguments) do
    with {:ok, review} <- resolve_review(arguments),
         :ok <- scope_review_to_session(review, arguments) do
      plan_refinement = get_in(review_metadata(review), ["plan_refinement"]) || %{}

      {:ok,
       %{
         "review_id" => review.id,
         "title" => review.title,
         "review_type" => review.review_type,
         "status" => review.status,
         "session_id" => review.session_id,
         "task_id" => review.task_id,
         "feedback_notes" => review.feedback_notes,
         "annotations" => review.annotations,
         "plan_phase" => plan_refinement["phase"],
         "plan_refinement" => plan_refinement,
         "plan_quality" => plan_refinement["quality"],
         "grill_questions" => get_in(plan_refinement, ["quality", "grill_questions"]) || [],
         "agent_feedback" => ReviewHelpers.review_agent_feedback(review),
         "responded_at" => review.responded_at,
         "browser_url" => ReviewHelpers.review_browser_url(review),
         "review_url" => ReviewHelpers.review_browser_url(review),
         "approval_instructions" =>
           ReviewHelpers.approval_instructions(review, ReviewHelpers.review_browser_url(review)),
         "review_roles" => ReviewHelpers.review_roles(review.review_type, plan_refinement)
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp resolve_review(arguments) do
    cond do
      Map.has_key?(arguments, "review_id") ->
        with {:ok, review_id} <-
               Arguments.normalize_integer(Map.get(arguments, "review_id"), "review_id") do
          resolve_review_by_id(review_id)
        end

      Map.has_key?(arguments, "task_id") ->
        with {:ok, task_id} <-
               Arguments.normalize_integer(Map.get(arguments, "task_id"), "task_id"),
             :ok <- scope_task_to_session(task_id, arguments),
             review when not is_nil(review) <-
               Mission.latest_review_for_task(task_id, Map.get(arguments, "review_type", "plan")) do
          {:ok, Mission.get_review_with_context(review.id)}
        else
          nil -> {:error, {:invalid_arguments, "No review found for task"}}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:error, {:invalid_arguments, "`review_id` or `task_id` is required"}}
    end
  end

  # An explicit session_id scopes the lookup: cross-session reads are denied
  # instead of silently served. Absent session_id preserves old behavior.
  defp scope_review_to_session(review, arguments) do
    case Map.get(arguments, "session_id") do
      nil ->
        :ok

      raw ->
        with {:ok, session_id} <- Arguments.normalize_integer(raw, "session_id") do
          if review.session_id == session_id do
            :ok
          else
            {:error, {:invalid_arguments, "Review does not belong to the given session"}}
          end
        end
    end
  end

  defp scope_task_to_session(task_id, arguments) do
    case Map.get(arguments, "session_id") do
      nil ->
        :ok

      raw ->
        with {:ok, session_id} <- Arguments.normalize_integer(raw, "session_id") do
          case Mission.get_task(task_id) do
            %{session_id: ^session_id} -> :ok
            nil -> {:error, {:invalid_arguments, "No review found for task"}}
            _ -> {:error, {:invalid_arguments, "Task does not belong to the given session"}}
          end
        end
    end
  end

  defp resolve_review_by_id(review_id) do
    case Mission.get_review_with_context(review_id) do
      %{} = review ->
        {:ok, review}

      nil ->
        with {:ok, payload} <- fallback_review_status(review_id),
             {:ok, review} <- extract_review_from_payload(payload, review_id) do
          {:ok, review}
        else
          _ -> {:error, {:invalid_arguments, "Review not found"}}
        end
    end
  end

  defp fallback_review_status(review_id) do
    executable = ReviewHelpers.controlkeel_bin()

    args = [
      "review",
      "plan",
      "wait",
      "--id",
      Integer.to_string(review_id),
      "--timeout",
      Integer.to_string(@wait_timeout_seconds),
      "--json"
    ]

    try_fallback_variants(executable, args, ReviewHelpers.fallback_variants())
  end

  defp try_fallback_variants(_executable, _args, []), do: {:error, :fallback_failed}

  defp try_fallback_variants(executable, args, [variant | rest]) do
    case run_fallback_wait(executable, args, variant) do
      {:ok, payload} -> {:ok, payload}
      {:error, _reason} -> try_fallback_variants(executable, args, rest)
    end
  end

  defp run_fallback_wait(executable, args, opts) do
    case System.cmd(executable, args, opts) do
      {output, _status} ->
        case ReviewHelpers.extract_json_object(output) do
          {:ok, payload} when is_map(payload) -> {:ok, payload}
          _ -> {:error, :invalid_fallback_payload}
        end
    end
  rescue
    _ -> {:error, :fallback_failed}
  end

  defp extract_review_from_payload(%{"review" => review_payload} = payload, review_id)
       when is_map(review_payload) do
    review =
      %{
        id: ReviewHelpers.map_integer(review_payload, "id", review_id),
        title: ReviewHelpers.map_string(review_payload, "title"),
        review_type: ReviewHelpers.map_string(review_payload, "review_type"),
        status: ReviewHelpers.map_string(review_payload, "status", "pending"),
        session_id: ReviewHelpers.map_integer_or_nil(review_payload, "session_id"),
        task_id: ReviewHelpers.map_integer_or_nil(review_payload, "task_id"),
        feedback_notes: ReviewHelpers.map_string_or_nil(review_payload, "feedback_notes"),
        annotations: Map.get(review_payload, "annotations"),
        metadata: %{},
        responded_at: nil,
        fallback_payload: payload
      }

    {:ok, review}
  end

  defp extract_review_from_payload(_, _review_id), do: {:error, :missing_review}

  defp review_metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp review_metadata(_review), do: %{}
end
