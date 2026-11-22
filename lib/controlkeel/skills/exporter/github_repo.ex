defmodule ControlKeel.Skills.Exporter.GithubRepo do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".github/skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".github/agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.copilot_agent_contents(skills))

    command_path = Path.join(root, ".github/commands/controlkeel-plan-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.copilot_plan_review_command_contents())

    review_command_path = Path.join(root, ".github/commands/controlkeel-review.md")
    File.write!(review_command_path, E.host_review_command_contents("GitHub Copilot", "copilot"))

    annotate_command_path = Path.join(root, ".github/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents(
        "GitHub Copilot",
        "copilot",
        ".github/controlkeel-annotate.md"
      )
    )

    last_command_path = Path.join(root, ".github/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("GitHub Copilot"))

    github_mcp = Path.join(root, ".github/mcp.json")

    File.write!(
      github_mcp,
      Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    vscode_mcp = Path.join(root, ".vscode/mcp.json")
    File.mkdir_p!(Path.dirname(vscode_mcp))

    File.write!(
      vscode_mcp,
      Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    instructions_path = Path.join(root, ".github/copilot-instructions.md")
    File.mkdir_p!(Path.dirname(instructions_path))
    File.write!(instructions_path, E.instructions_only_contents("copilot", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => github_mcp, "kind" => "mcp"},
        %{"path" => vscode_mcp, "kind" => "mcp"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Copy the .github and .vscode folders into your repository root.",
        "VS Code and Copilot can then discover the skills, custom agent, command prompts, and MCP server config from the repo."
      ]
    )
  end
end
