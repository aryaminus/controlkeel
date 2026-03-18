defmodule ControlKeel.MCP.Tools.CkBudget do
  @moduledoc false

  alias ControlKeel.Budget

  @allowed_modes ~w(estimate commit)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      case normalized["mode"] do
        "estimate" -> Budget.estimate(normalized)
        "commit" -> Budget.commit(normalized)
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, mode} <- mode(arguments),
         {:ok, estimated_cost_cents} <-
           optional_non_negative_integer(arguments, "estimated_cost_cents"),
         {:ok, input_tokens} <- optional_non_negative_integer(arguments, "input_tokens"),
         {:ok, cached_input_tokens} <-
           optional_non_negative_integer(arguments, "cached_input_tokens"),
         {:ok, output_tokens} <- optional_non_negative_integer(arguments, "output_tokens") do
      {:ok,
       %{
         "session_id" => session_id,
         "task_id" => task_id,
         "mode" => mode,
         "estimated_cost_cents" => estimated_cost_cents,
         "provider" => optional_binary(arguments, "provider"),
         "model" => optional_binary(arguments, "model"),
         "input_tokens" => input_tokens || 0,
         "cached_input_tokens" => cached_input_tokens || 0,
         "output_tokens" => output_tokens || 0,
         "source" => optional_binary(arguments, "source") || "mcp",
         "tool" => optional_binary(arguments, "tool") || "ck_budget",
         "metadata" => Map.get(arguments, "metadata", %{})
       }}
    end
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "estimate") do
      value when value in @allowed_modes -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`mode` must be `estimate` or `commit`"}}
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

  defp optional_non_negative_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp normalize_integer(value, _key) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a non-negative integer if provided"}}
    end
  end

  defp normalize_integer(_value, key) do
    {:error, {:invalid_arguments, "`#{key}` must be a non-negative integer if provided"}}
  end

  defp optional_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end
end
