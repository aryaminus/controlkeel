defmodule ControlKeel.Runtime.CodeModePolicy do
  @moduledoc """
  Guardrail policy for programmatic tool calling and generated mini-scripts.

  This module intentionally does not execute code. It gives planners, routers,
  review tools, and future runtimes a compact contract for when generated code
  can be considered for execution and which controls must wrap it.
  """

  @regulated_risk_tiers ~w(high critical)

  @default_limits %{
    "max_runtime_ms" => 30_000,
    "max_concurrent_runs" => 1,
    "max_network_requests" => 0,
    "max_output_bytes" => 65_536
  }

  @relaxed_limits %{
    "max_runtime_ms" => 60_000,
    "max_concurrent_runs" => 2,
    "max_network_requests" => 10,
    "max_output_bytes" => 131_072
  }

  @doc "Build a code-mode policy map for generated API orchestration code."
  def build(opts \\ []) do
    risk_tier = opts |> Keyword.get(:risk_tier, "medium") |> normalize_risk_tier()
    requested_capabilities = normalize_list(Keyword.get(opts, :requested_capabilities, []))
    network_allowlist = normalize_list(Keyword.get(opts, :network_allowlist, []))
    mode = Keyword.get(opts, :mode, :generated_script) |> to_string()

    allowed_capabilities =
      allowed_capabilities(requested_capabilities, network_allowlist, risk_tier)

    %{
      "mode" => mode,
      "status" => "advisory_contract",
      "sandbox_required" => true,
      "approval_required" =>
        approval_required?(risk_tier, requested_capabilities, network_allowlist),
      "default_denied_capabilities" => ["filesystem", "network", "secrets", "shell", "deploy"],
      "allowed_capabilities" => allowed_capabilities,
      "network_allowlist" => network_allowlist,
      "limits" => limits_for(risk_tier, allowed_capabilities),
      "rate_policy" => rate_policy(risk_tier, allowed_capabilities),
      "proof_artifacts" => [
        "generated_source",
        "validated_capability_grants",
        "sandbox_runtime_log",
        "egress_summary",
        "result_digest"
      ],
      "review_notes" => review_notes(risk_tier, allowed_capabilities)
    }
  end

  @doc "Returns true when a brief looks like it benefits from code-mode policy metadata."
  def relevant_brief?(brief) when is_map(brief) do
    text =
      [
        value(brief, "idea"),
        value(brief, "data_summary"),
        value(brief, "recommended_stack"),
        value(brief, "next_step"),
        value(brief, "acceptance_criteria")
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.downcase()

    Enum.any?(
      [
        "code-mode",
        "code mode",
        "programmatic tool",
        "generated script",
        "mini-script",
        "typed runtime",
        "openapi",
        "api orchestration",
        "mcp tool",
        "large api"
      ],
      &String.contains?(text, &1)
    )
  end

  def relevant_brief?(_brief), do: false

  defp allowed_capabilities(requested, network_allowlist, risk_tier) do
    requested
    |> Enum.filter(fn
      "network" -> network_allowlist != [] and risk_tier not in ["critical"]
      capability -> capability in ["read_api", "write_api"]
    end)
    |> Enum.uniq()
  end

  defp approval_required?(risk_tier, requested, network_allowlist) do
    risk_tier in @regulated_risk_tiers or
      Enum.any?(requested, &(&1 in ["network", "write_api", "deploy", "secrets", "shell"])) or
      network_allowlist != []
  end

  defp limits_for(risk_tier, allowed_capabilities) do
    if risk_tier in ["low", "medium"] and "network" in allowed_capabilities do
      @relaxed_limits
    else
      @default_limits
    end
  end

  defp rate_policy(risk_tier, allowed_capabilities) do
    %{
      "max_requests_per_minute" => rpm_for(risk_tier, allowed_capabilities),
      "respect_retry_after" => true
    }
  end

  defp rpm_for("critical", _allowed), do: 0
  defp rpm_for("high", _allowed), do: 6

  defp rpm_for(_risk_tier, allowed) do
    if "network" in allowed, do: 30, else: 0
  end

  defp review_notes(risk_tier, allowed_capabilities) do
    [
      "Generated code is data until ck_validate and human/CK review approve the capability grants.",
      "Run in an isolated runtime with filesystem, shell, secrets, deploy, and network denied by default.",
      if("network" in allowed_capabilities,
        do:
          "Network access is limited to the reviewed allowlist and must respect retry-after/rate-limit telemetry.",
        else: "Network access remains disabled."
      ),
      if(risk_tier in @regulated_risk_tiers,
        do: "High-risk or regulated briefs require explicit approval before execution.",
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_risk_tier(value) when value in ["low", "medium", "high", "critical"], do: value
  defp normalize_risk_tier("moderate"), do: "medium"

  defp normalize_risk_tier(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_risk_tier()

  defp normalize_risk_tier(_value), do: "medium"

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value) when is_binary(value), do: normalize_list([value])
  defp normalize_list(_value), do: []

  defp value(map, key), do: Map.get(map, key) || Map.get(map, known_atom_key(key))

  defp known_atom_key("idea"), do: :idea
  defp known_atom_key("data_summary"), do: :data_summary
  defp known_atom_key("recommended_stack"), do: :recommended_stack
  defp known_atom_key("next_step"), do: :next_step
  defp known_atom_key("acceptance_criteria"), do: :acceptance_criteria
  defp known_atom_key(_key), do: nil
end
