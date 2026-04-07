defmodule ControlKeel.Intent.ExecutionPosture do
  @moduledoc false

  alias ControlKeel.Intent.ExecutionBrief

  @default_clearance_focus ~w(file_write network deploy secrets)
  @regulated_risk_tiers ~w(high critical)

  @default_posture %{
    "exploration_surface" => "virtual_workspace",
    "state_surface" => "typed_storage",
    "api_execution_surface" => "typed_runtime_or_shell",
    "mutation_surface" => "shell_sandbox",
    "shell_role" => "fallback",
    "clearance_focus" => @default_clearance_focus,
    "rationale" =>
      "Prefer read-only discovery first, keep durable state in typed storage surfaces, use typed runtimes for large tool and API interactions when available, and treat shell as the broad fallback surface for mutation and execution."
  }

  def build(%ExecutionBrief{} = brief), do: build(ExecutionBrief.to_map(brief))

  def build(brief) when is_map(brief) do
    risk_tier = fetch_string(brief, "risk_tier")
    compliance = normalize_list(fetch_value(brief, "compliance"))

    regulated? =
      risk_tier in @regulated_risk_tiers or
        compliance != [] or
        external_or_sensitive_data?(brief)

    %{
      "exploration_surface" => "virtual_workspace",
      "state_surface" => "typed_storage",
      "api_execution_surface" =>
        if(regulated?, do: "typed_runtime", else: "typed_runtime_or_shell"),
      "mutation_surface" => "shell_sandbox",
      "shell_role" => if(regulated?, do: "broad_fallback_only", else: "repo_local_fallback"),
      "clearance_focus" => clearance_focus(risk_tier),
      "rationale" => rationale(regulated?, risk_tier, compliance)
    }
  end

  def build(_brief), do: @default_posture

  defp clearance_focus("critical"), do: ["bash" | @default_clearance_focus]
  defp clearance_focus("high"), do: ["bash" | @default_clearance_focus]
  defp clearance_focus(_risk_tier), do: @default_clearance_focus

  defp rationale(true, risk_tier, compliance) do
    risk_label = risk_tier || "elevated"

    compliance_label =
      case compliance do
        [] -> "sensitive or external-system-heavy work"
        items -> "compliance pressure (#{Enum.join(items, ", ")})"
      end

    "This brief is #{risk_label} risk or carries #{compliance_label}, so CK should favor read-only exploration, typed storage-backed state, and typed execution for tool and API work before granting broad shell authority."
  end

  defp rationale(false, _risk_tier, _compliance) do
    "This brief can stay hybrid: use the virtual workspace for discovery, keep state in typed storage-backed surfaces, prefer typed execution when it reduces context and side effects, and keep shell focused on repo-local mutation and test flows."
  end

  defp external_or_sensitive_data?(brief) do
    [fetch_string(brief, "data_summary"), fetch_string(brief, "recommended_stack")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
    |> then(fn text ->
      Enum.any?(
        ~w(api webhook postgres mysql redis salesforce stripe slack pii phi payroll billing patient healthcare legal finance),
        &String.contains?(text, &1)
      )
    end)
  end

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(_value), do: []

  defp fetch_string(map, key) do
    case fetch_value(map, key) do
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

  defp fetch_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp known_atom_key("risk_tier"), do: :risk_tier
  defp known_atom_key("compliance"), do: :compliance
  defp known_atom_key("data_summary"), do: :data_summary
  defp known_atom_key("recommended_stack"), do: :recommended_stack
  defp known_atom_key(_key), do: nil
end
