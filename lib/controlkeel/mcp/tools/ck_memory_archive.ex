defmodule ControlKeel.MCP.Tools.CkMemoryArchive do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, memory_id} <- required_integer(arguments, "memory_id"),
         {:ok, session} <- fetch_session(session_id),
         {:ok, record} <- fetch_record(memory_id, session.id),
         {:ok, archived} <- Memory.archive_record(record) do
      {:ok,
       %{
         "archived" => true,
         "memory_id" => archived.id,
         "session_id" => archived.session_id,
         "archived_at" => archived.archived_at
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

  defp fetch_record(memory_id, session_id) do
    case Memory.get_record(memory_id) do
      %{session_id: ^session_id} = record ->
        {:ok, record}

      nil ->
        {:error, {:invalid_arguments, "Memory record not found"}}

      _other ->
        {:error, {:invalid_arguments, "`memory_id` must belong to the current session"}}
    end
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
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
end
