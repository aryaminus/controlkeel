defmodule ControlKeel.AgentRuntimes.Pi do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "pi"

  @impl true
  def runtime_transport, do: "pi_rpc"

  @impl true
  def runtime_auth_owner, do: "agent"

  @impl true
  def runtime_session_support do
    %{"create" => true, "fork" => false, "resume" => false, "streaming" => true}
  end

  @impl true
  def runtime_review_transport, do: "extension_rpc"

  @impl true
  def runtime_provider_hint(_project_root, _opts) do
    %{
      "provider" => "pi_connected",
      "source" => "agent_runtime",
      "auth_mode" => "agent_runtime",
      "auth_owner" => "agent"
    }
  end
end
