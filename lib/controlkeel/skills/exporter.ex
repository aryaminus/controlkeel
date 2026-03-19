defmodule ControlKeel.Skills.Exporter do
  @moduledoc false

  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills
  alias ControlKeel.Skills.SkillExportPlan
  alias ControlKeel.Skills.SkillTarget

  @app_version to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")

  def export(target_id, project_root, opts \\ []) do
    with %SkillTarget{} = target <- SkillTarget.get(target_id),
         analysis <- Skills.validate(project_root, trust_project_skills: true),
         root <- export_root(project_root, target.id),
         {:ok, _removed} <- File.rm_rf(root),
         :ok <- File.mkdir_p(root),
         {:ok, writes, instructions} <-
           write_target(target, root, project_root, analysis.skills, opts) do
      :telemetry.execute(
        [:controlkeel, :skills, :exported],
        %{count: 1},
        %{
          target: target.id,
          scope: Keyword.get(opts, :scope, target.default_scope),
          project_root: Path.expand(project_root),
          skill_count: length(analysis.skills)
        }
      )

      {:ok,
       %SkillExportPlan{
         target: target.id,
         output_dir: root,
         scope: Keyword.get(opts, :scope, target.default_scope),
         writes: writes,
         instructions: instructions,
         native_available: target.native
       }}
    else
      nil -> {:error, :unknown_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_target(%SkillTarget{id: "open-standard"}, root, _project_root, skills, _opts) do
    write_skill_tree(skills, Path.join(root, "skills"))
    instructions = ["Portable skills exported to #{Path.join(root, "skills")}."]
    {:ok, [%{"path" => Path.join(root, "skills"), "kind" => "skills"}], instructions}
  end

  defp write_target(%SkillTarget{id: "codex"}, root, project_root, skills, _opts) do
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".codex/agents/controlkeel-operator.toml")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, codex_agent_contents(project_root, skills))

    instructions_path = Path.join(root, "AGENTS.md")
    File.write!(instructions_path, instructions_only_contents("codex", project_root))

    {:ok,
     [
       %{"path" => skill_root, "kind" => "skills"},
       %{"path" => agent_path, "kind" => "agent"},
       %{"path" => instructions_path, "kind" => "instructions"}
     ],
     [
       "Copy .agents/skills into your repo or user skill folder.",
       "Copy .codex/agents/controlkeel-operator.toml into your Codex agents directory if you want a preconfigured operator."
     ]}
  end

  defp write_target(%SkillTarget{id: "claude-standalone"}, root, project_root, skills, _opts) do
    skill_root = Path.join(root, ".claude/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".claude/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, claude_agent_contents(skills))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root), pretty: true) <> "\n")

    claude_md = Path.join(root, "CLAUDE.md")
    File.write!(claude_md, instructions_only_contents("claude", project_root))

    {:ok,
     [
       %{"path" => skill_root, "kind" => "skills"},
       %{"path" => agent_path, "kind" => "agent"},
       %{"path" => mcp_path, "kind" => "mcp"},
       %{"path" => claude_md, "kind" => "instructions"}
     ],
     [
       "Copy .claude/skills and .claude/agents into your project or home .claude directory.",
       "Merge the generated .mcp.json into Claude's MCP configuration if needed."
     ]}
  end

  defp write_target(%SkillTarget{id: "claude-plugin"}, root, project_root, skills, _opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, claude_agent_contents(skills))

    manifest_path = Path.join(root, ".claude-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(claude_plugin_manifest(), pretty: true) <> "\n")

    settings_path = Path.join(root, "settings.json")

    File.write!(
      settings_path,
      Jason.encode!(%{"agent" => "controlkeel-operator"}, pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root), pretty: true) <> "\n")

    {:ok,
     [
       %{"path" => manifest_path, "kind" => "manifest"},
       %{"path" => skill_root, "kind" => "skills"},
       %{"path" => agent_path, "kind" => "agent"},
       %{"path" => mcp_path, "kind" => "mcp"},
       %{"path" => settings_path, "kind" => "settings"}
     ], ["Run `claude --plugin-dir #{root}` to test the plugin locally."]}
  end

  defp write_target(%SkillTarget{id: "copilot-plugin"}, root, project_root, skills, _opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    manifest_path = Path.join(root, "plugin.json")
    File.write!(manifest_path, Jason.encode!(copilot_plugin_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root), pretty: true) <> "\n")

    {:ok,
     [
       %{"path" => manifest_path, "kind" => "manifest"},
       %{"path" => skill_root, "kind" => "skills"},
       %{"path" => agent_path, "kind" => "agent"},
       %{"path" => mcp_path, "kind" => "mcp"}
     ],
     [
       "Use this bundle as a local Copilot / VS Code plugin or publish it through your plugin workflow."
     ]}
  end

  defp write_target(%SkillTarget{id: "github-repo"}, root, project_root, skills, _opts) do
    skill_root = Path.join(root, ".github/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".github/agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    github_mcp = Path.join(root, ".github/mcp.json")
    File.write!(github_mcp, Jason.encode!(mcp_payload(project_root), pretty: true) <> "\n")

    vscode_mcp = Path.join(root, ".vscode/mcp.json")
    File.mkdir_p!(Path.dirname(vscode_mcp))
    File.write!(vscode_mcp, Jason.encode!(mcp_payload(project_root), pretty: true) <> "\n")

    instructions_path = Path.join(root, ".github/copilot-instructions.md")
    File.mkdir_p!(Path.dirname(instructions_path))
    File.write!(instructions_path, instructions_only_contents("copilot", project_root))

    {:ok,
     [
       %{"path" => skill_root, "kind" => "skills"},
       %{"path" => agent_path, "kind" => "agent"},
       %{"path" => github_mcp, "kind" => "mcp"},
       %{"path" => vscode_mcp, "kind" => "mcp"},
       %{"path" => instructions_path, "kind" => "instructions"}
     ],
     [
       "Copy the .github and .vscode folders into your repository root.",
       "VS Code and Copilot can then discover the skills, custom agent, and MCP server config from the repo."
     ]}
  end

  defp write_target(%SkillTarget{id: "instructions-only"}, root, project_root, _skills, _opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("agents", project_root))

    claude_path = Path.join(root, "CLAUDE.md")
    File.write!(claude_path, instructions_only_contents("claude", project_root))

    copilot_path = Path.join(root, "copilot-instructions.md")
    File.write!(copilot_path, instructions_only_contents("copilot", project_root))

    {:ok,
     [
       %{"path" => agents_path, "kind" => "instructions"},
       %{"path" => claude_path, "kind" => "instructions"},
       %{"path" => copilot_path, "kind" => "instructions"}
     ], ["Use these snippets with MCP-only tools that do not support native skills or plugins."]}
  end

  defp write_skill_tree(skills, destination_root) do
    File.mkdir_p!(destination_root)

    Enum.each(skills, fn skill ->
      destination = Path.join(destination_root, skill.name)

      unless same_path?(skill.skill_dir, destination) do
        File.rm_rf!(destination)
        File.cp_r!(skill.skill_dir, destination)
      end
    end)
  end

  defp export_root(project_root, target) do
    Path.join(Path.expand(project_root), "controlkeel/dist/#{target}")
  end

  defp mcp_payload(project_root) do
    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "command" => mcp_command(project_root),
          "args" => mcp_args(project_root)
        }
      }
    }
  end

  defp mcp_command(project_root) do
    wrapper = ProjectBinding.mcp_wrapper_path(project_root)
    if File.exists?(wrapper), do: wrapper, else: "controlkeel"
  end

  defp mcp_args(project_root) do
    wrapper = ProjectBinding.mcp_wrapper_path(project_root)

    if File.exists?(wrapper) do
      []
    else
      ["mcp", "--project-root", Path.expand(project_root)]
    end
  end

  defp claude_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, subagents, and MCP bridge.",
      "version" => @app_version,
      "author" => %{"name" => "ControlKeel"},
      "license" => "Apache-2.0"
    }
  end

  defp copilot_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, agents, and MCP bridge.",
      "version" => @app_version,
      "skills" => "skills",
      "agents" => "agents",
      "mcpServers" => ".mcp.json",
      "tags" => ["governance", "security", "skills"]
    }
  end

  defp codex_agent_contents(project_root, skills) do
    """
    name = "controlkeel-operator"
    description = "Operate inside a ControlKeel-governed project with CK skills and MCP tools."
    model = "gpt-5.4-mini"

    [mcp]
    servers = ["controlkeel"]

    [skills]
    preload = [#{Enum.map_join(skills, ", ", &~s("#{&1.name}"))}]

    [context]
    project_root = "#{Path.expand(project_root)}"
    """
  end

  defp claude_agent_contents(skills) do
    """
    ---
    description: Use ControlKeel governance, findings, proofs, budgets, and benchmarks inside this project.
    tools: ["*"]
    mcpServers: ["controlkeel"]
    skills:
    #{Enum.map_join(skills, "\n", &"  - #{&1.name}")}
    ---

    # ControlKeel Operator

    You are the specialized operator for ControlKeel-governed work.

    Always begin with the `controlkeel-governance` skill and then load domain-specific skills as needed.
    Surface findings clearly, respect blocks, and use CK proof, benchmark, and budget tooling before declaring work complete.
    """
  end

  defp copilot_agent_contents(skills) do
    """
    ---
    description: Operate inside a ControlKeel-governed repository and use CK skills and MCP tools proactively.
    tools: ["*"]
    ---

    # ControlKeel Operator

    Start by loading the `controlkeel-governance` skill. Use these supporting skills when relevant:

    #{Enum.map_join(skills, "\n", &"- `#{&1.name}` — #{&1.description}")}

    Prefer CK MCP tools for validation, routing, findings, budgets, proofs, and benchmark control.
    """
  end

  defp instructions_only_contents(target, project_root) do
    """
    # ControlKeel Companion Instructions

    This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, and routing.

    Project root: `#{Path.expand(project_root)}`
    Target: `#{target}`

    Required workflow:
    1. Call `ck_context` at the start of a task.
    2. Call `ck_validate` before writing code, config, shell, or deploy content.
    3. Record any human-review issue with `ck_finding`.
    4. Check `ck_budget` before expensive model or multi-agent work.
    5. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.
    """
  end

  defp same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end
end
