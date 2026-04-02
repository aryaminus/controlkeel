defmodule ControlKeel.AgentAdapters.VSCode do
  @moduledoc false

  @behaviour ControlKeel.AgentAdapters.Adapter

  alias ControlKeel.Skills

  @impl true
  def id, do: "vscode"

  @impl true
  def install(project_root, opts), do: Skills.install("github-repo", project_root, opts)

  @impl true
  def export(project_root, opts), do: Skills.export("vscode-companion", project_root, opts)

  @impl true
  def artifact_manifest(_opts) do
    [
      ".github/skills",
      ".github/agents",
      ".github/mcp.json",
      ".vscode/mcp.json",
      ".vscode/extensions.json",
      "extension/package.json",
      "extension/extension.js"
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
      browser_embed: "vscode_webview",
      subagent_visibility: "none",
      package_outputs: [
        %{
          "kind" => "release_bundle",
          "name" => "github-repo",
          "artifact" => "controlkeel-github-repo.tar.gz"
        },
        %{
          "kind" => "vsix",
          "name" => "vscode-companion",
          "artifact" => "controlkeel-vscode-companion.vsix"
        }
      ]
    }
  end

  @impl true
  def skill_targets do
    [
      %{
        id: "vscode-companion",
        label: "VS Code companion extension",
        description:
          "VS Code webview companion that opens ControlKeel browser reviews inside the editor and injects terminal routing env vars.",
        native: true,
        default_scope: "export",
        supported_scopes: ["export"],
        release_bundle: true
      }
    ]
  end
end
