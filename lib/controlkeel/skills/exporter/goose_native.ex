defmodule ControlKeel.Skills.Exporter.GooseNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    hints_path = Path.join(root, ".goosehints")
    File.write!(hints_path, E.goose_hints_contents())

    workflow_path = Path.join(root, "goose/workflow_recipes/controlkeel-review.yaml")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, E.goose_workflow_contents())

    command_path = Path.join(root, "goose/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.goose_command_contents())

    submit_command_path = Path.join(root, "goose/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.goose_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "goose/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Goose", "goose", "goose/annotate.md")
    )

    last_command_path = Path.join(root, "goose/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Goose"))

    extension_path = Path.join(root, "goose/controlkeel-extension.yaml")
    File.mkdir_p!(Path.dirname(extension_path))
    File.write!(extension_path, E.goose_extension_yaml(project_root, opts))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("goose", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => hints_path, "kind" => "instructions"},
        %{"path" => workflow_path, "kind" => "workflow"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => extension_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.goosehints`, `goose/workflow_recipes/`, and `goose/commands/` at the repo root so Goose loads ControlKeel context, recipes, and slash-command review flows automatically.",
        "Merge `goose/controlkeel-extension.yaml` into `~/.config/goose/config.yaml` or add the same stdio extension through `goose configure`."
      ]
    )
  end
end
