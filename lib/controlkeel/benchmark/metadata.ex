defmodule ControlKeel.Benchmark.Metadata do
  @moduledoc false

  def normalize_scenario_metadata(payload) when is_map(payload) do
    metadata =
      payload
      |> Map.get("metadata", %{})
      |> stringify_keys()

    Map.merge(
      %{
        "task_type" => infer_task_type(payload, metadata),
        "risk_tier" => infer_risk_tier(payload, metadata),
        "domain_pack" => infer_domain_pack(payload, metadata),
        "budget_tier" => infer_budget_tier(payload, metadata)
      },
      metadata
    )
  end

  def normalize_scenario_metadata(_payload), do: default_metadata()

  def suite_internal?(%{metadata: metadata}) when is_map(metadata) do
    internal_metadata?(metadata)
  end

  def suite_internal?(payload) when is_map(payload) do
    internal_metadata?(Map.get(payload, "metadata", %{}))
  end

  def suite_internal?(_payload), do: false

  def default_metadata do
    %{
      "task_type" => "backend",
      "risk_tier" => "medium",
      "domain_pack" => "software",
      "budget_tier" => "medium"
    }
  end

  defp infer_task_type(payload, metadata) do
    metadata["task_type"] ||
      cond do
        category(payload) in ["privacy", "compliance"] -> "review"
        path(payload) =~ ~r/\.(css|tsx|jsx|html)$/ -> "ui"
        path(payload) =~ ~r/(docker|compose|config|production|infra|deploy)/ -> "deploy"
        true -> "backend"
      end
  end

  defp infer_risk_tier(payload, metadata) do
    metadata["risk_tier"] ||
      cond do
        category(payload) == "privacy" -> "high"
        Map.get(payload, "expected_decision") == "block" -> "high"
        true -> "moderate"
      end
  end

  defp infer_domain_pack(payload, metadata) do
    metadata["domain_pack"] ||
      cond do
        String.contains?(String.downcase(Map.get(payload, "incident_label", "")), "phi") ->
          "healthcare"

        String.contains?(String.downcase(Map.get(payload, "name", "")), "patient") ->
          "healthcare"

        true ->
          "software"
      end
  end

  defp infer_budget_tier(payload, metadata) do
    metadata["budget_tier"] ||
      cond do
        path(payload) =~ ~r/(docker|deploy|infra|production)/ -> "high"
        category(payload) == "security" -> "medium"
        true -> "low"
      end
  end

  defp internal_metadata?(metadata) when is_map(metadata) do
    case Map.get(metadata, "internal") do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp category(payload), do: String.downcase(Map.get(payload, "category", ""))
  defp path(payload), do: String.downcase(Map.get(payload, "path", ""))

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
