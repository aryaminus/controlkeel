defmodule ControlKeel.MCP.Tools.CkReviewFeedback do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.MCP.Tools.ReviewHelpers

  def call(arguments) when is_map(arguments) do
    with {:ok, review_id} <- Arguments.required_integer(arguments, "review_id"),
         {:ok, decision} <- required_decision(arguments),
         {:ok, review} <- fetch_review(review_id),
         :ok <- scope_review_to_session(review, arguments),
         {:ok, updated} <- respond_review(review, decision, arguments) do
      {:ok,
       %{
         "review_id" => updated.id,
         "status" => updated.status,
         "feedback_notes" => updated.feedback_notes,
         "agent_feedback" => ReviewHelpers.review_agent_feedback(updated),
         "responded_at" => updated.responded_at,
         "browser_url" => ReviewHelpers.review_browser_url(updated)
       }}
    else
      {:error, {:invalid_arguments, reason}} ->
        {:error, {:invalid_arguments, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp fetch_review(review_id) do
    case Mission.get_review(review_id) do
      nil -> fallback_review(review_id)
      review -> {:ok, review}
    end
  end

  # An explicit session_id scopes the decision: cross-session approve/deny
  # is denied. Absent session_id preserves old behavior. Fallback (CLI)
  # reviews carry no session, so they fail closed when scoped.
  defp scope_review_to_session(%{fallback_review_id: _}, arguments) do
    case Map.get(arguments, "session_id") do
      nil -> :ok
      _ -> {:error, {:invalid_arguments, "Review does not belong to the given session"}}
    end
  end

  defp scope_review_to_session(review, arguments) do
    case Map.get(arguments, "session_id") do
      nil ->
        :ok

      raw ->
        with {:ok, session_id} <- Arguments.normalize_integer(raw, "session_id") do
          if Map.get(review, :session_id) == session_id do
            :ok
          else
            {:error, {:invalid_arguments, "Review does not belong to the given session"}}
          end
        end
    end
  end

  defp respond_review(%{fallback_review_id: review_id}, decision, arguments) do
    respond_review_via_cli(review_id, decision, arguments)
  end

  defp respond_review(review, _decision, arguments) do
    Mission.respond_review(review, %{
      "decision" => Map.get(arguments, "decision"),
      "feedback_notes" => Map.get(arguments, "feedback_notes"),
      "annotations" => Map.get(arguments, "annotations"),
      "reviewed_by" => Map.get(arguments, "reviewed_by", "mcp")
    })
  end

  defp fallback_review(review_id) do
    {:ok,
     %{
       id: review_id,
       fallback_review_id: review_id
     }}
  end

  defp respond_review_via_cli(review_id, decision, arguments) do
    executable = ReviewHelpers.controlkeel_bin()
    args = cli_feedback_args(review_id, decision, arguments)

    try_feedback_variants(executable, args, review_id, ReviewHelpers.fallback_variants())
  end

  defp try_feedback_variants(_executable, _args, _review_id, []),
    do: {:error, {:invalid_arguments, "Review not found"}}

  defp try_feedback_variants(executable, args, review_id, [variant | rest]) do
    case run_fallback_response(executable, args, review_id, variant) do
      {:ok, payload} -> {:ok, payload}
      {:error, _reason} -> try_feedback_variants(executable, args, review_id, rest)
    end
  end

  defp run_fallback_response(executable, args, review_id, opts) do
    case System.cmd(executable, args, opts) do
      {output, _status} ->
        with {:ok, payload} <- ReviewHelpers.extract_json_object(output),
             {:ok, review} <- extract_review_from_payload(payload, review_id) do
          {:ok,
           %{
             id: review.id,
             status: review.status,
             feedback_notes: review.feedback_notes,
             responded_at: nil,
             fallback_payload: payload
           }}
        else
          _ -> {:error, {:invalid_arguments, "Review not found"}}
        end
    end
  rescue
    _ -> {:error, {:invalid_arguments, "Review not found"}}
  end

  defp cli_feedback_args(review_id, decision, arguments) do
    base = [
      "review",
      "plan",
      "respond",
      Integer.to_string(review_id),
      "--decision",
      decision,
      "--json"
    ]

    base
    |> maybe_append_arg("--feedback-notes", Map.get(arguments, "feedback_notes"))
    |> maybe_append_arg("--reviewed-by", Map.get(arguments, "reviewed_by"))
    |> maybe_append_json("--annotations", Map.get(arguments, "annotations"))
  end

  defp maybe_append_arg(args, _flag, nil), do: args
  defp maybe_append_arg(args, _flag, value) when value == "", do: args
  defp maybe_append_arg(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_append_json(args, _flag, nil), do: args

  defp maybe_append_json(args, flag, value) when is_map(value) or is_list(value) do
    args ++ [flag, Jason.encode!(value)]
  end

  defp maybe_append_json(args, flag, value) when is_binary(value) and value != "" do
    args ++ [flag, value]
  end

  defp maybe_append_json(args, _flag, _value), do: args

  defp extract_review_from_payload(%{"review" => review_payload}, review_id)
       when is_map(review_payload) do
    {:ok,
     %{
       id: ReviewHelpers.map_integer(review_payload, "id", review_id),
       status: ReviewHelpers.map_string(review_payload, "status", "pending"),
       feedback_notes: ReviewHelpers.map_string_or_nil(review_payload, "feedback_notes")
     }}
  end

  defp extract_review_from_payload(_, _review_id), do: {:error, :missing_review}

  defp required_decision(arguments) do
    case Map.get(arguments, "decision") do
      value when value in ["approved", "denied"] -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`decision` must be approved or denied"}}
    end
  end
end
