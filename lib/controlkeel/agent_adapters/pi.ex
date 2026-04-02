defmodule ControlKeel.AgentAdapters.Pi do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "pi"

  @impl true
  def install(project_root, opts), do: Skills.install("pi-native", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("pi-native", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".agents/skills",
      ".pi/controlkeel.json",
      ".pi/commands/controlkeel-review.md",
      ".pi/commands/controlkeel-submit-plan.md",
      ".pi/mcp.json",
      "pi-extension.json",
      "package.json",
      "README.md",
      "PI.md"
    ]
  end

  @impl true
  def review_submission_contract do
    %{
      review_experience: "browser_review",
      submission_mode: "command",
      feedback_mode: "command_reply"
    }
  end

  @impl true
  def phase_contract do
    %{
      phase_model: "file_plan_mode",
      plan_phase_support: ["planning", "review", "execution"]
    }
  end

  @impl true
  def host_capabilities do
    %{
      install_experience: "first_class",
      browser_embed: "external",
      subagent_visibility: "primary_only",
      package_outputs: [
        %{
          "kind" => "release_bundle",
          "name" => "pi-native",
          "artifact" => "controlkeel-pi-native.tar.gz"
        },
        %{
          "kind" => "npm_package",
          "name" => "@aryaminus/controlkeel-pi-extension",
          "artifact" => "controlkeel-pi-native.tgz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
