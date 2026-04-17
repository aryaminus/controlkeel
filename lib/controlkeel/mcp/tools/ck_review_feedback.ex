defmodule ControlKeel.MCP.Tools.CkReviewFeedback do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ReviewBridge

  def call(arguments) when is_map(arguments) do
    with {:ok, review_id} <- required_integer(arguments, "review_id"),
         {:ok, review} <- fetch_review(review_id),
         {:ok, updated} <-
           Mission.respond_review(review, %{
             "decision" => Map.get(arguments, "decision"),
             "feedback_notes" => Map.get(arguments, "feedback_notes"),
             "annotations" => Map.get(arguments, "annotations"),
             "reviewed_by" => Map.get(arguments, "reviewed_by", "mcp")
           }) do
      {:ok,
       %{
         "review_id" => updated.id,
         "status" => updated.status,
         "feedback_notes" => updated.feedback_notes,
         "agent_feedback" => ReviewBridge.agent_feedback(updated),
         "responded_at" => updated.responded_at,
         "browser_url" => safe_review_url(updated.id)
       }}
    else
      {:error, {:invalid_arguments, reason}} ->
        {:error, {:invalid_arguments, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp safe_review_url(review_id) do
    try do
      ControlKeelWeb.Endpoint.url() <> "/reviews/#{review_id}"
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp fetch_review(review_id) do
    case Mission.get_review(review_id) do
      nil -> {:error, {:invalid_arguments, "Review not found"}}
      review -> {:ok, review}
    end
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
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
