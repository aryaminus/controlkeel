defmodule ControlKeel.Skills.Exporter.AntigravityCliNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  # Antigravity auto-discovers workspace assets under `.agents/`. CK writes
  # each surface once there; a parallel plugin bundle would register the same
  # hooks and MCP server twice.
  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    rules_path = Path.join(root, ".agents/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rules_path))
    File.write!(rules_path, E.antigravity_rules_contents())

    hooks_dir = Path.join(root, ".agents/hooks")
    File.mkdir_p!(hooks_dir)

    hook_paths =
      for {name, contents_fn} <- E.antigravity_hook_scripts() do
        path = Path.join(hooks_dir, name)
        File.write!(path, contents_fn.())
        File.chmod!(path, 0o755)
        %{"path" => path, "kind" => "hook"}
      end

    hooks_path = Path.join(root, ".agents/hooks.json")
    File.write!(hooks_path, Jason.encode!(E.antigravity_hooks_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, ".agents/mcp_config.json")

    File.write!(
      mcp_path,
      Jason.encode!(E.antigravity_mcp_config(project_root, opts), pretty: true) <> "\n"
    )

    agents_md = Path.join(root, "AGENTS.md")
    File.write!(agents_md, E.instructions_only_contents("antigravity-cli", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => rules_path, "kind" => "rules"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_md, "kind" => "instructions"}
      ] ++ hook_paths,
      [
        "Antigravity auto-discovers skills, rules, hooks, and MCP config under `.agents/`.",
        "Merge `.agents/mcp_config.json` and `.agents/hooks.json` into existing files rather than replacing them."
      ]
    )
  end
end
