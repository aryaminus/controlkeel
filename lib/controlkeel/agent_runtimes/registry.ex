defmodule ControlKeel.AgentRuntimes.Registry do
  @moduledoc false

  alias ControlKeel.AgentIntegration

  @modules [
    ControlKeel.AgentRuntimes.Augment,
    ControlKeel.AgentRuntimes.ClaudeCode,
    ControlKeel.AgentRuntimes.CodexCLI,
    ControlKeel.AgentRuntimes.Copilot,
    ControlKeel.AgentRuntimes.OpenCode,
    ControlKeel.AgentRuntimes.Pi,
    ControlKeel.AgentRuntimes.VSCode
  ]

  def modules, do: @modules

  def get(id) do
    id = normalize_id(id)
    Enum.find(@modules, &(apply(&1, :id, []) == id))
  end

  def enrich_integration(%AgentIntegration{} = integration) do
    case get(integration.id) do
      nil ->
        integration

      runtime ->
        %AgentIntegration{
          integration
          | runtime_transport: runtime.runtime_transport(),
            runtime_auth_owner: runtime.runtime_auth_owner(),
            runtime_session_support: runtime.runtime_session_support(),
            runtime_review_transport: runtime.runtime_review_transport()
        }
    end
  end

  def provider_hint(id, project_root, opts \\ []) do
    case get(id) do
      nil -> nil
      runtime -> runtime.runtime_provider_hint(project_root, opts)
    end
  end

  defp normalize_id(id) do
    id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
