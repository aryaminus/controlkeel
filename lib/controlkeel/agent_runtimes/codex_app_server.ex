defmodule ControlKeel.AgentRuntimes.CodexAppServer do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "codex-app-server"

  @impl true
  def runtime_transport, do: "codex_app_server_json_rpc"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => true, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "app_server_review"

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
      tool_approval: true,
      user_input_pause_resume: true,
      deterministic_event_ids: true,
      replay_safe_delivery: true
    }
  end
end
