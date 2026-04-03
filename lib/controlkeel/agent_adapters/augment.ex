defmodule ControlKeel.AgentAdapters.Augment do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "augment"

  @impl true
  def install(project_root, opts), do: Skills.install("augment-native", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("augment-native", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".augment/skills/controlkeel-governance/SKILL.md",
      ".augment/agents/controlkeel-operator.md",
      ".augment/commands/controlkeel-review.md",
      ".augment/commands/controlkeel-submit-plan.md",
      ".augment/commands/controlkeel-annotate.md",
      ".augment/commands/controlkeel-last.md",
      ".augment/rules/controlkeel.md",
      ".augment/mcp.json",
      ".augment/settings.controlkeel.json",
      ".augment-plugin/plugin.json",
      "hooks/hooks.json",
      "hooks/controlkeel-review.sh",
      "AGENTS.md",
      "AUGMENT.md",
      "README.md"
    ]
  end

  @impl true
  def review_submission_contract do
    %{
      review_experience: "native_review",
      submission_mode: "hook",
      feedback_mode: "command_reply"
    }
  end

  @impl true
  def phase_contract do
    %{
      phase_model: "host_plan_mode",
      plan_phase_support: ["planning", "review", "execution"]
    }
  end

  @impl true
  def host_capabilities do
    %{
      install_experience: "first_class",
      browser_embed: "external",
      subagent_visibility: "all",
      package_outputs: [
        %{
          "kind" => "release_bundle",
          "name" => "augment-native",
          "artifact" => "controlkeel-augment-native.tar.gz"
        },
        %{
          "kind" => "release_bundle",
          "name" => "augment-plugin",
          "artifact" => "controlkeel-augment-plugin.tar.gz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
