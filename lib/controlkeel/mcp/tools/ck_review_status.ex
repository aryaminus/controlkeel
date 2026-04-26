defmodule ControlKeel.MCP.Tools.CkReviewStatus do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.ReviewBridge

  @wait_timeout_seconds 1

  def call(arguments) when is_map(arguments) do
    with {:ok, review} <- resolve_review(arguments) do
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
         "agent_feedback" => review_agent_feedback(review),
         "responded_at" => review.responded_at,
         "browser_url" => review_browser_url(review)
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp resolve_review(arguments) do
    cond do
      Map.has_key?(arguments, "review_id") ->
        with {:ok, review_id} <- normalize_integer(Map.get(arguments, "review_id"), "review_id") do
          resolve_review_by_id(review_id)
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
    executable = controlkeel_bin()

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

    try_fallback_variants(executable, args, fallback_variants())
  end

  defp try_fallback_variants(_executable, _args, []), do: {:error, :fallback_failed}

  defp try_fallback_variants(executable, args, [variant | rest]) do
    case run_fallback_wait(executable, args, variant) do
      {:ok, payload} -> {:ok, payload}
      {:error, _reason} -> try_fallback_variants(executable, args, rest)
    end
  end

  defp fallback_variants do
    root = resolved_project_root()

    [
      [cd: root, stderr_to_stdout: true],
      [stderr_to_stdout: true],
      [cd: root, stderr_to_stdout: true, env: fallback_env("prod")],
      [stderr_to_stdout: true, env: fallback_env("prod")],
      [cd: root, stderr_to_stdout: true, env: fallback_env("dev")],
      [stderr_to_stdout: true, env: fallback_env("dev")]
    ]
  end

  defp fallback_env(mix_env) do
    System.get_env()
    |> Map.put("MIX_ENV", mix_env)
    |> Enum.into([])
  end

  defp run_fallback_wait(executable, args, opts) do
    case System.cmd(executable, args, opts) do
      {output, _status} ->
        case extract_json_object(output) do
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
        id: map_integer(review_payload, "id", review_id),
        title: map_string(review_payload, "title"),
        review_type: map_string(review_payload, "review_type"),
        status: map_string(review_payload, "status", "pending"),
        session_id: map_integer_or_nil(review_payload, "session_id"),
        task_id: map_integer_or_nil(review_payload, "task_id"),
        feedback_notes: map_string_or_nil(review_payload, "feedback_notes"),
        annotations: Map.get(review_payload, "annotations"),
        metadata: %{},
        responded_at: nil,
        fallback_payload: payload
      }

    {:ok, review}
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

  defp review_agent_feedback(review), do: ReviewBridge.agent_feedback(review)

  defp review_browser_url(%{fallback_payload: payload}) do
    Map.get(payload, "browser_url") || safe_review_url(Map.get(payload, "review", %{})["id"])
  end

  defp review_browser_url(review), do: safe_review_url(review.id)

  defp review_metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp review_metadata(_review), do: %{}

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
