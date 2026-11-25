defmodule ControlKeel.Skills.Exporter.ClineNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    mcp_path = Path.join(root, ".cline/data/settings/cline_mcp_settings.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    rule_path = Path.join(root, ".clinerules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.cline_rule_contents())

    workflow_path = Path.join(root, ".clinerules/workflows/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, E.cline_workflow_contents())

    command_path = Path.join(root, ".cline/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.cline_command_contents())

    submit_command_path = Path.join(root, ".cline/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.cline_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".cline/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Cline", "cline", ".cline/annotate.md")
    )

    last_command_path = Path.join(root, ".cline/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Cline"))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("cline", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => workflow_path, "kind" => "workflow"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.agents/skills` into your project (or `~/.agents/skills`), alongside the `.clinerules` guidance.",
        "Keep `.clinerules/`, `.cline/commands`, and `.cline/hooks` in the repo so Cline loads ControlKeel rules, workflows, commands, and hooks for the governed workspace.",
        "Merge `.cline/data/settings/cline_mcp_settings.json` into Cline MCP settings (`~/.cline/data/settings/cline_mcp_settings.json` or `$CLINE_DIR/data/settings/cline_mcp_settings.json`)."
      ]
    )
  end
end
