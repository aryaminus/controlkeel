defmodule ControlKeel.MCP.Tools.CkReviewFeedback do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ReviewBridge

  def call(arguments) when is_map(arguments) do
    with {:ok, review_id} <- required_integer(arguments, "review_id"),
         {:ok, decision} <- required_decision(arguments),
         {:ok, review} <- fetch_review(review_id),
         {:ok, updated} <- respond_review(review, decision, arguments) do
      {:ok,
       %{
         "review_id" => updated.id,
         "status" => updated.status,
         "feedback_notes" => updated.feedback_notes,
         "agent_feedback" => review_agent_feedback(updated),
         "responded_at" => updated.responded_at,
         "browser_url" => review_browser_url(updated)
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
    executable = controlkeel_bin()
    args = cli_feedback_args(review_id, decision, arguments)

    with {:error, _reason} <-
           run_fallback_response(executable, args, review_id,
             cd: resolved_project_root(),
             stderr_to_stdout: true
           ) do
      run_fallback_response(executable, args, review_id, stderr_to_stdout: true)
    end
  end

  defp run_fallback_response(executable, args, review_id, opts) do
    case System.cmd(executable, args, opts) do
      {output, _status} ->
        with {:ok, payload} <- extract_json_object(output),
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
       id: map_integer(review_payload, "id", review_id),
       status: map_string(review_payload, "status", "pending"),
       feedback_notes: map_string_or_nil(review_payload, "feedback_notes")
     }}
  end

  defp extract_review_from_payload(_, _review_id), do: {:error, :missing_review}

  defp map_string(map, key, default \\ nil) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> default
    end
  end

  defp map_string_or_nil(map, key) do
    case Map.get(map, key) do
      nil -> nil
      value -> map_string(%{key => value}, key)
    end
  end

  defp map_integer(map, key, default) do
    case map_integer_or_nil(map, key) do
      nil -> default
      value -> value
    end
  end

  defp map_integer_or_nil(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp review_agent_feedback(%{fallback_payload: payload}) do
    payload["agent_feedback"]
  end

  defp review_agent_feedback(updated), do: ReviewBridge.agent_feedback(updated)

  defp review_browser_url(%{fallback_payload: payload}) do
    Map.get(payload, "browser_url") || safe_review_url(Map.get(payload, "review", %{})["id"])
  end

  defp review_browser_url(updated), do: safe_review_url(updated.id)

  defp safe_review_url(nil), do: nil

  defp safe_review_url(review_id) do
    try do
      ControlKeelWeb.Endpoint.url() <> "/reviews/#{review_id}"
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp controlkeel_bin do
    case System.get_env("CONTROLKEEL_BIN") do
      value when is_binary(value) and value != "" -> value
      _ -> System.find_executable("controlkeel") || "controlkeel"
    end
  end

  defp resolved_project_root do
    case System.get_env("CONTROLKEEL_PROJECT_ROOT") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> fallback_project_root()
    end
  end

  defp fallback_project_root do
    case System.get_env("CK_PROJECT_ROOT") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> File.cwd!()
    end
  end

  defp extract_json_object(output) when is_binary(output) do
    indices = :binary.matches(output, "{")

    Enum.reduce_while(indices, {:error, :json_not_found}, fn {offset, _length}, _acc ->
      slice = binary_part(output, offset, byte_size(output) - offset)

      with {:ok, candidate} <- take_balanced_json_object(slice),
           {:ok, decoded} <- Jason.decode(candidate) do
        {:halt, {:ok, decoded}}
      else
        _ -> {:cont, {:error, :json_not_found}}
      end
    end)
  end

  defp extract_json_object(_output), do: {:error, :json_not_found}

  defp take_balanced_json_object("{" <> _ = input) do
    bytes = :binary.bin_to_list(input)

    case scan_json_object(bytes, 0, false, false, 0) do
      {:ok, end_index} -> {:ok, binary_part(input, 0, end_index + 1)}
      :error -> {:error, :json_not_found}
    end
  end

  defp take_balanced_json_object(_input), do: {:error, :json_not_found}

  defp scan_json_object([], _depth, _in_string, _escaped, _index), do: :error

  defp scan_json_object([char | rest], depth, in_string, escaped, index) do
    cond do
      in_string and escaped ->
        scan_json_object(rest, depth, true, false, index + 1)

      in_string and char == ?\\ ->
        scan_json_object(rest, depth, true, true, index + 1)

      in_string and char == ?\" ->
        scan_json_object(rest, depth, false, false, index + 1)

      in_string ->
        scan_json_object(rest, depth, true, false, index + 1)

      char == ?\" ->
        scan_json_object(rest, depth, true, false, index + 1)

      char == ?{ ->
        scan_json_object(rest, depth + 1, false, false, index + 1)

      char == ?} and depth == 1 ->
        {:ok, index}

      char == ?} and depth > 1 ->
        scan_json_object(rest, depth - 1, false, false, index + 1)

      true ->
        scan_json_object(rest, depth, false, false, index + 1)
    end
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  defp required_decision(arguments) do
    case Map.get(arguments, "decision") do
      value when value in ["approved", "denied"] -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`decision` must be approved or denied"}}
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
