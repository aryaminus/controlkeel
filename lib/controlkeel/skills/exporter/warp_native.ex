defmodule ControlKeel.Skills.Exporter.WarpNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, compat_skill_root)

    config_path = Path.join(root, ".warp/controlkeel-mcp.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(E.warp_native_mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    readme_path = Path.join(root, ".warp/README.md")
    File.write!(readme_path, E.warp_native_readme_contents(project_root, opts))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("warp", project_root, opts))

    review_command_path = Path.join(root, ".warp/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Warp", "warp"))

    submit_command_path = Path.join(root, ".warp/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Warp", "warp", ".warp/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".warp/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Warp", "warp", ".warp/annotate.md")
    )

    last_command_path = Path.join(root, ".warp/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Warp"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.agents/skills/` in the repo; Warp scans open-standard Agent Skills directories.",
        "Import or copy `.warp/controlkeel-mcp.json` into Warp Settings > MCP Servers or Warp Drive > MCP Servers; Warp local MCP is app-managed, not repo-auto-loaded.",
        "Keep `AGENTS.md` at the repo root so Warp project rules apply automatically."
      ]
    )
  end
end
