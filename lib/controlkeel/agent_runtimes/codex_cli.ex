defmodule ControlKeel.AgentRuntimes.CodexCLI do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "codex-cli"

  @impl true
  def runtime_transport, do: "codex_sdk"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => false, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "command_thread"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "openai",
      "source" => "agent_runtime",
      "auth_mode" => "agent_runtime",
      "auth_owner" => "agent"
    }
  end

  @impl true
  def capabilities do
    %{
      policy_gate: true,
      tool_approval: false,
      user_input_pause_resume: false,
      deterministic_event_ids: false,
      replay_safe_delivery: false
    }
  end
end
