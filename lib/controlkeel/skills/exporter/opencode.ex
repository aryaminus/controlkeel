defmodule ControlKeel.Skills.Exporter.OpenCode do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, compat_skill_root)

    plugin_path = Path.join(root, ".opencode/plugins/controlkeel-governance.ts")
    File.mkdir_p!(Path.dirname(plugin_path))
    File.write!(plugin_path, E.opencode_plugin_contents())

    agent_path = Path.join(root, ".opencode/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.opencode_agent_contents(skills))

    command_path = Path.join(root, ".opencode/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.opencode_command_contents())

    submit_command_path = Path.join(root, ".opencode/commands/controlkeel-submit-plan.md")
    File.mkdir_p!(Path.dirname(submit_command_path))
    File.write!(submit_command_path, E.opencode_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".opencode/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("OpenCode", "opencode", ".opencode/annotate.md")
    )

    last_command_path = Path.join(root, ".opencode/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("OpenCode"))

    mcp_path = Path.join(root, ".opencode/mcp.json")

    File.write!(
      mcp_path,
      Jason.encode!(E.opencode_mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    package_json_path = Path.join(root, "package.json")

    File.write!(
      package_json_path,
      Jason.encode!(E.opencode_package_manifest(), pretty: true) <> "\n"
    )

    package_entry_path = Path.join(root, "index.js")
    File.write!(package_entry_path, E.opencode_package_entry_contents())

    package_readme_path = Path.join(root, "README.md")
    File.write!(package_readme_path, E.opencode_package_readme_contents())

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("opencode", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => plugin_path, "kind" => "plugin"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => package_entry_path, "kind" => "runtime"},
        %{"path" => package_readme_path, "kind" => "instructions"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.agents/skills/` into your project for OpenCode skill discovery.",
        "Copy `.opencode/plugins/` into your project's `.opencode/plugins/` directory (loaded automatically at startup).",
        "Copy `.opencode/agents/` into your project's `.opencode/agents/` directory for the governed review agent.",
        "Copy `.opencode/commands/` into your project's `.opencode/commands/` directory for the `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last` commands.",
        "Merge `.opencode/mcp.json` into your `opencode.json` under the `mcp` key.",
        "For direct npm plugin installs, add `\"plugin\": [\"@aryaminus/controlkeel-opencode\"]` to your `opencode.json`."
      ]
    )
  end
end
