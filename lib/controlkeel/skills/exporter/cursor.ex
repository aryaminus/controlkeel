defmodule ControlKeel.Skills.Exporter.Cursor do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".cursor/rules/controlkeel.mdc")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.cursor_rule_contents())

    command_path = Path.join(root, ".cursor/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.cursor_command_contents())

    submit_command_path = Path.join(root, ".cursor/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.cursor_submit_plan_command_contents())

    diff_command_path = Path.join(root, ".cursor/commands/controlkeel-diff-review.md")
    File.write!(diff_command_path, E.cursor_diff_review_command_contents())

    completion_command_path = Path.join(root, ".cursor/commands/controlkeel-completion-review.md")
    File.write!(completion_command_path, E.cursor_completion_review_command_contents())

    annotate_command_path = Path.join(root, ".cursor/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Cursor", "cursor", ".cursor/annotate.md")
    )

    last_command_path = Path.join(root, ".cursor/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Cursor"))

    agent_path = Path.join(root, ".cursor/agents/controlkeel-governor.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.cursor_agent_contents())

    background_agent_path = Path.join(root, ".cursor/background-agents/controlkeel.md")
    File.mkdir_p!(Path.dirname(background_agent_path))
    File.write!(background_agent_path, E.cursor_background_agent_contents())

    hooks_path = Path.join(root, ".cursor/hooks.json")
    File.write!(hooks_path, Jason.encode!(E.cursor_hooks_manifest(), pretty: true) <> "\n")

    hook_dir = Path.join(root, ".cursor/hooks")
    File.mkdir_p!(hook_dir)

    for {name, contents_fn} <- E.cursor_hook_scripts() do
      path = Path.join(hook_dir, name)
      File.write!(path, contents_fn.())
      File.chmod!(path, 0o755)
    end

    mcp_path = Path.join(root, ".cursor/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))

    File.write!(
      mcp_path,
      Jason.encode!(E.cursor_mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    plugin_root = Path.join(root, ".cursor-plugin")
    plugin_path = Path.join(plugin_root, "plugin.json")
    plugin_hooks_json = Path.join(plugin_root, "hooks/hooks.json")
    E.write_cursor_plugin_bundle!(root, project_root, opts)

    agents_path = Path.join(root, "AGENTS.md")

    unless E.version_downgrade_for_path?(E.app_version(), plugin_path) do
      File.write!(agents_path, E.instructions_only_contents("cursor", project_root, opts))
    end

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => diff_command_path, "kind" => "command"},
        %{"path" => completion_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => background_agent_path, "kind" => "workflow"},
        %{"path" => plugin_path, "kind" => "plugin"},
        %{"path" => plugin_hooks_json, "kind" => "hooks"},
        %{"path" => Path.join(plugin_root, "rules"), "kind" => "rules"},
        %{"path" => Path.join(plugin_root, "skills"), "kind" => "skills"},
        %{"path" => Path.join(plugin_root, "agents"), "kind" => "agent"},
        %{"path" => Path.join(plugin_root, "commands"), "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.cursor/rules`, `.cursor/commands`, `.cursor/hooks`, `.cursor/skills`, `.cursor/agents`, and `.cursor/background-agents` in the repo so Cursor loads ControlKeel governance.",
        "Use .cursor/mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template.",
        "The `.cursor-plugin/` directory is a distributable Cursor plugin bundle: manifest, mirrored rules/skills/agents/commands, and `hooks/hooks.json` with the same gate scripts as `.cursor/hooks/`."
      ]
    )
  end
end
