defmodule ControlKeel.AgentRuntimes.Augment do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "augment"

  @impl true
  def runtime_transport, do: "auggie_sdk_acp"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => false, "resume" => true, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "plugin_hook_acp"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "augment_runtime",
      "source" => "agent_runtime",
      "auth_mode" => "agent_runtime",
      "auth_owner" => "agent"
    }
  end
end
