defmodule ControlKeel.AgentAdapters.Registry do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Skills.SkillTarget

  @modules [
    ControlKeel.AgentAdapters.ClaudeCode,
    ControlKeel.AgentAdapters.CodexCLI,
    ControlKeel.AgentAdapters.Copilot,
    ControlKeel.AgentAdapters.OpenCode,
    ControlKeel.AgentAdapters.Pi,
    ControlKeel.AgentAdapters.VSCode
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

      adapter ->
        review = adapter.review_submission_contract()
        phase = adapter.phase_contract()
        capabilities = adapter.host_capabilities()
        artifacts = adapter.artifact_manifest(scope: integration.default_scope)

        %AgentIntegration{
          integration
          | install_experience:
              Map.get(capabilities, :install_experience, integration.install_experience),
            review_experience: Map.get(review, :review_experience, integration.review_experience),
            submission_mode: Map.get(review, :submission_mode, integration.submission_mode),
            feedback_mode: Map.get(review, :feedback_mode, integration.feedback_mode),
            plan_phase_support:
              Map.get(phase, :plan_phase_support, integration.plan_phase_support),
            artifact_surfaces:
              if(artifacts == [], do: integration.artifact_surfaces, else: artifacts),
            phase_model: Map.get(phase, :phase_model, integration.phase_model),
            browser_embed: Map.get(capabilities, :browser_embed, integration.browser_embed),
            subagent_visibility:
              Map.get(capabilities, :subagent_visibility, integration.subagent_visibility),
            package_outputs: Map.get(capabilities, :package_outputs, integration.package_outputs)
        }
    end
  end

  def skill_targets do
    @modules
    |> Enum.flat_map(&apply(&1, :skill_targets, []))
    |> Enum.map(&build_target/1)
  end

  def package_outputs(id) do
    case get(id) do
      nil -> []
      adapter -> adapter.host_capabilities()[:package_outputs] || []
    end
  end

  defp build_target(attrs) do
    struct!(SkillTarget, attrs)
  end

  defp normalize_id(id) do
    id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
