defmodule ControlKeel.MCP.Tools.CkMemoryRecord do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, memory} <- required_binary(arguments, "memory"),
         {:ok, session} <- fetch_session(session_id),
         :ok <- validate_task(task_id, session.id),
         {:ok, record} <- create_record(arguments, session, task_id, memory) do
      {:ok,
       %{
         "recorded" => true,
         "memory_id" => record.id,
         "record_type" => record.record_type,
         "title" => record.title,
         "session_id" => record.session_id,
         "task_id" => record.task_id
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp create_record(arguments, session, task_id, memory) do
    metadata =
      Map.get(arguments, "metadata", %{})
      |> ensure_map()
      |> Map.put_new("source", "mcp")

    Memory.record(%{
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: task_id,
      record_type: Map.get(arguments, "record_type", "decision"),
      title: title_for(arguments, memory),
      summary: summary_for(arguments, memory),
      body: body_for(arguments, memory),
      tags: normalize_tags(Map.get(arguments, "tags")),
      source_type: Map.get(arguments, "source_type", "generated"),
      source_id: Map.get(arguments, "source_id"),
      metadata: metadata
    })
  end

  defp title_for(arguments, memory) do
    case Map.get(arguments, "title") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> memory |> String.trim() |> String.slice(0, 80)
    end
  end

  defp summary_for(arguments, memory) do
    case Map.get(arguments, "summary") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> memory |> String.trim() |> String.slice(0, 160)
    end
  end

  defp body_for(arguments, memory) do
    case Map.get(arguments, "body") do
      value when is_binary(value) and value != "" -> value
      _ -> memory
    end
  end

  defp normalize_tags(tags) when is_list(tags), do: Enum.map(tags, &to_string/1)

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(_tags), do: []

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

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}
end
