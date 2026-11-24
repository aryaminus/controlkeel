defmodule ControlKeel.Skills.Exporter.CopilotPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.copilot_agent_contents(skills))

    command_path = Path.join(root, "commands/controlkeel-plan-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.copilot_plan_review_command_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.write!(review_command_path, E.host_review_command_contents("GitHub Copilot", "copilot"))

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents(
        "GitHub Copilot",
        "copilot",
        ".github/controlkeel-annotate.md"
      )
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("GitHub Copilot"))

    manifest_path = Path.join(root, "plugin.json")
    File.write!(manifest_path, Jason.encode!(E.copilot_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks.json")
    File.write!(hooks_path, Jason.encode!(E.copilot_hooks_manifest(), pretty: true) <> "\n")

    shell_hook_path = Path.join(root, "bin/ck-validate-shell.sh")
    File.mkdir_p!(Path.dirname(shell_hook_path))
    File.write!(shell_hook_path, E.shell_gate_hook_contents(:copilot))
    File.chmod!(shell_hook_path, 0o755)

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"}
      ],
      [
        "Use this bundle as a local Copilot / VS Code plugin or publish it through your plugin workflow.",
        "The plugin ships `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last` command prompts and a shell-command gate. Submit plans for review with the `ck_review_submit` tool.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end
end
