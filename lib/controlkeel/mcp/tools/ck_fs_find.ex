defmodule ControlKeel.MCP.Tools.CkFsFind do
  @moduledoc false

  alias ControlKeel.VirtualWorkspace

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, query} <- required_binary(arguments, "query"),
         {:ok, limit} <- optional_integer(arguments, "limit", 50) do
      VirtualWorkspace.find(session_id, query,
        path: Map.get(arguments, "path", "."),
        limit: limit
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

  defp required_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:invalid_arguments, "`#{key}` is required"}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` is required"}}
    end
  end

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
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
