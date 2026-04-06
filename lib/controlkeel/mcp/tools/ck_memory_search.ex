defmodule ControlKeel.MCP.Tools.CkMemorySearch do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.Mission

  @max_top_k 20

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, query} <- required_binary(arguments, "query"),
         {:ok, top_k} <- optional_top_k(arguments),
         {:ok, session} <- fetch_session(session_id),
         :ok <- validate_task(task_id, session.id) do
      result =
        Memory.search(query,
          workspace_id: session.workspace_id,
          session_id: session.id,
          task_id: task_id,
          record_type: Map.get(arguments, "record_type"),
          top_k: top_k
        )

      {:ok,
       %{
         "query" => result.query,
         "count" => result.total_count,
         "semantic_available" => result.semantic_available,
         "records" => Enum.map(result.entries, &memory_summary/1)
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp fetch_session(session_id) do
    case Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp validate_task(nil, _session_id), do: :ok

  defp validate_task(task_id, session_id) do
    case Mission.get_task(task_id) do
      %{session_id: ^session_id} -> :ok
      nil -> {:error, {:invalid_arguments, "`task_id` was not found"}}
      _other -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  defp optional_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp normalize_integer(_value, key),
    do: {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}

  defp required_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> {:error, {:invalid_arguments, "`#{key}` is required"}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` is required"}}
    end
  end

  defp optional_top_k(arguments) do
    case Map.get(arguments, "top_k", 5) do
      value when is_integer(value) and value > 0 and value <= @max_top_k -> {:ok, value}
      value when is_binary(value) -> parse_top_k(value)
      _other -> {:error, {:invalid_arguments, "`top_k` must be between 1 and #{@max_top_k}"}}
    end
  end

  defp parse_top_k(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 and parsed <= @max_top_k -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`top_k` must be between 1 and #{@max_top_k}"}}
    end
  end

  defp memory_summary(entry) do
    %{
      "id" => entry.id,
      "record_type" => entry.record_type,
      "title" => entry.title,
      "summary" => entry.summary,
      "tags" => entry.tags,
      "source_type" => entry.source_type,
      "session_id" => entry.session_id,
      "task_id" => entry.task_id,
      "inserted_at" => entry.inserted_at,
      "score" => entry.score
    }
  end
end
