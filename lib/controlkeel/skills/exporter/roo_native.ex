defmodule ControlKeel.Skills.Exporter.RooNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".roo/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.roo_rule_contents())

    command_path = Path.join(root, ".roo/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.roo_command_contents())

    submit_command_path = Path.join(root, ".roo/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.roo_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".roo/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Roo Code", "roo-code", ".roo/annotate.md")
    )

    last_command_path = Path.join(root, ".roo/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Roo Code"))

    guidance_path = Path.join(root, ".roo/guidance/controlkeel.md")
    File.mkdir_p!(Path.dirname(guidance_path))
    File.write!(guidance_path, E.roo_guidance_contents())

    cloud_guidance_path = Path.join(root, ".roo/guidance/controlkeel-cloud-agent.md")
    File.write!(cloud_guidance_path, E.roo_cloud_guidance_contents())

    modes_path = Path.join(root, ".roomodes")
    File.write!(modes_path, E.roo_modes_contents())

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("roo-code", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => guidance_path, "kind" => "guidance"},
        %{"path" => cloud_guidance_path, "kind" => "guidance"},
        %{"path" => modes_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.roo/` and `.roomodes` into the repo root so Roo Code can discover ControlKeel skills and governed modes.",
        "Merge `.mcp.json` or register the same MCP server through Roo's MCP flow if you manage MCP outside the repo."
      ]
    )
  end
end
