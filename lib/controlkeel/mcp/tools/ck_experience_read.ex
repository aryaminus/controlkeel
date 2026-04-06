defmodule ControlKeel.MCP.Tools.CkExperienceRead do
  @moduledoc false

  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, source_session_id} <- optional_integer(arguments, "source_session_id", session_id),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, artifact_type} <- required_string(arguments, "artifact_type") do
      Mission.experience_history_read(session_id,
        source_session_id: source_session_id,
        task_id: task_id,
        artifact_type: artifact_type
      )
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  defp optional_integer(arguments, key, default \\ nil) do
    case Map.get(arguments, key, default) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp required_string(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`#{key}` is required"}}
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
