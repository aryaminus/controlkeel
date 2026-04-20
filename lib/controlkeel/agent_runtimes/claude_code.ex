defmodule ControlKeel.AgentRuntimes.ClaudeCode do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "claude-code"

  @impl true
  def runtime_transport, do: "claude_agent_sdk"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => true, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "hook_sdk"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "anthropic",
      "source" => "agent_runtime",
      "auth_mode" => "env_bridge",
      "auth_owner" => "agent"
    }
  end

  @impl true
  def capabilities do
    %{
      policy_gate: true,
      tool_approval: true,
      user_input_pause_resume: true,
      deterministic_event_ids: false,
      replay_safe_delivery: false
    }
  end
end
