defmodule ControlKeel.Skills.Exporter.OpenStandard do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  # The fallback for hosts without a named integration: the open Agent Skills
  # path, a portable `.mcp.json`, and `AGENTS.md` instructions.
  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_md = Path.join(root, "AGENTS.md")
    File.write!(agents_md, E.instructions_only_contents("open-standard", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_md, "kind" => "instructions"}
      ],
      [
        "Copy .agents/skills into your project, merge .mcp.json into your host's MCP config, and add AGENTS.md (or append it to an existing one)."
      ]
    )
  end
end
