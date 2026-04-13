defmodule ControlKeel.MCP.Tools.CkCostOptimizer do
  @moduledoc false

  alias ControlKeel.Budget.CostOptimizer

  @allowed_modes ~w(suggest compare)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      case normalized["mode"] do
        "suggest" ->
          opts = [
            spending: normalized["spending"] || [],
            top_provider: normalized["top_provider"],
            top_model: normalized["top_model"]
          ]

          case CostOptimizer.suggest(normalized["session_id"], opts) do
            {:ok, suggestions} when is_list(suggestions) ->
              {:ok, %{"mode" => "suggest", "suggestions" => suggestions}}

            other ->
              other
          end

        "compare" ->
          opts = [
            estimated_tokens: normalized["estimated_tokens"] || 10_000
          ]

          case CostOptimizer.compare_agents(
                 normalized["task_description"] || "Unknown task",
                 opts
               ) do
            {:ok, comparisons} when is_list(comparisons) ->
              {:ok, %{"mode" => "compare", "comparisons" => comparisons}}

            other ->
              other
          end
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, mode} <- mode(arguments) do
      {:ok,
       %{
         "mode" => mode,
         "session_id" => Map.get(arguments, "session_id"),
         "spending" => Map.get(arguments, "spending", []),
         "top_provider" => Map.get(arguments, "top_provider"),
         "top_model" => Map.get(arguments, "top_model"),
         "task_description" => Map.get(arguments, "task_description"),
         "estimated_tokens" => Map.get(arguments, "estimated_tokens", 10_000)
       }}
    end
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "suggest") do
      value when value in @allowed_modes -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`mode` must be `suggest` or `compare`"}}
    end
  end
end
