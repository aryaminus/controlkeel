defmodule ControlKeel.Skills.Exporter.DevinTerminalNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, compat_skill_root)

    agent_path = Path.join(root, ".devin/agents/controlkeel-operator/AGENT.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.devin_terminal_agent_contents())

    hook_manifest_path = Path.join(root, ".devin/hooks.v1.json")
    File.mkdir_p!(Path.dirname(hook_manifest_path))

    File.write!(
      hook_manifest_path,
      Jason.encode!(E.devin_terminal_hooks_manifest(), pretty: true) <> "\n"
    )

    hook_dir = Path.join(root, ".devin/hooks")
    File.mkdir_p!(hook_dir)

    for {name, contents_fn} <- E.devin_terminal_hook_scripts() do
      path = Path.join(hook_dir, name)
      File.write!(path, contents_fn.())
      File.chmod!(path, 0o755)
    end

    config_path = Path.join(root, ".devin/config.json")

    File.write!(
      config_path,
      Jason.encode!(E.devin_terminal_config_payload(project_root, opts), pretty: true) <> "\n"
    )

    readme_path = Path.join(root, ".devin/README.md")
    File.write!(readme_path, E.devin_terminal_readme_contents(project_root, opts))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("devin-terminal", project_root, opts))

    review_command_path = Path.join(root, ".devin/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Devin", "devin"))

    submit_command_path = Path.join(root, ".devin/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Devin", "devin", ".devin/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".devin/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Devin", "devin", ".devin/annotate.md")
    )

    last_command_path = Path.join(root, ".devin/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Devin"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => hook_manifest_path, "kind" => "hooks"},
        %{"path" => hook_dir, "kind" => "hooks"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.devin/config.json`, `.devin/hooks.v1.json`, `.devin/hooks/`, `.devin/skills/`, and `.devin/agents/` in the repo so Devin for Terminal can load ControlKeel natively.",
        "Keep `.agents/skills/` as the compatibility mirror because Devin also imports open-standard AgentSkills directories.",
        "Use `devin mcp get controlkeel` or inspect `.devin/config.json` to confirm the local ControlKeel MCP registration."
      ]
    )
  end
end
