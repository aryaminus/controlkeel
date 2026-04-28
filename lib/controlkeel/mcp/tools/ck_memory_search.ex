defmodule ControlKeel.MCP.Tools.CkMemorySearch do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.MCP.Arguments

  @max_top_k 20

  def call(arguments) when is_map(arguments) do
    with {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, query} <- required_binary(arguments, "query"),
         {:ok, top_k} <- Arguments.optional_top_k(arguments, default: 5, max: @max_top_k),
         {:ok, session} <- Arguments.fetch_session(arguments),
         :ok <- Arguments.validate_task(task_id, session.id) do
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
