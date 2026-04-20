defmodule ControlKeel.Intent.RuntimePolicyProfile do
  @moduledoc false

  @profiles %{
    "full_access" => %{
      "preflight" => "strict",
      "post_action" => "mandatory",
      "interactive_gate" => false,
      "human_checkpoint" => false,
      "deny_shell_network_deploy_by_default" => false,
      "description" =>
        "Runtime allows full autonomous access. CK enforces strict preflight checks and mandatory post-action validation."
    },
    "approval_required" => %{
      "preflight" => "standard",
      "post_action" => "optional",
      "interactive_gate" => true,
      "human_checkpoint" => true,
      "deny_shell_network_deploy_by_default" => false,
      "description" =>
        "Runtime requires explicit approval before tool execution. CK gates tool calls with interactive human checkpoints."
    },
    "auto_accept_edits" => %{
      "preflight" => "standard",
      "post_action" => "standard",
      "interactive_gate" => false,
      "human_checkpoint" => false,
      "deny_shell_network_deploy_by_default" => true,
      "description" =>
        "Runtime auto-accepts file edits. CK gates shell, network, deploy, and secrets tools; file edits flow through with standard validation."
    }
  }

  @default_mode "full_access"

  def resolve(nil), do: resolve(@default_mode)
  def resolve(""), do: resolve(@default_mode)

  def resolve(mode) when is_binary(mode) do
    normalized = normalize_mode(mode)

    Map.get(@profiles, normalized, Map.get(@profiles, @default_mode))
    |> Map.put("mode", normalized)
  end

  def resolve(_), do: resolve(@default_mode)

  def profiles, do: @profiles

  def modes, do: Map.keys(@profiles)

  defp normalize_mode("full-access"), do: "full_access"
  defp normalize_mode("full_access"), do: "full_access"
  defp normalize_mode("approval-required"), do: "approval_required"
  defp normalize_mode("approval_required"), do: "approval_required"
  defp normalize_mode("auto-accept-edits"), do: "auto_accept_edits"
  defp normalize_mode("auto_accept_edits"), do: "auto_accept_edits"
  defp normalize_mode("supervised"), do: "approval_required"
  defp normalize_mode(other), do: other
end
