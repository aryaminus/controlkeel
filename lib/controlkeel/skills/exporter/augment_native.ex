defmodule ControlKeel.Skills.Exporter.AugmentNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".augment/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.augment_agent_contents(skills))

    command_path = Path.join(root, ".augment/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.augment_review_command_contents())

    submit_command_path = Path.join(root, ".augment/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.augment_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".augment/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Augment", "augment", ".augment/annotate.md")
    )

    last_command_path = Path.join(root, ".augment/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Augment"))

    rule_path = Path.join(root, ".augment/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.augment_rule_contents())

    mcp_path = Path.join(root, ".augment/mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    settings_path = Path.join(root, ".augment/settings.controlkeel.json")

    File.write!(
      settings_path,
      Jason.encode!(E.augment_settings_snippet(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("augment", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => settings_path, "kind" => "settings"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.agents/skills`, `.augment/agents`, `.augment/commands`, and `.augment/rules` in the repo so Auggie loads ControlKeel-native guidance automatically.",
        "Use `.augment/mcp.json` with `auggie --mcp-config ./.augment/mcp.json` for ephemeral MCP wiring or merge `.augment/settings.controlkeel.json` into `~/.augment/settings.json` for persistence."
      ]
    )
  end
end
