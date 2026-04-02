defmodule ControlKeel.AgentAdapters.ClaudeCode do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "claude-code"

  @impl true
  def install(project_root, opts), do: Skills.install("claude-plugin", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("claude-plugin", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      "skills/",
      "agents/controlkeel-operator.md",
      ".claude-plugin/plugin.json",
      "hooks/hooks.json",
      "hooks/controlkeel-review.sh",
      "hooks/controlkeel-review.ps1",
      "settings.json",
      ".mcp.json"
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
          "name" => "claude-plugin",
          "artifact" => "controlkeel-claude-plugin.tar.gz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
