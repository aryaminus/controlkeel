defmodule ControlKeel.AgentRuntimes.T3Code do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "t3code"

  @impl true
  def runtime_transport, do: "t3code_provider_runtime"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => true, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "orchestration_domain_event"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "provider_neutral",
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
