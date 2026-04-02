defmodule ControlKeel.AgentAdapters.OpenCode do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "opencode"

  @impl true
  def install(project_root, opts), do: Skills.install("opencode-native", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("opencode-native", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".opencode/plugins/controlkeel-governance.ts",
      ".opencode/agents/controlkeel-operator.md",
      ".opencode/commands/controlkeel-review.md",
      ".opencode/commands/controlkeel-submit-plan.md",
      ".opencode/mcp.json",
      "package.json",
      "index.js",
      "README.md",
      "AGENTS.md"
    ]
  end

  @impl true
  def review_submission_contract do
    %{
      review_experience: "native_review",
      submission_mode: "tool_call",
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
          "name" => "opencode-native",
          "artifact" => "controlkeel-opencode-native.tar.gz"
        },
        %{
          "kind" => "npm_package",
          "name" => "@aryaminus/controlkeel-opencode",
          "artifact" => "controlkeel-opencode-native.tgz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
