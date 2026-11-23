defmodule ControlKeel.Skills.Exporter.KiroNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    # 0. Skill tree
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    # 2. Steering file
    steering_path = Path.join(root, ".kiro/steering/controlkeel.md")
    File.mkdir_p!(Path.dirname(steering_path))
    File.write!(steering_path, E.kiro_steering_contents())

    command_path = Path.join(root, ".kiro/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.kiro_command_contents())

    submit_command_path = Path.join(root, ".kiro/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Kiro", "kiro", ".kiro/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".kiro/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Kiro", "kiro", ".kiro/annotate.md")
    )

    last_command_path = Path.join(root, ".kiro/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Kiro"))

    # 3. MCP config
    mcp_path = Path.join(root, ".kiro/mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    # 4. Instructions
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("kiro", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => steering_path, "kind" => "instructions"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.kiro/steering/` and `.kiro/commands/` for governed agent guidance.",
        "Merge `.kiro/mcp.json` into your Kiro MCP settings."
      ]
    )
  end
end
