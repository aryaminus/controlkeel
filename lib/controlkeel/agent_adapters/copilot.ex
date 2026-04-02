defmodule ControlKeel.AgentAdapters.Copilot do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "copilot"

  @impl true
  def install(project_root, opts), do: Skills.install("github-repo", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("copilot-plugin", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".github/skills",
      ".github/agents",
      ".github/mcp.json",
      ".github/copilot-instructions.md",
      ".github/commands/controlkeel-plan-review.md",
      ".vscode/mcp.json",
      ".vscode/extensions.json",
      "plugin.json",
      "hooks.json"
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
      subagent_visibility: "primary_only",
      package_outputs: [
        %{
          "kind" => "release_bundle",
          "name" => "copilot-plugin",
          "artifact" => "controlkeel-copilot-plugin.tar.gz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
