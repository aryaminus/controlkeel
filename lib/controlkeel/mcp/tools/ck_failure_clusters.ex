defmodule ControlKeel.MCP.Tools.CkFailureClusters do
  @moduledoc false

  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 5),
         {:ok, same_domain_only} <- optional_boolean(arguments, "same_domain_only", true) do
      Mission.failure_mode_clusters(session_id,
        session_limit: session_limit,
        same_domain_only: same_domain_only
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

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value -> normalize_integer(value, key)
    end
  end

  defp optional_boolean(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value when is_boolean(value) -> {:ok, value}
      nil -> {:ok, default}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a boolean if provided"}}
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
