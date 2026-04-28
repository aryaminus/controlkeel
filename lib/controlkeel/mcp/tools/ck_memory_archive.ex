defmodule ControlKeel.MCP.Tools.CkMemoryArchive do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    with {:ok, memory_id} <- Arguments.required_integer(arguments, "memory_id"),
         {:ok, session} <- Arguments.fetch_session(arguments),
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
end
