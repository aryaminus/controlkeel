defmodule ControlKeel.Skills.Exporter.KiloNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    command_path = Path.join(root, ".kilo/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.kilo_command_contents())

    submit_command_path = Path.join(root, ".kilo/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Kilo Code", "kilo", ".kilo/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".kilo/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Kilo Code", "kilo", ".kilo/annotate.md")
    )

    last_command_path = Path.join(root, ".kilo/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Kilo Code"))

    config_path = Path.join(root, ".kilo/kilo.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(E.kilo_config_snippet(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("kilo", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.agents/skills/` into your repo (or `~/.agents/skills/`) for Agent Skills discovery.",
        "Copy `.kilo/commands/` into the project root so Kilo can expose `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last`.",
        "Merge `.kilo/kilo.json` into `kilo.json` or `~/.config/kilo/kilo.json` to register the ControlKeel MCP server."
      ]
    )
  end
end
