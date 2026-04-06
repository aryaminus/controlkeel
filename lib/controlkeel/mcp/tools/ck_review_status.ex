defmodule ControlKeel.MCP.Tools.CkReviewStatus do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ReviewBridge

  def call(arguments) when is_map(arguments) do
    with {:ok, review} <- resolve_review(arguments) do
      plan_refinement = get_in(review.metadata || %{}, ["plan_refinement"]) || %{}

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
         "plan_quality" => plan_refinement["quality"],
         "grill_questions" => get_in(plan_refinement, ["quality", "grill_questions"]) || [],
         "agent_feedback" => ReviewBridge.agent_feedback(review),
         "responded_at" => review.responded_at,
         "browser_url" => ControlKeelWeb.Endpoint.url() <> "/reviews/#{review.id}"
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp resolve_review(arguments) do
    cond do
      Map.has_key?(arguments, "review_id") ->
        with {:ok, review_id} <- normalize_integer(Map.get(arguments, "review_id"), "review_id"),
             %{} = review <- Mission.get_review_with_context(review_id) do
          {:ok, review}
        else
          nil -> {:error, {:invalid_arguments, "Review not found"}}
          {:error, reason} -> {:error, reason}
        end

      Map.has_key?(arguments, "task_id") ->
        with {:ok, task_id} <- normalize_integer(Map.get(arguments, "task_id"), "task_id"),
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

  defp normalize_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}
    end
  end

  defp normalize_integer(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}
end
