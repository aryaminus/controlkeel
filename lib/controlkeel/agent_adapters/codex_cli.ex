defmodule ControlKeel.AgentAdapters.CodexCLI do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "codex-cli"

  @impl true
  def install(project_root, opts), do: Skills.install("codex", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("codex", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".agents/skills",
      ".codex/skills",
      ".codex/config.toml",
      ".codex/hooks.json",
      ".codex/hooks",
      ".codex/agents/controlkeel-operator.toml",
      ".codex/agents/controlkeel-reviewer.toml",
      ".codex/agents/controlkeel-docs-researcher.toml",
      ".codex/commands/controlkeel-review.md",
      ".codex/commands/controlkeel-annotate.md",
      ".codex/commands/controlkeel-last.md",
      ".codex/commands/controlkeel-diff-review.md",
      ".codex/commands/controlkeel-completion-review.md",
      ".mcp.json",
      "AGENTS.md"
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
      phase_model: "review_only",
      plan_phase_support: ["review", "execution"]
    }
  end

  @impl true
  def host_capabilities do
    %{
      install_experience: "first_class",
      browser_embed: "none",
      subagent_visibility: "primary_only",
      package_outputs: [
        %{
          "kind" => "release_bundle",
          "name" => "codex",
          "artifact" => "controlkeel-codex.tar.gz"
        },
        %{
          "kind" => "release_bundle",
          "name" => "codex-plugin",
          "artifact" => "controlkeel-codex-plugin.tar.gz"
        }
      ]
    }
  end

  @impl true
  def skill_targets, do: []
end
