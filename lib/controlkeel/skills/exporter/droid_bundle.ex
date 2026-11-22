defmodule ControlKeel.Skills.Exporter.DroidBundle do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    droid_path = Path.join(root, ".factory/droids/controlkeel.md")
    File.mkdir_p!(Path.dirname(droid_path))
    File.write!(droid_path, E.droid_profile_contents())

    review_command_path = Path.join(root, ".factory/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.droid_review_command_contents())

    submit_command_path = Path.join(root, ".factory/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.droid_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".factory/commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, E.droid_annotate_command_contents())

    last_command_path = Path.join(root, ".factory/commands/controlkeel-last.md")
    File.write!(last_command_path, E.droid_last_command_contents())

    mcp_path = Path.join(root, ".factory/mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("droid", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => droid_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.factory/` into the repo or your user Factory config directory.",
        "Use the generated droid profile plus the review, submit-plan, annotate, and last commands as the governed ControlKeel entry point."
      ]
    )
  end
end
