defmodule ControlKeel.AgentRuntimes.Copilot do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "copilot"

  @impl true
  def runtime_transport, do: "hook_session_parser"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => false, "fork" => false, "resume" => false, "streaming" => false}
  end

  @impl true
  def runtime_review_transport, do: "hook_session_state"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "openai",
      "source" => "agent_runtime",
      "auth_mode" => "agent_runtime",
      "auth_owner" => "agent"
    }
  end
end
