defmodule ControlKeel.Governance.ApprovalAdapter do
  @moduledoc false

  # CK-side approval decision adapter for external runtimes.
  # When a provider-neutral runtime like t3code encounters request.opened
  # or canUseTool, it calls evaluate/2 to get a CK governance decision
  # without needing to understand CK's internal policy engine.

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Intent.RuntimePolicyProfile

  @tool_risk_tiers %{
    "shell" => :high,
    "bash" => :high,
    "deploy" => :high,
    "network" => :high,
    "secrets" => :critical,
    "file_write" => :medium,
    "file_read" => :low,
    "file_edit" => :medium,
    "tool_call" => :medium,
    "mcp" => :medium,
    "browser" => :medium,
    "git" => :medium
  }

  @default_tier :medium

  @doc """
  Evaluate whether a tool execution request should be allowed.

  Returns a decision map with:
    - decision: :accept | :accept_for_session | :decline | :cancel
    - reason: human-readable explanation
    - policy_rule_ids: list of rule IDs that informed the decision
    - requires_human_approval: boolean
  """
  def evaluate(agent_id, request, opts \\ []) do
    integration = AgentIntegration.get(agent_id)
    capabilities = integration && integration.runtime_capabilities
    policy_mode = Keyword.get(opts, :policy_mode) || infer_policy_mode(integration)
    profile = RuntimePolicyProfile.resolve(policy_mode)
    tool_tier = tool_risk_tier(request)

    evaluate_decision(capabilities, profile, tool_tier, request)
  end

  @doc """
  Evaluate a batch of tool requests and return per-tool decisions.
  """
  def evaluate_batch(agent_id, requests, opts \\ []) do
    Enum.map(requests, fn request ->
      {request_key(request), evaluate(agent_id, request, opts)}
    end)
  end

  @doc """
  Returns the tool risk tier for a given request.
  """
  def tool_risk_tier(request) do
    tool_name =
      (request["tool"] || request[:tool] || "")
      |> to_string()
      |> String.downcase()

    # Check prefix matches for compound tool names
    Enum.find_value(@tool_risk_tiers, @default_tier, fn {prefix, tier} ->
      if String.starts_with?(tool_name, prefix), do: tier
    end)
  end

  @doc """
  List all tool risk tiers.
  """
  def tool_risk_tiers, do: @tool_risk_tiers

  defp evaluate_decision(nil, _profile, _tier, _request) do
    %{
      decision: :decline,
      reason: "Unknown agent — no integration found for governance evaluation.",
      policy_rule_ids: ["UNKNOWN_AGENT"],
      requires_human_approval: true
    }
  end

  defp evaluate_decision(capabilities, _profile, :critical, _request) do
    if capabilities[:tool_approval] do
      %{
        decision: :decline,
        reason:
          "Critical-tier tool requires explicit human approval through the runtime's approval flow.",
        policy_rule_ids: ["CRITICAL_TOOL_GATE"],
        requires_human_approval: true
      }
    else
      %{
        decision: :decline,
        reason: "Critical-tier tool blocked — runtime does not support tool-level approval.",
        policy_rule_ids: ["CRITICAL_TOOL_NO_APPROVAL_SUPPORT"],
        requires_human_approval: true
      }
    end
  end

  defp evaluate_decision(
         %{policy_gate: true},
         %{"interactive_gate" => true} = profile,
         :medium,
         _request
       ) do
    %{
      decision: :accept_for_session,
      reason:
        "Interactive gate active (mode: #{profile["mode"]}) but medium-tier tool is covered by CK policy preflight and post-action validation.",
      policy_rule_ids: ["INTERACTIVE_GATE_MEDIUM_POLICY_ALLOW"],
      requires_human_approval: false
    }
  end

  defp evaluate_decision(
         _capabilities,
         %{"interactive_gate" => true} = profile,
         :medium,
         _request
       ) do
    %{
      decision: :decline,
      reason:
        "Interactive gate active (mode: #{profile["mode"]}). Medium-tier tool requires human checkpoint because this runtime lacks CK policy-gate support.",
      policy_rule_ids: ["INTERACTIVE_GATE_MEDIUM_NO_POLICY_GATE"],
      requires_human_approval: true
    }
  end

  defp evaluate_decision(_capabilities, %{"interactive_gate" => true} = profile, :high, _request) do
    %{
      decision: :decline,
      reason:
        "Interactive gate active (mode: #{profile["mode"]}). High-tier tool requires human checkpoint.",
      policy_rule_ids: ["INTERACTIVE_GATE_HIGH"],
      requires_human_approval: true
    }
  end

  defp evaluate_decision(
         _capabilities,
         %{"deny_shell_network_deploy_by_default" => true},
         tier,
         _request
       )
       when tier in [:high, :critical] do
    %{
      decision: :decline,
      reason: "Auto-accept-edits mode denies #{tier}-tier tools by default.",
      policy_rule_ids: ["AUTO_ACCEPT_DENY_#{tier |> to_string() |> String.upcase()}"],
      requires_human_approval: true
    }
  end

  defp evaluate_decision(%{policy_gate: true}, %{"preflight" => "strict"}, tier, _request)
       when tier in [:high, :medium] do
    %{
      decision: :accept_for_session,
      reason: "Strict preflight allows #{tier}-tier tool for this session.",
      policy_rule_ids: ["STRICT_PREFLOW_ALLOW_#{tier |> to_string() |> String.upcase()}"],
      requires_human_approval: false
    }
  end

  defp evaluate_decision(%{policy_gate: true}, _profile, :low, _request) do
    %{
      decision: :accept,
      reason: "Low-tier tool allowed.",
      policy_rule_ids: ["LOW_TIER_ALLOW"],
      requires_human_approval: false
    }
  end

  defp evaluate_decision(%{policy_gate: true}, _profile, _tier, _request) do
    %{
      decision: :accept_for_session,
      reason: "Policy gate active — tool accepted for this session.",
      policy_rule_ids: ["POLICY_GATE_ACCEPT"],
      requires_human_approval: false
    }
  end

  defp evaluate_decision(_capabilities, _profile, _tier, _request) do
    %{
      decision: :accept,
      reason: "No specific governance restriction applies.",
      policy_rule_ids: [],
      requires_human_approval: false
    }
  end

  defp infer_policy_mode(%{autonomy_mode: mode}), do: mode
  defp infer_policy_mode(%{phase_model: "review_only"}), do: "approval_required"
  defp infer_policy_mode(_), do: "full_access"

  defp request_key(request) do
    request["request_id"] || request[:request_id] || request["tool"] || "unknown"
  end
end
