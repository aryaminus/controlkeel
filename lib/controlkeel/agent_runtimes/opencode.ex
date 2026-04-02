defmodule ControlKeel.AgentRuntimes.OpenCode do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "opencode"

  @impl true
  def runtime_transport, do: "opencode_sdk"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => true, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "plugin_session_tool"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "opencode_connected",
      "source" => "agent_runtime",
      "auth_mode" => "agent_runtime",
      "auth_owner" => "agent"
    }
  end
end
