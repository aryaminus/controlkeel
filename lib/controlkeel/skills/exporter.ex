defmodule ControlKeel.Skills.Exporter do
  @moduledoc false

  alias ControlKeel.CodexConfig
  alias ControlKeel.Distribution
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills
  alias ControlKeel.Skills.SkillExportPlan
  alias ControlKeel.Skills.SkillTarget

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

  defp write_target(%SkillTarget{id: "open-standard"}, root, project_root, skills, opts) do
    write_skill_tree(skills, Path.join(root, "skills"))
    instructions = ["Portable skills exported to #{Path.join(root, "skills")}."]

    with_common_assets(
      root,
      project_root,
      opts,
      [%{"path" => Path.join(root, "skills"), "kind" => "skills"}],
      instructions
    )
  end

  defp write_target(%SkillTarget{id: "codex"}, root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    native_skill_root = Path.join(root, ".codex/skills")
    write_skill_tree(skills, compat_skill_root)
    write_skill_tree(skills, native_skill_root)

    config_path = Path.join(root, ".codex/config.toml")
    File.mkdir_p!(Path.dirname(config_path))

    {:ok, _} =
      CodexConfig.write(config_path, %{
        command: mcp_command(project_root, opts),
        args: mcp_args(project_root, opts)
      })

    agent_path = Path.join(root, ".codex/agents/controlkeel-operator.toml")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, codex_agent_contents(project_root, skills, opts))

    diff_command_path = Path.join(root, ".codex/commands/controlkeel-diff-review.md")
    File.mkdir_p!(Path.dirname(diff_command_path))
    File.write!(diff_command_path, codex_diff_review_command_contents())

    completion_command_path = Path.join(root, ".codex/commands/controlkeel-completion-review.md")
    File.mkdir_p!(Path.dirname(completion_command_path))
    File.write!(completion_command_path, codex_completion_review_command_contents())

    review_command_path = Path.join(root, ".codex/commands/controlkeel-review.md")
    File.write!(review_command_path, codex_review_command_contents())

    annotate_command_path = Path.join(root, ".codex/commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, codex_annotate_command_contents())

    last_command_path = Path.join(root, ".codex/commands/controlkeel-last.md")
    File.write!(last_command_path, codex_last_command_contents())

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    instructions_path = Path.join(root, "AGENTS.md")
    File.write!(instructions_path, instructions_only_contents("codex", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => native_skill_root, "kind" => "skills"},
        %{"path" => config_path, "kind" => "config"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => diff_command_path, "kind" => "command"},
        %{"path" => completion_command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Use .codex/skills for Codex-native skill loading and keep .agents/skills for open-standard compatibility.",
        "Use .codex/config.toml to register the ControlKeel MCP server and operator role with Codex.",
        "Copy .codex/agents/controlkeel-operator.toml into your Codex agents directory if you want a preconfigured operator.",
        "Use .codex/commands/ for browser-reviewed review, annotate, last, diff, and completion approval flows.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "codex-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    diff_command_path = Path.join(root, "commands/controlkeel-diff-review.md")
    File.mkdir_p!(Path.dirname(diff_command_path))
    File.write!(diff_command_path, codex_diff_review_command_contents())

    completion_command_path = Path.join(root, "commands/controlkeel-completion-review.md")
    File.mkdir_p!(Path.dirname(completion_command_path))
    File.write!(completion_command_path, codex_completion_review_command_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.write!(review_command_path, codex_review_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, codex_annotate_command_contents())

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, codex_last_command_contents())

    manifest_path = Path.join(root, ".codex-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(codex_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks.json")
    File.write!(hooks_path, Jason.encode!(empty_hooks_manifest(), pretty: true) <> "\n")

    app_path = Path.join(root, ".app.json")
    File.write!(app_path, Jason.encode!(codex_app_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    marketplace_path = Path.join(root, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      marketplace_path,
      Jason.encode!(codex_marketplace_manifest(), pretty: true) <> "\n"
    )

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => diff_command_path, "kind" => "command"},
        %{"path" => completion_command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => app_path, "kind" => "app"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => marketplace_path, "kind" => "marketplace"}
      ],
      [
        "Install this bundle as a Codex plugin or add it to your repo-local Codex marketplace.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "claude-standalone"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".claude/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".claude/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, claude_agent_contents(skills))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    claude_md = Path.join(root, "CLAUDE.md")
    File.write!(claude_md, instructions_only_contents("claude", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => claude_md, "kind" => "instructions"}
      ],
      [
        "Copy .claude/skills and .claude/agents into your project or home .claude directory.",
        "Merge the generated .mcp.json into Claude's MCP configuration if needed."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "claude-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, claude_agent_contents(skills))

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, host_review_command_contents("Claude Code", "claude-code"))

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Claude Code", "claude-code", ".claude/annotate.md")
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Claude Code"))

    manifest_path = Path.join(root, ".claude-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(claude_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))

    File.write!(
      hooks_path,
      Jason.encode!(claude_hooks_manifest(), pretty: true) <> "\n"
    )

    shell_hook_path = Path.join(root, "hooks/controlkeel-review.sh")
    File.write!(shell_hook_path, review_bridge_shell_contents("claude-code"))
    File.chmod!(shell_hook_path, 0o755)

    powershell_hook_path = Path.join(root, "hooks/controlkeel-review.ps1")
    File.write!(powershell_hook_path, review_bridge_powershell_contents("claude-code"))

    manual_hook_path = Path.join(root, "hooks/manual-settings.json")
    File.write!(manual_hook_path, Jason.encode!(claude_manual_settings(), pretty: true) <> "\n")

    settings_path = Path.join(root, "settings.json")

    File.write!(
      settings_path,
      Jason.encode!(%{"agent" => "controlkeel-operator"}, pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => powershell_hook_path, "kind" => "hook"},
        %{"path" => manual_hook_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => settings_path, "kind" => "settings"}
      ],
      [
        "Run `claude --plugin-dir #{root}` to test the plugin locally.",
        "The plugin also ships `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last` command prompts for explicit governed review passes.",
        "Use hooks/manual-settings.json when you prefer Claude's manual hook installation path.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "cline-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".cline/skills")
    write_skill_tree(skills, skill_root)

    mcp_path = Path.join(root, ".cline/data/settings/cline_mcp_settings.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    rule_path = Path.join(root, ".clinerules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, cline_rule_contents())

    workflow_path = Path.join(root, ".clinerules/workflows/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, cline_workflow_contents())

    command_path = Path.join(root, ".cline/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, cline_command_contents())

    submit_command_path = Path.join(root, ".cline/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, cline_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".cline/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Cline", "cline", ".cline/annotate.md")
    )

    last_command_path = Path.join(root, ".cline/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Cline"))

    pretool_hook_path = Path.join(root, ".cline/hooks/PreToolUse/controlkeel-review.sh")
    File.mkdir_p!(Path.dirname(pretool_hook_path))
    File.write!(pretool_hook_path, review_bridge_shell_contents("cline"))
    File.chmod!(pretool_hook_path, 0o755)

    taskstart_hook_path = Path.join(root, ".cline/hooks/TaskStart/controlkeel-context.sh")
    File.mkdir_p!(Path.dirname(taskstart_hook_path))
    File.write!(taskstart_hook_path, cline_taskstart_hook_contents())
    File.chmod!(taskstart_hook_path, 0o755)

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("cline", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => workflow_path, "kind" => "workflow"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => pretool_hook_path, "kind" => "hook"},
        %{"path" => taskstart_hook_path, "kind" => "hook"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.cline/skills` into your project or `~/.cline/skills`.",
        "Keep `.clinerules/`, `.cline/commands`, and `.cline/hooks` in the repo so Cline loads ControlKeel rules, workflows, commands, and hooks for the governed workspace.",
        "Merge `.cline/data/settings/cline_mcp_settings.json` into Cline MCP settings (`~/.cline/data/settings/cline_mcp_settings.json` or `$CLINE_DIR/data/settings/cline_mcp_settings.json`)."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "cursor-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".cursor/rules/controlkeel.mdc")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, cursor_rule_contents())

    command_path = Path.join(root, ".cursor/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, cursor_command_contents())

    submit_command_path = Path.join(root, ".cursor/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, cursor_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".cursor/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Cursor", "cursor", ".cursor/annotate.md")
    )

    last_command_path = Path.join(root, ".cursor/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Cursor"))

    background_agent_path = Path.join(root, ".cursor/background-agents/controlkeel.md")
    File.mkdir_p!(Path.dirname(background_agent_path))
    File.write!(background_agent_path, cursor_background_agent_contents())

    mcp_path = Path.join(root, ".cursor/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("cursor", project_root, opts))

    with_common_assets(
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
        %{"path" => background_agent_path, "kind" => "workflow"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.cursor/rules`, `.cursor/commands`, and `.cursor/background-agents` in the repo so Cursor loads ControlKeel guidance, review commands, and background-agent handoff notes.",
        "Use .cursor/mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "windsurf-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".windsurf/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, windsurf_rule_contents())

    command_path = Path.join(root, ".windsurf/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, windsurf_command_contents())

    submit_command_path = Path.join(root, ".windsurf/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      host_submit_plan_command_contents("Windsurf", "windsurf", ".windsurf/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".windsurf/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Windsurf", "windsurf", ".windsurf/annotate.md")
    )

    last_command_path = Path.join(root, ".windsurf/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Windsurf"))

    workflow_path = Path.join(root, ".windsurf/workflows/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, windsurf_workflow_contents())

    workspace_hooks_path = Path.join(root, ".windsurf/hooks.json")

    File.write!(
      workspace_hooks_path,
      Jason.encode!(windsurf_workspace_hook_manifest(), pretty: true) <> "\n"
    )

    hook_path = Path.join(root, ".windsurf/hooks/controlkeel-review.json")
    File.mkdir_p!(Path.dirname(hook_path))
    File.write!(hook_path, Jason.encode!(windsurf_hook_manifest(), pretty: true) <> "\n")

    hook_script_path = Path.join(root, ".windsurf/hooks/controlkeel-review.sh")
    File.write!(hook_script_path, review_bridge_shell_contents("windsurf"))
    File.chmod!(hook_script_path, 0o755)

    mcp_path = Path.join(root, ".windsurf/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("windsurf", project_root, opts))

    with_common_assets(
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
        %{"path" => workflow_path, "kind" => "workflow"},
        %{"path" => workspace_hooks_path, "kind" => "hooks"},
        %{"path" => hook_path, "kind" => "hook"},
        %{"path" => hook_script_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.windsurf/rules`, `.windsurf/workflows`, and `.windsurf/hooks` in the repo so Windsurf loads ControlKeel guidance, Cascade workflows, and hook-native review interception.",
        "Use `.windsurf/hooks.json` as the canonical workspace hook config; the per-hook JSON and shell script are included as portable review assets.",
        "Use .windsurf/mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "continue-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".continue/skills")
    write_skill_tree(skills, skill_root)

    prompt_path = Path.join(root, ".continue/prompts/controlkeel.md")
    File.mkdir_p!(Path.dirname(prompt_path))
    File.write!(prompt_path, continue_prompt_contents())

    plan_prompt_path = Path.join(root, ".continue/prompts/controlkeel-plan.md")
    File.write!(plan_prompt_path, continue_plan_prompt_contents())

    review_prompt_path = Path.join(root, ".continue/prompts/controlkeel-review.md")
    File.write!(review_prompt_path, continue_review_prompt_contents())

    headless_prompt_path = Path.join(root, ".continue/prompts/controlkeel-headless.md")
    File.write!(headless_prompt_path, continue_headless_prompt_contents())

    command_path = Path.join(root, ".continue/commands/controlkeel-review.prompt")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, continue_command_contents())

    submit_command_path = Path.join(root, ".continue/commands/controlkeel-submit-plan.prompt")
    File.write!(submit_command_path, continue_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".continue/commands/controlkeel-annotate.prompt")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Continue", "continue", ".continue/annotate.md")
    )

    last_command_path = Path.join(root, ".continue/commands/controlkeel-last.prompt")
    File.write!(last_command_path, host_last_command_contents("Continue"))

    config_path = Path.join(root, ".continue/mcp.json")
    File.write!(config_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    mcp_server_path = Path.join(root, ".continue/mcpServers/controlkeel.yaml")
    File.mkdir_p!(Path.dirname(mcp_server_path))
    File.write!(mcp_server_path, continue_mcp_server_contents(project_root, opts))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("continue", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => prompt_path, "kind" => "instructions"},
        %{"path" => plan_prompt_path, "kind" => "instructions"},
        %{"path" => review_prompt_path, "kind" => "instructions"},
        %{"path" => headless_prompt_path, "kind" => "instructions"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "mcp"},
        %{"path" => mcp_server_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.continue/skills`, `.continue/prompts`, and `.continue/commands` into the repo for Continue-native plan, review, and headless guidance.",
        "Use `.continue/mcpServers/controlkeel.yaml` for MCP registration or `.continue/mcp.json` as the portable fallback."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "letta-code-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    settings_path = Path.join(root, ".letta/settings.json")
    File.mkdir_p!(Path.dirname(settings_path))
    File.write!(settings_path, Jason.encode!(letta_settings_manifest(), pretty: true) <> "\n")

    local_settings_example_path = Path.join(root, ".letta/settings.local.example.json")

    File.write!(
      local_settings_example_path,
      Jason.encode!(letta_local_settings_example_manifest(), pretty: true) <> "\n"
    )

    hooks_root = Path.join(root, ".letta/hooks")
    File.mkdir_p!(hooks_root)

    findings_hook_path = Path.join(hooks_root, "controlkeel-findings.sh")
    File.write!(findings_hook_path, letta_findings_hook_contents())
    File.chmod!(findings_hook_path, 0o755)

    session_hook_path = Path.join(hooks_root, "controlkeel-session-start.sh")
    File.write!(session_hook_path, letta_session_start_hook_contents())
    File.chmod!(session_hook_path, 0o755)

    mcp_helper_path = Path.join(root, ".letta/controlkeel-mcp.sh")
    File.write!(mcp_helper_path, letta_mcp_helper_contents(project_root, opts))
    File.chmod!(mcp_helper_path, 0o755)

    readme_path = Path.join(root, ".letta/README.md")
    File.write!(readme_path, letta_readme_contents(project_root, opts))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("letta-code", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => settings_path, "kind" => "settings"},
        %{"path" => local_settings_example_path, "kind" => "settings"},
        %{"path" => findings_hook_path, "kind" => "hook"},
        %{"path" => session_hook_path, "kind" => "hook"},
        %{"path" => mcp_helper_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.agents/skills` in the repo so Letta discovers ControlKeel skills through its primary project skill path.",
        "Commit `.letta/settings.json` for shared hook defaults; keep personal overrides in `.letta/settings.local.json` based on the included example file.",
        "Register ControlKeel with Letta through `/mcp add --transport stdio controlkeel ./.letta/controlkeel-mcp.sh` or the hosted HTTP variant described in `.letta/README.md`.",
        "Use `letta -p` for headless runs and `letta server` for remote/listener workflows; the included README documents both without claiming a CK-owned runtime."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "pi-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    command_path = Path.join(root, ".pi/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, pi_command_contents())

    submit_command_path = Path.join(root, ".pi/commands/controlkeel-submit-plan.md")
    File.mkdir_p!(Path.dirname(submit_command_path))
    File.write!(submit_command_path, pi_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".pi/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Pi", "pi", ".pi/annotate.md")
    )

    last_command_path = Path.join(root, ".pi/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Pi"))

    phase_config_path = Path.join(root, ".pi/controlkeel.json")
    File.mkdir_p!(Path.dirname(phase_config_path))

    File.write!(
      phase_config_path,
      Jason.encode!(pi_phase_manifest(project_root, opts), pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".pi/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    extension_path = Path.join(root, "pi-extension.json")

    File.write!(
      extension_path,
      Jason.encode!(pi_extension_manifest(project_root, opts), pretty: true) <> "\n"
    )

    package_json_path = Path.join(root, "package.json")
    File.write!(package_json_path, Jason.encode!(pi_package_manifest(), pretty: true) <> "\n")

    package_readme_path = Path.join(root, "README.md")
    File.write!(package_readme_path, pi_package_readme_contents())

    instructions_path = Path.join(root, "PI.md")
    File.write!(instructions_path, instructions_only_contents("pi", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => phase_config_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => extension_path, "kind" => "plugin"},
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => package_readme_path, "kind" => "instructions"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Keep `.pi/controlkeel.json` and `.pi/commands/` in the repo so Pi can switch between planning and execution with a governed plan file.",
        "Use `.pi/mcp.json` for local stdio MCP and `.mcp.hosted.json` as the hosted MCP template.",
        "Install `pi-extension.json` into Pi's local extension directory when a standalone extension link flow is preferred.",
        "For direct npm installs on Pi builds that support extension packages, use `pi install npm:@aryaminus/controlkeel-pi-extension`."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "roo-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".roo/skills")
    write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".roo/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, roo_rule_contents())

    command_path = Path.join(root, ".roo/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, roo_command_contents())

    submit_command_path = Path.join(root, ".roo/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, roo_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".roo/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Roo Code", "roo-code", ".roo/annotate.md")
    )

    last_command_path = Path.join(root, ".roo/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Roo Code"))

    guidance_path = Path.join(root, ".roo/guidance/controlkeel.md")
    File.mkdir_p!(Path.dirname(guidance_path))
    File.write!(guidance_path, roo_guidance_contents())

    cloud_guidance_path = Path.join(root, ".roo/guidance/controlkeel-cloud-agent.md")
    File.write!(cloud_guidance_path, roo_cloud_guidance_contents())

    modes_path = Path.join(root, ".roomodes")
    File.write!(modes_path, roo_modes_contents())

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("roo-code", project_root, opts))

    with_common_assets(
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

  defp write_target(%SkillTarget{id: "goose-native"}, root, project_root, _skills, opts) do
    hints_path = Path.join(root, ".goosehints")
    File.write!(hints_path, goose_hints_contents())

    workflow_path = Path.join(root, "goose/workflow_recipes/controlkeel-review.yaml")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, goose_workflow_contents())

    command_path = Path.join(root, "goose/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, goose_command_contents())

    submit_command_path = Path.join(root, "goose/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, goose_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "goose/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Goose", "goose", "goose/annotate.md")
    )

    last_command_path = Path.join(root, "goose/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Goose"))

    extension_path = Path.join(root, "goose/controlkeel-extension.yaml")
    File.mkdir_p!(Path.dirname(extension_path))
    File.write!(extension_path, goose_extension_yaml(project_root, opts))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("goose", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
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

  defp write_target(%SkillTarget{id: "hermes-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".hermes/skills")
    write_skill_tree(skills, skill_root)

    mcp_path = Path.join(root, ".hermes/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("hermes-agent", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.hermes/skills` into your Hermes config directory or project workspace.",
        "Merge `.hermes/mcp.json` into Hermes MCP configuration and keep `AGENTS.md` in the governed repo."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "openclaw-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    config_path = Path.join(root, ".openclaw/openclaw.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(openclaw_config_snippet(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("openclaw", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `skills/` into your OpenClaw workspace or managed skills directory.",
        "Merge `.openclaw/openclaw.json` into OpenClaw settings to register the ControlKeel MCP server and skill path."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "openclaw-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    manifest_path = Path.join(root, "openclaw.plugin.json")
    File.write!(manifest_path, Jason.encode!(openclaw_plugin_manifest(), pretty: true) <> "\n")

    package_json = Path.join(root, "package.json")

    File.write!(
      package_json,
      Jason.encode!(
        %{"name" => "controlkeel-openclaw", "private" => true, "version" => app_version()},
        pretty: true
      ) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("openclaw", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => package_json, "kind" => "package"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Install this folder with `openclaw plugins install <path>` or unpack it into a local plugin workspace.",
        "Use `AGENTS.md` in the governed repo for shared ControlKeel context."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "copilot-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    command_path = Path.join(root, "commands/controlkeel-plan-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, copilot_plan_review_command_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.write!(review_command_path, host_review_command_contents("GitHub Copilot", "copilot"))

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents(
        "GitHub Copilot",
        "copilot",
        ".github/controlkeel-annotate.md"
      )
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("GitHub Copilot"))

    manifest_path = Path.join(root, "plugin.json")
    File.write!(manifest_path, Jason.encode!(copilot_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks.json")
    File.write!(hooks_path, Jason.encode!(copilot_hooks_manifest(), pretty: true) <> "\n")

    shell_hook_path = Path.join(root, "bin/controlkeel-review.sh")
    File.mkdir_p!(Path.dirname(shell_hook_path))
    File.write!(shell_hook_path, review_bridge_shell_contents("copilot"))
    File.chmod!(shell_hook_path, 0o755)

    powershell_hook_path = Path.join(root, "bin/controlkeel-review.ps1")
    File.write!(powershell_hook_path, review_bridge_powershell_contents("copilot"))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => powershell_hook_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"}
      ],
      [
        "Use this bundle as a local Copilot / VS Code plugin or publish it through your plugin workflow.",
        "The plugin ships `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last` command prompts alongside plan-mode interception.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "augment-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, augment_agent_contents(skills))

    command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, augment_review_command_contents())

    submit_command_path = Path.join(root, "commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, augment_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Augment", "augment", ".augment/annotate.md")
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Augment"))

    rule_path = Path.join(root, "rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, augment_rule_contents())

    manifest_path = Path.join(root, ".augment-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(augment_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))
    File.write!(hooks_path, Jason.encode!(augment_hooks_manifest(), pretty: true) <> "\n")

    shell_hook_path = Path.join(root, "hooks/controlkeel-review.sh")
    File.write!(shell_hook_path, review_bridge_shell_contents("augment"))
    File.chmod!(shell_hook_path, 0o755)

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    readme_path = Path.join(root, "README.md")
    File.write!(readme_path, augment_plugin_readme_contents())

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Run `auggie --plugin-dir #{root}` to test the plugin locally.",
        "The plugin ships hook-native review interception plus the `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last` commands.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "github-repo"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".github/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".github/agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    command_path = Path.join(root, ".github/commands/controlkeel-plan-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, copilot_plan_review_command_contents())

    review_command_path = Path.join(root, ".github/commands/controlkeel-review.md")
    File.write!(review_command_path, host_review_command_contents("GitHub Copilot", "copilot"))

    annotate_command_path = Path.join(root, ".github/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents(
        "GitHub Copilot",
        "copilot",
        ".github/controlkeel-annotate.md"
      )
    )

    last_command_path = Path.join(root, ".github/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("GitHub Copilot"))

    github_mcp = Path.join(root, ".github/mcp.json")
    File.write!(github_mcp, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    vscode_mcp = Path.join(root, ".vscode/mcp.json")
    File.mkdir_p!(Path.dirname(vscode_mcp))
    File.write!(vscode_mcp, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    vscode_extensions = Path.join(root, ".vscode/extensions.json")

    File.write!(
      vscode_extensions,
      Jason.encode!(vscode_extensions_manifest(), pretty: true) <> "\n"
    )

    instructions_path = Path.join(root, ".github/copilot-instructions.md")
    File.mkdir_p!(Path.dirname(instructions_path))
    File.write!(instructions_path, instructions_only_contents("copilot", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => github_mcp, "kind" => "mcp"},
        %{"path" => vscode_mcp, "kind" => "mcp"},
        %{"path" => vscode_extensions, "kind" => "settings"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Copy the .github and .vscode folders into your repository root.",
        "VS Code and Copilot can then discover the skills, custom agent, command prompts, and MCP server config from the repo."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "vscode-companion"}, root, _project_root, _skills, _opts) do
    extension_root = Path.join(root, "extension")
    File.mkdir_p!(extension_root)

    package_json_path = Path.join(extension_root, "package.json")

    File.write!(
      package_json_path,
      Jason.encode!(vscode_companion_manifest(), pretty: true) <> "\n"
    )

    extension_js_path = Path.join(extension_root, "extension.js")
    File.write!(extension_js_path, vscode_companion_extension_contents())

    readme_path = Path.join(extension_root, "README.md")
    File.write!(readme_path, vscode_companion_readme_contents())

    with_common_assets(
      root,
      root,
      [],
      [
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => extension_js_path, "kind" => "runtime"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Zip the `extension/` directory as a `.vsix` when publishing the VS Code companion.",
        "The companion opens ControlKeel review URLs inside a VS Code webview and injects terminal routing env vars."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "droid-bundle"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".factory/skills")
    write_skill_tree(skills, skill_root)

    droid_path = Path.join(root, ".factory/droids/controlkeel.md")
    File.mkdir_p!(Path.dirname(droid_path))
    File.write!(droid_path, droid_profile_contents())

    review_command_path = Path.join(root, ".factory/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, droid_review_command_contents())

    submit_command_path = Path.join(root, ".factory/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, droid_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".factory/commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, droid_annotate_command_contents())

    last_command_path = Path.join(root, ".factory/commands/controlkeel-last.md")
    File.write!(last_command_path, droid_last_command_contents())

    mcp_path = Path.join(root, ".factory/mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("droid", project_root, opts))

    with_common_assets(
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

  defp write_target(%SkillTarget{id: "droid-plugin"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    droid_path = Path.join(root, "droids/controlkeel.md")
    File.mkdir_p!(Path.dirname(droid_path))
    File.write!(droid_path, droid_profile_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, droid_review_command_contents())

    submit_command_path = Path.join(root, "commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, droid_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, droid_annotate_command_contents())

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, droid_last_command_contents())

    manifest_path = Path.join(root, ".factory-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(droid_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))
    File.write!(hooks_path, Jason.encode!(empty_hooks_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, "mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    readme_path = Path.join(root, "README.md")
    File.write!(readme_path, droid_plugin_readme_contents())

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => droid_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Use `controlkeel plugin export droid` to produce this shareable Factory plugin bundle.",
        "Install it through Droid's plugin marketplace flow, for example by adding the exported directory as a local marketplace and then installing `controlkeel@droid-plugin`."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "forge-acp"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    write_skill_tree(skills, skill_root)

    acp_path = Path.join(root, ".forge/controlkeel.acp.json")
    File.mkdir_p!(Path.dirname(acp_path))

    File.write!(
      acp_path,
      Jason.encode!(forge_acp_manifest(project_root, opts), pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("forge", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => acp_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Use `.forge/controlkeel.acp.json` when Forge can open an ACP session; keep `.mcp.json` as the portable fallback."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "opencode-native"}, root, project_root, _skills, opts) do
    # 1. Governance plugin — hooks into OpenCode's plugin lifecycle
    plugin_path = Path.join(root, ".opencode/plugins/controlkeel-governance.ts")
    File.mkdir_p!(Path.dirname(plugin_path))
    File.write!(plugin_path, opencode_plugin_contents())

    # 2. Agent profile — a governed review agent
    agent_path = Path.join(root, ".opencode/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, opencode_agent_contents())

    # 3. Command template — /controlkeel-review
    command_path = Path.join(root, ".opencode/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, opencode_command_contents())

    submit_command_path = Path.join(root, ".opencode/commands/controlkeel-submit-plan.md")
    File.mkdir_p!(Path.dirname(submit_command_path))
    File.write!(submit_command_path, opencode_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".opencode/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("OpenCode", "opencode", ".opencode/annotate.md")
    )

    last_command_path = Path.join(root, ".opencode/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("OpenCode"))

    # 4. MCP config — opencode-format mcp.json
    mcp_path = Path.join(root, ".opencode/mcp.json")

    File.write!(
      mcp_path,
      Jason.encode!(opencode_mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    package_json_path = Path.join(root, "package.json")

    File.write!(
      package_json_path,
      Jason.encode!(opencode_package_manifest(), pretty: true) <> "\n"
    )

    package_entry_path = Path.join(root, "index.js")
    File.write!(package_entry_path, opencode_package_entry_contents())

    package_readme_path = Path.join(root, "README.md")
    File.write!(package_readme_path, opencode_package_readme_contents())

    # 5. Instructions
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("opencode", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
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
        "Copy `.opencode/plugins/` into your project's `.opencode/plugins/` directory (loaded automatically at startup).",
        "Copy `.opencode/agents/` into your project's `.opencode/agents/` directory for the governed review agent.",
        "Copy `.opencode/commands/` into your project's `.opencode/commands/` directory for the `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last` commands.",
        "Merge `.opencode/mcp.json` into your `opencode.json` under the `mcp` key.",
        "For direct npm plugin installs, add `\"plugin\": [\"@aryaminus/controlkeel-opencode\"]` to your `opencode.json`."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "gemini-cli-native"}, root, project_root, _skills, opts) do
    # 1. Extension manifest
    manifest_path = Path.join(root, "gemini-extension.json")

    File.write!(
      manifest_path,
      Jason.encode!(gemini_extension_manifest(project_root, opts), pretty: true) <> "\n"
    )

    # 2. Custom command — /controlkeel:review
    command_path = Path.join(root, ".gemini/commands/controlkeel/review.toml")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, gemini_command_contents())

    submit_plan_command_path = Path.join(root, ".gemini/commands/controlkeel/submit-plan.toml")
    File.write!(submit_plan_command_path, gemini_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".gemini/commands/controlkeel/annotate.toml")
    File.write!(annotate_command_path, gemini_annotate_command_contents())

    last_command_path = Path.join(root, ".gemini/commands/controlkeel/last.toml")
    File.write!(last_command_path, gemini_last_command_contents())

    # 3. Agent skill
    skill_path = Path.join(root, "skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(skill_path))
    File.write!(skill_path, gemini_skill_contents())

    # 4. GEMINI.md context
    gemini_md_path = Path.join(root, "GEMINI.md")
    File.write!(gemini_md_path, instructions_only_contents("gemini-cli", project_root, opts))

    extension_readme_path = Path.join(root, "README.md")
    File.write!(extension_readme_path, gemini_extension_readme_contents())

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "settings"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_plan_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => skill_path, "kind" => "skills"},
        %{"path" => gemini_md_path, "kind" => "instructions"},
        %{"path" => extension_readme_path, "kind" => "instructions"}
      ],
      [
        "Install with `gemini extensions link .` or copy the directory into `~/.gemini/extensions/controlkeel/`.",
        "The `/controlkeel:review`, `/controlkeel:submit-plan`, `/controlkeel:annotate`, and `/controlkeel:last` commands plus the `controlkeel-governance` skill are auto-discovered."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "kiro-native"}, root, project_root, _skills, opts) do
    # 1. Agent Hook — post-tool validation
    hook_path = Path.join(root, ".kiro/hooks/controlkeel-validate.json")
    File.mkdir_p!(Path.dirname(hook_path))
    File.write!(hook_path, Jason.encode!(kiro_hook_spec(), pretty: true) <> "\n")

    review_hook_path = Path.join(root, ".kiro/hooks/controlkeel-review.json")
    File.write!(review_hook_path, Jason.encode!(kiro_review_hook_spec(), pretty: true) <> "\n")

    # 2. Steering file
    steering_path = Path.join(root, ".kiro/steering/controlkeel.md")
    File.mkdir_p!(Path.dirname(steering_path))
    File.write!(steering_path, kiro_steering_contents())

    tool_policy_path = Path.join(root, ".kiro/settings/controlkeel-tools.json")
    File.mkdir_p!(Path.dirname(tool_policy_path))

    File.write!(
      tool_policy_path,
      Jason.encode!(kiro_tool_policy_manifest(), pretty: true) <> "\n"
    )

    command_path = Path.join(root, ".kiro/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, kiro_command_contents())

    submit_command_path = Path.join(root, ".kiro/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      host_submit_plan_command_contents("Kiro", "kiro", ".kiro/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".kiro/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Kiro", "kiro", ".kiro/annotate.md")
    )

    last_command_path = Path.join(root, ".kiro/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Kiro"))

    # 3. MCP config
    mcp_path = Path.join(root, ".kiro/mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    # 4. Instructions
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("kiro", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => hook_path, "kind" => "hook"},
        %{"path" => review_hook_path, "kind" => "hook"},
        %{"path" => steering_path, "kind" => "instructions"},
        %{"path" => tool_policy_path, "kind" => "settings"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.kiro/hooks/` into your project root for Agent Hook auto-discovery and review interception.",
        "Copy `.kiro/steering/`, `.kiro/settings/`, and `.kiro/commands/` for governed agent behavioral guidance and tool controls.",
        "Merge `.kiro/mcp.json` into your Kiro MCP settings."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "kilo-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".kilo/skills")
    write_skill_tree(skills, skill_root)

    command_path = Path.join(root, ".kilo/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, kilo_command_contents())

    submit_command_path = Path.join(root, ".kilo/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      host_submit_plan_command_contents("Kilo Code", "kilo", ".kilo/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".kilo/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Kilo Code", "kilo", ".kilo/annotate.md")
    )

    last_command_path = Path.join(root, ".kilo/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Kilo Code"))

    config_path = Path.join(root, ".kilo/kilo.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(kilo_config_snippet(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("kilo", project_root, opts))

    with_common_assets(
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
        "Copy `.kilo/skills/` into your repo or `~/.kilo/skills/` for Kilo Agent Skills discovery.",
        "Copy `.kilo/commands/` into the project root so Kilo can expose `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last`.",
        "Merge `.kilo/kilo.json` into `kilo.json` or `~/.config/kilo/kilo.json` to register the ControlKeel MCP server."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "amp-native"}, root, project_root, _skills, opts) do
    # 1. TypeScript plugin
    plugin_path = Path.join(root, ".amp/plugins/controlkeel-governance.ts")
    File.mkdir_p!(Path.dirname(plugin_path))
    File.write!(plugin_path, amp_plugin_contents())

    skill_path = Path.join(root, ".agents/skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(skill_path))
    File.write!(skill_path, amp_skill_contents())

    skill_mcp_path = Path.join(root, ".agents/skills/controlkeel-governance/mcp.json")

    File.write!(
      skill_mcp_path,
      Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    command_path = Path.join(root, ".amp/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, amp_command_contents())

    submit_command_path = Path.join(root, ".amp/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      host_submit_plan_command_contents("Amp", "amp", ".amp/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".amp/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Amp", "amp", ".amp/annotate.md")
    )

    last_command_path = Path.join(root, ".amp/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Amp"))

    package_json_path = Path.join(root, ".amp/package.json")
    File.write!(package_json_path, Jason.encode!(amp_package_manifest(), pretty: true) <> "\n")

    # 2. MCP config
    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    # 3. Instructions
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("amp", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => plugin_path, "kind" => "plugin"},
        %{"path" => skill_path, "kind" => "skills"},
        %{"path" => skill_mcp_path, "kind" => "mcp"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.amp/plugins/` and `.amp/commands/` into your project root (requires `PLUGINS=all` env var to activate).",
        "Prefer the native skill path when possible: `amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance`.",
        "Merge `.mcp.json` into your project's MCP config."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "augment-native"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".augment/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".augment/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, augment_agent_contents(skills))

    command_path = Path.join(root, ".augment/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, augment_review_command_contents())

    submit_command_path = Path.join(root, ".augment/commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, augment_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".augment/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      host_annotate_command_contents("Augment", "augment", ".augment/annotate.md")
    )

    last_command_path = Path.join(root, ".augment/commands/controlkeel-last.md")
    File.write!(last_command_path, host_last_command_contents("Augment"))

    rule_path = Path.join(root, ".augment/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, augment_rule_contents())

    mcp_path = Path.join(root, ".augment/mcp.json")
    File.write!(mcp_path, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    settings_path = Path.join(root, ".augment/settings.controlkeel.json")

    File.write!(
      settings_path,
      Jason.encode!(augment_settings_snippet(project_root, opts), pretty: true) <> "\n"
    )

    instructions_path = Path.join(root, "AUGMENT.md")
    File.write!(instructions_path, instructions_only_contents("augment", project_root, opts))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("augment", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => settings_path, "kind" => "settings"},
        %{"path" => instructions_path, "kind" => "instructions"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.augment/skills`, `.augment/agents`, `.augment/commands`, and `.augment/rules` in the repo so Auggie loads ControlKeel-native guidance automatically.",
        "Use `.augment/mcp.json` with `auggie --mcp-config ./.augment/mcp.json` for ephemeral MCP wiring or merge `.augment/settings.controlkeel.json` into `~/.augment/settings.json` for persistence.",
        "For hook-native review interception, run Auggie with the local plugin bundle from `controlkeel/dist/augment-plugin`."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "instructions-only"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("agents", project_root, opts))

    claude_path = Path.join(root, "CLAUDE.md")
    File.write!(claude_path, instructions_only_contents("claude", project_root, opts))

    copilot_path = Path.join(root, "copilot-instructions.md")
    File.write!(copilot_path, instructions_only_contents("copilot", project_root, opts))

    aider_path = Path.join(root, "AIDER.md")
    File.write!(aider_path, aider_instructions_contents())

    aider_config_path = Path.join(root, ".aider.conf.yml")
    File.write!(aider_config_path, aider_config_contents(project_root, opts))

    aider_command_path = Path.join(root, ".aider/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(aider_command_path))
    File.write!(aider_command_path, aider_command_contents())

    aider_annotate_command_path = Path.join(root, ".aider/commands/controlkeel-annotate.md")

    File.write!(
      aider_annotate_command_path,
      host_annotate_command_contents("Aider", "aider", ".aider/annotate.md")
    )

    aider_last_command_path = Path.join(root, ".aider/commands/controlkeel-last.md")
    File.write!(aider_last_command_path, host_last_command_contents("Aider"))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => claude_path, "kind" => "instructions"},
        %{"path" => copilot_path, "kind" => "instructions"},
        %{"path" => aider_path, "kind" => "instructions"},
        %{"path" => aider_config_path, "kind" => "settings"},
        %{"path" => aider_command_path, "kind" => "command"},
        %{"path" => aider_annotate_command_path, "kind" => "command"},
        %{"path" => aider_last_command_path, "kind" => "command"}
      ],
      [
        "Use these snippets with MCP-only or command-driven tools such as Aider that do not support native skills or plugins."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "open-swe-runtime"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("open-swe", project_root, opts))

    readme_path = Path.join(root, "open-swe/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, open_swe_runtime_contents(project_root, opts))

    webhook_path = Path.join(root, "open-swe/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" => "Wire this into Open SWE GitHub, Slack, or Linear flows as needed."
        },
        pretty: true
      ) <> "\n"
    )

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Open SWE can read ControlKeel guidance.",
        "Use the runtime README and webhook example when wiring GitHub, Slack, or Linear entry points."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "devin-runtime"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("devin", project_root, opts))

    readme_path = Path.join(root, "devin/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, devin_runtime_contents(project_root, opts))

    config_path = Path.join(root, "devin/controlkeel-mcp.json")

    File.write!(
      config_path,
      Jason.encode!(
        %{
          "transport" => "STDIO",
          "command" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts),
          "env_variables" => %{},
          "note" =>
            "Use this in Devin's Add Your Own MCP flow when ControlKeel is installed in the runtime."
        },
        pretty: true
      ) <> "\n"
    )

    webhook_path = Path.join(root, "devin/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" =>
            "Use this when wiring Devin sessions back into ControlKeel governance or external CI hooks."
        },
        pretty: true
      ) <> "\n"
    )

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Devin can ingest ControlKeel workflow guidance.",
        "Use the custom MCP JSON as the starting point for Devin's Add Your Own MCP flow."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "executor-runtime"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("executor", project_root, opts))

    readme_path = Path.join(root, "executor/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, executor_runtime_contents(project_root, opts))

    sources_path = Path.join(root, "executor/controlkeel-sources.example.ts")

    File.write!(sources_path, """
    // Executor bootstrap example
    // Run with: executor call --file controlkeel-sources.example.ts
    return await tools.executor.sources.add({
      kind: "mcp",
      name: "ControlKeel",
      command: "#{mcp_command(project_root, opts)}",
      args: #{Jason.encode!(mcp_args(project_root, opts))}
    })
    """)

    webhook_path = Path.join(root, "executor/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" =>
            "Use this when syncing paused approvals, auth resumes, and governed runtime completions back into ControlKeel."
        },
        pretty: true
      ) <> "\n"
    )

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => sources_path, "kind" => "runtime"},
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Executor-driven runs inherit ControlKeel workflow guidance.",
        "Use the runtime README and source example when wiring OpenAPI, GraphQL, MCP, and custom JS integrations into Executor."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "virtual-bash-runtime"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("virtual-bash", project_root, opts))

    readme_path = Path.join(root, "virtual-bash/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, virtual_bash_runtime_contents(project_root, opts))

    manifest_path = Path.join(root, "virtual-bash/controlkeel-runtime.json")

    File.write!(
      manifest_path,
      Jason.encode!(
        %{
          "mode" => "virtual_workspace_runtime",
          "discovery" => %{
            "transport" => "mcp",
            "command" => mcp_command(project_root, opts),
            "args" => mcp_args(project_root, opts),
            "tools" => ["ck_fs_ls", "ck_fs_read", "ck_fs_find", "ck_fs_grep"]
          },
          "mutation" => %{
            "surface" => "shell_fallback",
            "approved_for" => ["repo mutation", "package commands", "test execution"],
            "sandbox_adapters" =>
              Enum.map(ControlKeel.ExecutionSandbox.supported_adapters(), fn adapter ->
                Map.take(adapter, [:id, :name, :available])
              end)
          },
          "note" =>
            "Use the virtual workspace first for discovery. Treat shell as a governed fallback, not the primary context surface."
        },
        pretty: true
      ) <> "\n"
    )

    shell_path = Path.join(root, "virtual-bash/controlkeel-shell.example.sh")

    File.write!(shell_path, """
    #!/usr/bin/env bash
    set -euo pipefail

    PROJECT_ROOT="#{Path.expand(project_root)}"

    echo "ControlKeel virtual-bash runtime bootstrap"
    echo "Project root: ${PROJECT_ROOT}"
    echo "Discovery first: use ck_fs_ls, ck_fs_read, ck_fs_find, and ck_fs_grep over MCP."
    echo "Shell fallback: use ControlKeel's configured sandbox for repo mutation, package commands, and tests."
    echo
    echo "MCP server:"
    echo "  #{mcp_command(project_root, opts)} #{Enum.join(mcp_args(project_root, opts), " ")}"
    echo
    echo "Sandbox adapters:"
    controlkeel sandbox status
    """)

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => manifest_path, "kind" => "runtime"},
        %{"path" => shell_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so virtual-bash loops inherit ControlKeel workflow guidance.",
        "Use the runtime manifest for discovery-first orchestration and the shell example when you need governed fallback execution."
      ]
    )
  end

  defp write_target(
         %SkillTarget{id: "cloudflare-workers-runtime"},
         root,
         project_root,
         _skills,
         opts
       ) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("cloudflare-workers", project_root, opts))

    readme_path = Path.join(root, "cloudflare-workers/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, cloudflare_workers_runtime_contents(project_root, opts))

    config_path = Path.join(root, "cloudflare-workers/wrangler.toml")
    File.write!(config_path, cloudflare_workers_wrangler_contents(project_root, opts))

    mcp_config = Path.join(root, "cloudflare-workers/controlkeel-mcp.json")

    File.write!(
      mcp_config,
      Jason.encode!(
        %{
          "mcp_servers" => %{
            "controlkeel-governance" => %{
              "command" => "npx",
              "args" => ["-y", "@aryaminus/controlkeel-mcp"],
              "env" => %{}
            }
          }
        },
        pretty: true
      ) <> "\n"
    )

    env_example_path = Path.join(root, "cloudflare-workers/.env.example")

    File.write!(env_example_path, """
    # ControlKeel Configuration
    CK_API_URL=https://api.controlkeel.com
    CK_API_KEY=ck_your_api_key_here

    # Workers AI (optional - defaults to Workers AI)
    # AI_PROVIDER=openai
    # OPENAI_API_KEY=sk-...
    """)

    package_json_path = Path.join(root, "cloudflare-workers/package.json")

    File.write!(package_json_path, """
    {
      "name": "cloudflare-workers-agent",
      "version": "0.0.0",
      "private": true,
      "type": "module",
      "scripts": {
        "deploy": "wrangler deploy",
        "dev": "wrangler dev"
      },
      "dependencies": {
        "@cloudflare/workers-types": "^4.20241127.0",
        "agents": "^1.0.0",
        "zod": "^3.23.0"
      },
      "devDependencies": {
        "@cloudflare/workers-plugin": "^3.0.0",
        "wrangler": "^3.93.0",
        "typescript": "^5.0.0"
      }
    }
    """)

    tsconfig_path = Path.join(root, "cloudflare-workers/tsconfig.json")

    File.write!(tsconfig_path, """
    {
      "compilerOptions": {
        "target": "ES2022",
        "module": "ES2022",
        "moduleResolution": "bundler",
        "lib": ["ES2022"],
        "types": ["@cloudflare/workers-types"],
        "strict": true,
        "skipLibCheck": true,
        "noEmit": true,
        "resolveJsonModule": true,
        "isolatedModules": true
      },
      "include": ["src/**/*.ts"]
    }
    """)

    agent_src = Path.join(root, "cloudflare-workers/src/agent.ts")
    File.mkdir_p!(Path.dirname(agent_src))
    File.write!(agent_src, cloudflare_workers_agent_contents(opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => mcp_config, "kind" => "settings"},
        %{"path" => agent_src, "kind" => "runtime"}
      ],
      [
        "Deploy with `npm run deploy` after adding your CK API key.",
        "The agent includes built-in governance tools via MCP."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "framework-adapter"}, root, project_root, _skills, opts) do
    readme_path = Path.join(root, "framework-adapters/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, framework_adapter_contents(project_root, opts))

    config_path = Path.join(root, "framework-adapters/frameworks.json")

    File.write!(
      config_path,
      Jason.encode!(
        %{
          "frameworks" => [
            %{"id" => "dspy", "mode" => "benchmark_adapter"},
            %{"id" => "gepa", "mode" => "policy_training_adapter"},
            %{"id" => "deepagents", "mode" => "runtime_harness_adapter"}
          ]
        },
        pretty: true
      ) <> "\n"
    )

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"}
      ],
      [
        "Use this export as the typed scaffold for DSPy, GEPA, or DeepAgents benchmark and training adapters."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "provider-profile"}, root, project_root, _skills, opts) do
    readme_path = Path.join(root, "provider-profiles/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, provider_profile_contents(project_root, opts))

    profile_templates = [
      {"codestral.json",
       %{
         "provider" => "openai",
         "model" => "codestral-latest",
         "base_url" => "https://api.mistral.ai/v1",
         "note" =>
           "Use this as a CK-owned provider profile or proxy template for Codestral-compatible APIs."
       }},
      {"vllm.json",
       %{
         "provider" => "openai",
         "model" => "Qwen/Qwen2.5-Coder-32B-Instruct",
         "base_url" => "http://127.0.0.1:8000",
         "note" =>
           "vLLM exposes an OpenAI-compatible server. Set this base URL and model, then optionally add a token if your deployment requires one."
       }},
      {"sglang.json",
       %{
         "provider" => "openai",
         "model" => "Qwen/Qwen2.5-Coder-32B-Instruct",
         "base_url" => "http://127.0.0.1:30000",
         "note" =>
           "SGLang commonly exposes an OpenAI-compatible HTTP endpoint. Adjust host, port, and model to match your deployment."
       }},
      {"lmstudio.json",
       %{
         "provider" => "openai",
         "model" => "local-model",
         "base_url" => "http://127.0.0.1:1234",
         "note" =>
           "LM Studio local server speaks an OpenAI-compatible API. ControlKeel can use it through the OpenAI provider path with a custom base URL."
       }},
      {"huggingface.json",
       %{
         "provider" => "openai",
         "model" => "meta-llama/Llama-3.1-8B-Instruct:cerebras",
         "base_url" => "https://router.huggingface.co",
         "note" =>
           "Hugging Face Inference Providers expose OpenAI-compatible chat-completion APIs and require an HF token."
       }},
      {"ollama.json",
       %{
         "provider" => "ollama",
         "model" => "qwen2.5:7b",
         "base_url" => "http://127.0.0.1:11434",
         "note" =>
           "Use the native Ollama provider path when you want local chat and embeddings without an external API key."
       }}
    ]

    writes =
      Enum.map(profile_templates, fn {filename, payload} ->
        path = Path.join(root, "provider-profiles/#{filename}")
        File.write!(path, Jason.encode!(payload, pretty: true) <> "\n")
        %{"path" => path, "kind" => "settings"}
      end)

    with_common_assets(
      root,
      project_root,
      opts,
      [%{"path" => readme_path, "kind" => "runtime"} | writes],
      [
        "Use these templates with `controlkeel provider set-key`, `set-base-url`, `set-model`, and `default` flows.",
        "OpenAI-compatible backends such as vLLM, SGLang, LM Studio, Hugging Face, and Codestral use the CK OpenAI provider path with a custom base URL."
      ]
    )
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

  defp with_common_assets(root, project_root, opts, writes, instructions) do
    {writes, instructions} =
      if Enum.any?(writes, &(&1["kind"] == "mcp")) do
        hosted_path = Path.join(root, ".mcp.hosted.json")

        File.write!(
          hosted_path,
          Jason.encode!(hosted_mcp_payload(opts), pretty: true) <> "\n"
        )

        {
          writes ++ [%{"path" => hosted_path, "kind" => "mcp-hosted"}],
          instructions ++ ["Hosted MCP template: #{hosted_path}"]
        }
      else
        {writes, instructions}
      end

    install_guide = Path.join(root, "CONTROLKEEL_INSTALL.md")
    File.write!(install_guide, install_guide_contents(project_root, opts))

    {:ok, writes ++ [%{"path" => install_guide, "kind" => "install-guide"}],
     instructions ++ ["Bundle install guide: #{install_guide}"]}
  end

  defp mcp_payload(project_root, opts) do
    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "command" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts)
        }
      }
    }
  end

  defp opencode_mcp_payload(project_root, opts) do
    %{
      "mcp" => %{
        "controlkeel" => %{
          "type" => "local",
          "command" => [mcp_command(project_root, opts) | mcp_args(project_root, opts)]
        }
      }
    }
  end

  defp hosted_mcp_payload(opts) do
    base_url = Keyword.get(opts, :hosted_base_url, "https://your-controlkeel.example")
    client_id = Keyword.get(opts, :oauth_client_id, "ck-sa-<service-account-id>")

    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "transport" => "http",
          "url" => "#{base_url}/mcp",
          "oauth" => %{
            "grant_type" => "client_credentials",
            "token_endpoint" => "#{base_url}/oauth/token",
            "client_id" => client_id,
            "client_secret_env" => "CONTROLKEEL_SERVICE_ACCOUNT_SECRET",
            "resource" => "#{base_url}/mcp",
            "scope" => Enum.join(ControlKeel.ProtocolInterop.hosted_mcp_scopes(), " ")
          }
        }
      }
    }
  end

  defp mcp_command(project_root, opts) do
    if portable_project_root?(opts) do
      "controlkeel"
    else
      wrapper = ProjectBinding.mcp_wrapper_path(project_root)
      if File.exists?(wrapper), do: wrapper, else: "controlkeel"
    end
  end

  defp mcp_args(project_root, opts) do
    if portable_project_root?(opts) do
      ["mcp", "--project-root", Distribution.portable_project_root()]
    else
      wrapper = ProjectBinding.mcp_wrapper_path(project_root)

      if File.exists?(wrapper) do
        []
      else
        ["mcp", "--project-root", Path.expand(project_root)]
      end
    end
  end

  defp portable_project_root?(opts) do
    Keyword.get(opts, :portable_project_root, false)
  end

  defp install_guide_contents(project_root, opts) do
    project_root_line =
      if portable_project_root?(opts) do
        "`.` (portable release bundle mode; replace with your governed project root if needed)"
      else
        "`#{Path.expand(project_root)}`"
      end

    """
    # Install ControlKeel

    Use one of these supported install paths before loading this bundle:

    #{Distribution.install_markdown_all()}

    GitHub releases: <#{Distribution.github_releases_url()}>

    ## MCP runtime

    This bundle expects the ControlKeel MCP runtime to be reachable through:

    - `controlkeel mcp --project-root #{project_root_line}`
    - Hosted MCP alternative: use the generated `.mcp.hosted.json` template with a workspace service account (`POST /oauth/token` + `POST /mcp`)

    ControlKeel can auto-bootstrap the governed project binding on first use. If you already ran `controlkeel init` or `controlkeel bootstrap` inside the target repository, the generated project wrapper under `controlkeel/bin/` can be used instead of the plain `controlkeel` binary.

    ## Provider access

    ControlKeel resolves model access in this order:

    1. Agent bridge when the host client exposes one
    2. CK provider profile or stored key
    3. Local Ollama
    4. Heuristic/no-LLM fallback

    If no model provider is available, MCP governance, findings, proof, benchmark, and policy surfaces still work; only true LLM-backed features degrade.

    ## Required CK tool surface

    #{Enum.map_join(Distribution.required_mcp_tools(), "\n", &"- `#{&1}`")}
    """
  end

  defp roo_rule_contents do
    """
    # ControlKeel governance for Roo Code

    - Read `AGENTS.md` before large refactors, risky edits, schema changes, or release work.
    - Prefer ControlKeel MCP tools for validation, findings, budgets, proofs, and routing.
    - Do not bypass a blocked ControlKeel finding without an explicit human approval step.
    """
  end

  defp roo_command_contents do
    """
    # ControlKeel review

    1. Read `AGENTS.md`, `.roomodes`, and any Roo guidance files in the workspace.
    2. Gather context before editing files.
    3. Use `ck_context` for task, workspace, transcript, and resume context, then `ck_validate` before and after risky changes.
    4. Summarize findings, risk, proof state, and benchmark impact before finishing.
    """
  end

  defp roo_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the plan to `.roo/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .roo/review-plan.md --submitted-by roo-code --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Do not continue until ControlKeel approves the plan.
    """
  end

  defp roo_guidance_contents do
    """
    # ControlKeel + Roo Code

    Use ControlKeel as the governance layer for risky work. Treat CK findings as the safety boundary, not optional advice.

    Start with `controlkeel-governance`, then load domain skills as needed.
    """
  end

  defp roo_cloud_guidance_contents do
    """
    # ControlKeel + Roo cloud agents

    When Roo cloud or remote agents are involved:

    1. Keep the human-readable plan in the repo.
    2. Submit plan or completion packets through ControlKeel review.
    3. Return blocked findings and proof state with the final handoff.
    """
  end

  defp roo_modes_contents do
    """
    customModes:
      - slug: controlkeel-operator
        name: ControlKeel Operator
        roleDefinition: >
          You are Roo Code operating inside a ControlKeel-governed repository. Use
          ControlKeel MCP tools for validation, findings, budgets, proofs, and routing
          before finalizing risky work.
        whenToUse: Use for governed code changes, validation, benchmark, or release work.
        description: Governed Roo Code mode backed by ControlKeel MCP.
        groups:
          - read
          - edit
          - command
          - mcp
        source: project
    """
  end

  defp goose_hints_contents do
    """
    This repository is governed by ControlKeel.

    @AGENTS.md

    Use ControlKeel MCP tools before risky edits, schema changes, auth changes, deployment work, or benchmark-sensitive changes.

    Always run validation and findings review before marking work complete.
    """
  end

  defp goose_workflow_contents do
    """
    name: controlkeel-review
    description: Review the task through ControlKeel validation, findings, and proof surfaces before completion.
    steps:
      - Read AGENTS.md and .goosehints.
      - Gather repo and task context before editing.
      - Use ControlKeel MCP tools for validation, findings, budgets, routing, and proofs.
      - Summarize risk, findings, and proof state before handoff.
    """
  end

  defp goose_command_contents do
    """
    # ControlKeel review

    Use this command when Goose needs a governed review pass before finalizing work.

    1. Read `.goosehints` and `AGENTS.md`.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate`.
    3. Summarize blocked findings and proof status.
    """
  end

  defp goose_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the plan to `goose/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file goose/review-plan.md --submitted-by goose --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Continue only after approval.
    """
  end

  defp goose_extension_yaml(project_root, opts) do
    goose_extension_config(project_root, opts)
    |> yaml_document()
  end

  defp goose_extension_config(project_root, opts) do
    %{
      "extensions" => %{
        "controlkeel" => %{
          "enabled" => true,
          "type" => "stdio",
          "name" => "ControlKeel",
          "description" => "ControlKeel governance MCP server",
          "cmd" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts),
          "timeout" => 300
        }
      }
    }
  end

  defp openclaw_config_snippet(project_root, opts) do
    %{
      "mcpServers" => %{
        "controlkeel" => %{
          "command" => mcp_command(project_root, opts),
          "args" => mcp_args(project_root, opts)
        }
      },
      "skills" => %{
        "load" => %{
          "extraDirs" => ["./skills"]
        }
      }
    }
  end

  defp kilo_config_snippet(project_root, opts) do
    %{
      "mcp" => %{
        "controlkeel" => %{
          "type" => "local",
          "command" => [mcp_command(project_root, opts) | mcp_args(project_root, opts)],
          "enabled" => true
        }
      }
    }
  end

  defp openclaw_plugin_manifest do
    %{
      "name" => "controlkeel",
      "version" => app_version(),
      "description" => "ControlKeel governance skills and MCP companion for OpenClaw.",
      "skills" => "skills",
      "mcpServers" => ".mcp.json"
    }
  end

  defp droid_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" =>
        "ControlKeel governance skills, droids, commands, and MCP bridge for Factory Droid.",
      "version" => app_version(),
      "author" => %{"name" => "ControlKeel", "url" => "https://github.com/aryaminus/controlkeel"},
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0"
    }
  end

  defp kilo_command_contents do
    """
    # ControlKeel review

    1. Read `AGENTS.md` and any repo-local Kilo guidance before making risky edits.
    2. Call `ck_context` for task, workspace, transcript, and resume context.
    3. Run `ck_validate` before and after risky code, config, shell, or deploy work.
    4. Summarize blocked findings, proof state, and review status before completion.
    """
  end

  defp droid_profile_contents do
    """
    ---
    name: controlkeel
    description: Govern risky code and release work through ControlKeel validation, proofs, and browser review.
    model: inherit
    ---

    # ControlKeel Droid

    Use ControlKeel governance, findings, proofs, budgets, and benchmark workflows before making risky code or deployment changes.

    Start each task by reading `AGENTS.md`, then use ControlKeel MCP tools for validation and finding escalation.
    """
  end

  defp droid_review_command_contents do
    """
    ---
    description: Run a governed ControlKeel review for the current Droid task
    disable-model-invocation: true
    ---

    # ControlKeel review

    Review the current task or PR goal through ControlKeel before risky work or final completion.

    1. Read `AGENTS.md` and any repo-local context first.
    2. Call `ck_context` for mission, workspace, memory, and review state.
    3. Call `ck_validate` before and after risky changes.
    4. Summarize findings, verification strength, risk, and next steps before continuing.
    """
  end

  defp droid_submit_plan_command_contents do
    """
    ---
    description: Submit the current Droid plan to ControlKeel and wait for approval
    disable-model-invocation: true
    ---

    # ControlKeel submit-plan

    1. Save the current implementation plan to `.factory/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .factory/review-plan.md --submitted-by droid --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Do not begin implementation until the review is approved.
    """
  end

  defp droid_annotate_command_contents do
    """
    ---
    description: Submit focused file-risk notes to ControlKeel before risky Droid edits
    disable-model-invocation: true
    ---

    # ControlKeel annotate

    1. Save the target file path, risks, and focused notes to `.factory/annotate.md`.
    2. Run `controlkeel review plan submit --title "File annotation review" --body-file .factory/annotate.md --submitted-by droid --json`.
    3. Wait for the response before applying risky edits.
    """
  end

  defp droid_last_command_contents do
    """
    ---
    description: Re-open the latest ControlKeel review tracked in Droid
    disable-model-invocation: true
    ---

    # ControlKeel last

    1. Read the last stored review id from your notes or prior command output.
    2. Run `controlkeel review plan open --id <review_id> --json`.
    3. If the review is still pending, run `controlkeel review plan wait --id <review_id> --json`.
    """
  end

  defp droid_plugin_readme_contents do
    """
    # ControlKeel Factory Plugin

    This bundle packages ControlKeel for Factory Droid as a shareable plugin.

    It ships:
    - `skills/` for governed ControlKeel skills
    - `droids/` for a reusable `controlkeel` droid
    - `commands/` for review, submit-plan, annotate, and last flows
    - `mcp.json` for the local ControlKeel MCP bridge
    - `hooks/hooks.json` as the plugin hook entrypoint

    Local testing flow:

    1. `controlkeel plugin export droid`
    2. `droid plugin marketplace add ./controlkeel/dist/droid-plugin`
    3. `droid plugin install controlkeel@droid-plugin`
    """
  end

  defp forge_acp_manifest(project_root, opts) do
    %{
      "agent" => "controlkeel",
      "transport" => "stdio",
      "command" => mcp_command(project_root, opts),
      "args" => mcp_args(project_root, opts),
      "note" => "Fallback to the bundled .mcp.json when ACP session setup is unavailable."
    }
  end

  defp open_swe_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Open SWE + ControlKeel

    Use this runtime export when Open SWE is triggered from GitHub, Slack, or Linear instead of a local editor attach flow.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Open SWE can ingest ControlKeel policy and workflow context.

    ## Recommended ControlKeel touchpoints

    - `controlkeel mcp --project-root #{project_root}` for MCP-capable local debugging
    - Webhook events: `finding.created`, `task.completed`, `task.failed`, `proof.generated`
    - Repo automation: run validation and proof generation before final PR handoff
    """
  end

  defp devin_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Devin + ControlKeel

    Use this runtime export when Devin runs as a hosted coding environment instead of a local editor attach flow.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Devin can ingest ControlKeel policy and workflow context.

    ## Recommended Devin setup

    - Use Devin's custom MCP flow and point it at the bundled `devin/controlkeel-mcp.json`
    - Prefer service accounts or shared runtime secrets for any OAuth-backed MCPs you add in Devin
    - Use webhook events such as `finding.created`, `task.completed`, `task.failed`, and `proof.generated` to sync governance state into CI or issue workflows
    """
  end

  defp executor_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Executor + ControlKeel

    Use this runtime export when you want a typed integration layer for OpenAPI, GraphQL, MCP, Google Discovery, or custom JS functions instead of pushing tool schemas and results directly through transcript context.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so Executor-driven runs inherit ControlKeel governance context.

    ## Recommended Executor setup

    - Start Executor with its local web/runtime flow or run `executor call --file ...` in the governed project root
    - Add ControlKeel as an MCP-backed source using the bundled `executor/controlkeel-sources.example.ts`
    - Let Executor handle auth or approval pauses, then sync final task/finding/proof outcomes back through CK webhooks
    - Prefer Executor for large integration surfaces where typed discovery and execution are better than broad shell usage

    ## ControlKeel fit

    - Typed discovery: use Executor to discover and describe tools by intent before execution
    - Governed execution: keep CK as the approval, findings, budget, and proof authority around the runtime
    - Runtime boundary: use shell only for repo mutation, package commands, and tests that do not fit the typed runtime
    """
  end

  defp virtual_bash_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Virtual Bash Runtime + ControlKeel

    Use this runtime export when you want a just-bash-style outer loop, but you want ControlKeel to keep discovery on the read-only virtual workspace and reserve shell for governed fallback only.

    ## Repo context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root so the runtime inherits ControlKeel workflow guidance.

    ## Recommended runtime shape

    - Discovery first: browse the repo with `ck_fs_ls`, `ck_fs_read`, `ck_fs_find`, and `ck_fs_grep`
    - Use the bundled `virtual-bash/controlkeel-runtime.json` as the machine-readable contract for the loop
    - Use shell only for repo mutation, package commands, and tests that do not fit the virtual workspace
    - Prefer a configured sandbox adapter such as `nono`, `docker`, or `e2b` when broader shell authority is needed

    ## ControlKeel fit

    - Honest scope: this is a governed virtual-workspace recipe, not a magical universal host
    - Context hygiene: filesystem discovery stays outside the transcript until the agent asks for specific content
    - Fallback boundary: shell remains broad fallback only, with stronger approval pressure than read-only discovery
    """
  end

  defp framework_adapter_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Framework adapter scaffold

    This export is the typed bridge for framework-style integrations that are not local `attach` targets.

    - Repo root: `#{project_root}`
    - Use for DSPy benchmark subjects, GEPA optimizer/policy-training artifacts, and DeepAgents runtime harness adapters.
    - ControlKeel still owns governance, proofs, benchmark orchestration, and provider brokerage around these frameworks.
    """
  end

  defp provider_profile_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Provider profile templates

    This export provides CK-owned provider templates for provider/model integrations that are not local `attach` clients.

    - Repo root: `#{project_root}`
    - Use with `controlkeel provider set-key ...`, `controlkeel provider set-base-url ...`, `controlkeel provider set-model ...`, and `controlkeel provider default ...`
    - Included templates cover Codestral, vLLM, SGLang, LM Studio, Hugging Face, and Ollama
    - OpenAI-compatible backends flow through the CK OpenAI provider path; use a custom base URL and model, then add a token only when the backend requires one
    - CK accepts base URLs with or without a trailing `/v1`, but the templates here omit it for consistency
    """
  end

  defp codex_plugin_manifest do
    %{
      "name" => "controlkeel",
      "version" => app_version(),
      "description" =>
        "ControlKeel governance skills, commands, agents, and MCP bridge for Codex.",
      "author" => %{
        "name" => "ControlKeel",
        "url" => "https://github.com/aryaminus/controlkeel"
      },
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0",
      "keywords" => ["governance", "security", "agent-skills", "mcp"],
      "skills" => "./skills/",
      "hooks" => "./hooks.json",
      "commands" => "./commands/",
      "mcpServers" => "./.mcp.json",
      "apps" => "./.app.json",
      "interface" => %{
        "displayName" => "ControlKeel",
        "shortDescription" => "Govern agent work with MCP, skills, and proofs.",
        "longDescription" =>
          "ControlKeel makes agent-built work secure, scoped, validated, and production-ready across MCP, proof, findings, budgets, and routing.",
        "developerName" => "ControlKeel",
        "category" => "Developer Tools",
        "capabilities" => ["Write", "Interactive", "Governance"],
        "websiteURL" => "https://github.com/aryaminus/controlkeel",
        "privacyPolicyURL" => "https://github.com/aryaminus/controlkeel",
        "termsOfServiceURL" => "https://github.com/aryaminus/controlkeel",
        "defaultPrompt" => [
          "Load ControlKeel governance and validate the current task.",
          "Review the repo through ControlKeel before a risky change.",
          "Use CK routing and proofs to complete this task safely."
        ],
        "brandColor" => "#0f766e"
      }
    }
  end

  defp codex_marketplace_manifest do
    %{
      "name" => "controlkeel-local",
      "interface" => %{"displayName" => "ControlKeel Local"},
      "plugins" => [
        %{
          "name" => "controlkeel",
          "source" => %{"source" => "local", "path" => "./plugins/controlkeel"},
          "policy" => %{"installation" => "AVAILABLE", "authentication" => "ON_USE"},
          "category" => "Developer Tools"
        }
      ]
    }
  end

  defp codex_app_manifest do
    %{
      "name" => "controlkeel",
      "description" => "Codex plugin companion app metadata for hosted MCP and skills delivery.",
      "protocols" => ["mcp"]
    }
  end

  defp claude_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, subagents, and MCP bridge.",
      "version" => app_version(),
      "author" => %{"name" => "ControlKeel", "url" => "https://github.com/aryaminus/controlkeel"},
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0",
      "keywords" => ["governance", "mcp", "skills", "security"],
      "agents" => "./agents/",
      "skills" => "./skills/",
      "commands" => "./commands/",
      "hooks" => "./hooks/hooks.json",
      "mcpServers" => "./.mcp.json"
    }
  end

  defp copilot_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance skills, agents, and MCP bridge.",
      "version" => app_version(),
      "author" => %{"name" => "ControlKeel", "email" => "opensource@controlkeel.local"},
      "license" => "Apache-2.0",
      "keywords" => ["governance", "security", "skills"],
      "skills" => "skills",
      "agents" => "agents",
      "commands" => "commands",
      "hooks" => "hooks.json",
      "mcpServers" => ".mcp.json",
      "tags" => ["governance", "security", "skills"]
    }
  end

  defp augment_plugin_manifest do
    %{
      "name" => "controlkeel",
      "description" => "ControlKeel governance bundle for Augment / Auggie CLI.",
      "version" => app_version(),
      "author" => %{"name" => "ControlKeel", "url" => "https://github.com/aryaminus/controlkeel"},
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => "https://github.com/aryaminus/controlkeel",
      "license" => "Apache-2.0",
      "keywords" => ["augment", "auggie", "governance", "mcp", "skills"],
      "skills" => "./skills/",
      "agents" => "./agents/",
      "commands" => "./commands/",
      "hooks" => "./hooks/hooks.json",
      "mcpServers" => "./.mcp.json"
    }
  end

  defp claude_hooks_manifest do
    %{
      "hooks" => %{
        "PermissionRequest" => [
          %{
            "matcher" => "ExitPlanMode",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/controlkeel-review.sh",
                "timeout" => 345_600
              }
            ]
          }
        ]
      }
    }
  end

  defp claude_manual_settings do
    %{
      "hooks" => %{
        "PermissionRequest" => [
          %{
            "matcher" => "ExitPlanMode",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "controlkeel review plan submit --stdin --submitted-by claude-code"
              }
            ]
          }
        ]
      }
    }
  end

  defp copilot_hooks_manifest do
    %{
      "version" => 1,
      "hooks" => %{
        "preToolUse" => [
          %{
            "type" => "command",
            "bash" => "./bin/controlkeel-review.sh",
            "powershell" => "./bin/controlkeel-review.ps1",
            "timeoutSec" => 345_600,
            "comment" => "Intercepts plan-mode exit and waits for ControlKeel browser review."
          }
        ]
      }
    }
  end

  defp augment_hooks_manifest do
    %{
      "hooks" => %{
        "PreToolUse" => [
          %{
            "matcher" => "str-replace-editor|save-file|launch-process",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./hooks/controlkeel-review.sh",
                "timeout" => 345_600
              }
            ]
          }
        ]
      }
    }
  end

  defp empty_hooks_manifest do
    %{"hooks" => %{}}
  end

  defp vscode_extensions_manifest do
    %{
      "recommendations" => ["aryaminus.controlkeel-review"],
      "unwantedRecommendations" => []
    }
  end

  defp vscode_companion_manifest do
    %{
      "name" => "controlkeel-review",
      "displayName" => "ControlKeel Review",
      "description" =>
        "Open ControlKeel review URLs in VS Code and route browser review into editor webviews.",
      "version" => app_version(),
      "publisher" => "aryaminus",
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => %{
        "type" => "git",
        "url" => "https://github.com/aryaminus/controlkeel.git"
      },
      "categories" => ["Other", "Testing"],
      "keywords" => ["controlkeel", "review", "governance", "mcp"],
      "engines" => %{"vscode" => "^1.85.0"},
      "main" => "./extension.js",
      "activationEvents" => ["onStartupFinished"],
      "contributes" => %{
        "commands" => [
          %{
            "command" => "controlkeel-review.openUrl",
            "title" => "ControlKeel: Open review URL in editor"
          },
          %{
            "command" => "controlkeel-review.openPayload",
            "title" => "ControlKeel: Open review payload in editor"
          },
          %{
            "command" => "controlkeel-review.annotateSelection",
            "title" => "ControlKeel: Annotate current selection"
          }
        ],
        "configuration" => %{
          "title" => "ControlKeel Review",
          "properties" => %{
            "controlkeelReview.injectBrowser" => %{
              "type" => "boolean",
              "default" => true,
              "description" =>
                "Inject browser routing environment variables into integrated terminals."
            }
          }
        }
      }
    }
  end

  defp review_bridge_shell_contents(submitted_by) do
    """
    #!/usr/bin/env sh
    set -eu

    tmp_body=$(mktemp)
    trap 'rm -f "$tmp_body"' EXIT INT TERM

    cat >"$tmp_body"

    : "${CONTROLKEEL_AGENT_ID:=#{submitted_by}}"
    export CONTROLKEEL_AGENT_ID

    submit_output=$(controlkeel review plan submit --stdin --submitted-by "#{submitted_by}" --json <"$tmp_body")
    printf "%s\\n" "$submit_output"

    if command -v jq >/dev/null 2>&1; then
      review_id=$(printf "%s\\n" "$submit_output" | jq -r '.review.id // empty')
    else
      review_id=$(printf "%s\\n" "$submit_output" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p' | head -n 1)
    fi

    if [ -z "$review_id" ]; then
      echo "ControlKeel hook could not parse the submitted review id." >&2
      exit 1
    fi

    controlkeel review plan wait --id "$review_id" --json
    """
  end

  defp review_bridge_powershell_contents(submitted_by) do
    """
    $plan = [Console]::In.ReadToEnd()
    $tempPath = Join-Path $env:TEMP ("controlkeel-plan-" + [Guid]::NewGuid().ToString() + ".md")

    try {
      Set-Content -Path $tempPath -Value $plan -NoNewline
      if (-not $env:CONTROLKEEL_AGENT_ID) {
        $env:CONTROLKEEL_AGENT_ID = "#{submitted_by}"
      }

      $submitOutput = & controlkeel review plan submit --stdin --submitted-by #{submitted_by} --json < $tempPath
      $submitOutput | ForEach-Object { Write-Output $_ }
      $submitJson = $submitOutput | ConvertFrom-Json

      if (-not $submitJson.review.id) {
        Write-Error "ControlKeel hook could not parse the submitted review id."
        exit 1
      }

      $reviewId = $submitJson.review.id
      & controlkeel review plan wait --id $reviewId --json
      exit $LASTEXITCODE
    }
    finally {
      if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force
      }
    }
    """
  end

  defp cline_rule_contents do
    """
    ---
    name: controlkeel-governance
    description: Keep ControlKeel governance active for risky edits, validation, proof capture, and release-sensitive work.
    ---

    # ControlKeel governance

    - Prefer ControlKeel MCP tools before risky edits, schema changes, auth changes, or release work.
    - Read `AGENTS.md` before large repo-wide changes.
    - Run validation and findings review before marking work complete.
    - Keep proof and benchmark surfaces current when asked to compare or attest behavior.
    """
  end

  defp cline_workflow_contents do
    """
    ---
    description: Review the current task through ControlKeel validation, findings, and proof surfaces before finalizing.
    ---

    # ControlKeel review workflow

    1. Read `AGENTS.md` for ControlKeel governance context.
    2. Gather repo and task context before changing files.
    3. Use ControlKeel MCP tools for validation, findings, budget, and routing when relevant.
    4. Summarize risk, findings, and proof status before completing the task.
    """
  end

  defp cline_command_contents do
    """
    # ControlKeel review

    Use this command when Cline should run a governed review pass before completing risky work.

    1. Read `AGENTS.md` and the current `.clinerules/` guidance.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate` before presenting a conclusion.
    3. Summarize findings, proof status, and any blockers.
    """
  end

  defp cline_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the current plan to `.cline/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .cline/review-plan.md --submitted-by cline --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Do not execute until the review is approved.
    """
  end

  defp cline_taskstart_hook_contents do
    """
    #!/usr/bin/env sh
    set -eu

    controlkeel status >/dev/null 2>&1 || true
    """
  end

  defp cursor_rule_contents do
    """
    ---
    description: Govern Cursor work with ControlKeel MCP, findings, budgets, proofs, and routing.
    ---

    Always call ControlKeel before risky edits, shell commands, auth changes, or release work.
    Load `controlkeel-governance` first, then add domain-specific skills as needed.
    """
  end

  defp cursor_command_contents do
    """
    # ControlKeel review

    Use ControlKeel before finalizing risky edits, schema changes, auth changes, or release work.

    1. Call `ck_context` for mission, workspace, transcript, and resume context.
    2. Call `ck_validate`.
    3. Summarize findings, proof status, and follow-up work.
    """
  end

  defp cursor_submit_plan_command_contents do
    """
    # ControlKeel submit plan

    1. Save the current plan to `.cursor/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .cursor/review-plan.md --submitted-by cursor --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Only implement after approval.
    """
  end

  defp cursor_background_agent_contents do
    """
    # ControlKeel background agent guidance

    When Cursor background agents are enabled, use this handoff:

    1. Draft the plan first.
    2. Submit the plan with ControlKeel before execution.
    3. Return proof status, unresolved findings, and any blocked work with the final handoff.
    """
  end

  defp windsurf_rule_contents do
    """
    # ControlKeel for Windsurf

    Use ControlKeel as the governance layer for risky repository changes.
    Prefer CK MCP tools for context, validation, findings, budgets, routing, and proof-aware completion.
    """
  end

  defp windsurf_command_contents do
    """
    # ControlKeel review

    Use this command in Windsurf before exiting plan mode or finalizing risky work.

    1. Gather mission, workspace, and recent transcript context with `ck_context`.
    2. Validate with `ck_validate`.
    3. If a human plan review is needed, submit it through ControlKeel and wait for approval.
    """
  end

  defp windsurf_workflow_contents do
    """
    # ControlKeel review workflow

    1. Stay in planning until ControlKeel approves the plan.
    2. Use ControlKeel MCP tools before risky edits.
    3. Surface blocked findings immediately.
    4. Finish with proof and risk status.
    """
  end

  defp windsurf_hook_manifest do
    %{
      "version" => 1,
      "hooks" => [
        %{
          "event" => "ExitPlanMode",
          "type" => "command",
          "command" => "./controlkeel-review.sh",
          "timeoutSec" => 345_600
        }
      ]
    }
  end

  defp windsurf_workspace_hook_manifest do
    %{
      "version" => 1,
      "hooks" => [
        %{
          "event" => "ExitPlanMode",
          "type" => "command",
          "command" => "./hooks/controlkeel-review.sh",
          "timeoutSec" => 345_600
        }
      ]
    }
  end

  defp augment_rule_contents do
    """
    # ControlKeel governance for Augment

    - Prefer ControlKeel MCP tools before risky edits, shell commands, auth changes, or release work.
    - Use `/controlkeel-submit-plan` before leaving planning for non-trivial changes.
    - Use `/controlkeel-review` before declaring work complete.
    - Use `/controlkeel-annotate` for file-specific risk notes and `/controlkeel-last` to reopen the latest review.
    - Stay autonomous where possible, but respect ControlKeel review gates and blocked findings.
    """
  end

  defp augment_review_command_contents do
    """
    ---
    description: Run a governed ControlKeel review for the current Augment task
    ---

    Read `.augment/rules/controlkeel.md`, use ControlKeel MCP tools, and summarize blocked findings, proof status, and follow-up work before completing the task.
    """
  end

  defp augment_submit_plan_command_contents do
    """
    ---
    description: Submit the current Augment plan to ControlKeel and wait for approval
    ---

    1. Save the current plan to `.augment/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .augment/review-plan.md --submitted-by augment --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Do not implement until the review is approved.
    """
  end

  defp augment_settings_snippet(project_root, opts) do
    %{
      "mcpServers" => mcp_payload(project_root, opts)["mcpServers"],
      "note" =>
        "Merge this into ~/.augment/settings.json if you want persistent ControlKeel MCP registration outside per-workspace --mcp-config usage."
    }
  end

  defp augment_plugin_readme_contents do
    """
    # ControlKeel Augment Plugin Bundle

    Use this bundle with:

    `auggie --plugin-dir ./controlkeel/dist/augment-plugin`

    The bundle ships:
    - hook-native plan interception
    - ControlKeel review, submit-plan, annotate, and last commands
    - a ControlKeel operator subagent
    - a local MCP bridge
    """
  end

  defp continue_prompt_contents do
    """
    # ControlKeel Continue Prompt

    Start with `controlkeel-governance`, use CK MCP tools before risky work, and surface blocked findings immediately.
    Keep proofs and budget state current before marking a task complete.
    """
  end

  defp continue_plan_prompt_contents do
    """
    # ControlKeel Continue Plan Mode

    Stay in plan mode until ControlKeel has reviewed and approved the plan. Use MCP tools for context gathering, but do not switch into implementation until approval returns.
    """
  end

  defp continue_review_prompt_contents do
    """
    # ControlKeel Continue Review

    Before finalizing, summarize:
    - unresolved findings
    - proof status
    - budget or routing concerns
    - any human review follow-up
    """
  end

  defp continue_headless_prompt_contents do
    """
    # ControlKeel Continue Headless

    In headless runs, prefer structured CLI calls:
    - `controlkeel review plan submit --json`
    - `controlkeel review plan wait --json`
    - `controlkeel findings --format json`
    """
  end

  defp continue_command_contents do
    """
    name: controlkeel-review
    description: Review the current task through ControlKeel validation, findings, and proof state.
    prompt: |
      Read AGENTS.md, run CK context/validation, and summarize blocked findings and proof state before completion.
    """
  end

  defp continue_submit_plan_command_contents do
    """
    name: controlkeel-submit-plan
    description: Submit the current plan to ControlKeel and wait for review.
    prompt: |
      Save the plan to `.continue/review-plan.md`, run `controlkeel review plan submit --body-file .continue/review-plan.md --submitted-by continue --json`, then wait with `controlkeel review plan wait --id <review_id> --json`.
    """
  end

  defp letta_settings_manifest do
    %{
      "hooks" => %{
        "SessionStart" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./.letta/hooks/controlkeel-session-start.sh",
                "timeout" => 5_000
              }
            ]
          }
        ],
        "PostToolUse" => [
          %{
            "matcher" => "Bash|Edit|Write|TodoWrite|Task",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./.letta/hooks/controlkeel-findings.sh",
                "timeout" => 5_000
              }
            ]
          }
        ],
        "PermissionRequest" => [
          %{
            "matcher" => "*",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "./.letta/hooks/controlkeel-findings.sh",
                "timeout" => 5_000
              }
            ]
          }
        ]
      }
    }
  end

  defp letta_local_settings_example_manifest do
    %{
      "permissions" => %{
        "allow" => ["Read(*)", "Glob(*)", "Grep(*)"],
        "ask" => ["Bash(*)", "Edit(*)", "Write(*)", "Task(*)"]
      }
    }
  end

  defp letta_findings_hook_contents do
    """
    #!/usr/bin/env sh
    set -eu

    if ! command -v controlkeel >/dev/null 2>&1; then
      exit 0
    fi

    controlkeel findings --format summary --quiet 2>/dev/null || true
    exit 0
    """
  end

  defp letta_session_start_hook_contents do
    """
    #!/usr/bin/env sh
    set -eu

    cat <<'EOF'
    ControlKeel: prefer ck_context before risky work, ck_validate before writes or shell, and ck_review_submit/ck_review_status for non-trivial plans.
    MCP registration helper: ./.letta/controlkeel-mcp.sh
    EOF
    """
  end

  defp letta_mcp_helper_contents(project_root, opts) do
    command = mcp_command(project_root, opts)
    args = Enum.map_join(mcp_args(project_root, opts), " ", &shell_escape/1)

    """
    #!/usr/bin/env sh
    set -eu

    exec #{shell_escape(command)} #{args} "$@"
    """
  end

  defp letta_readme_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Letta Code + ControlKeel

    This bundle prepares the real Letta-native surfaces ControlKeel can support today:

    - project skills in `.agents/skills`
    - checked-in hook settings in `.letta/settings.json`
    - repo-local MCP registration helper in `.letta/controlkeel-mcp.sh`
    - portable MCP reference in `.mcp.json`

    ## Skills

    Letta's primary project skill path is `.agents/skills`, with legacy `.skills` compatibility and optional `--skills` / `--skill-sources` overrides.

    ## Hooks

    - `.letta/settings.json` is the shared project settings file
    - `.letta/settings.local.json` is for personal/local overrides and should stay untracked
    - `.letta/settings.local.example.json` is a starter local permissions file

    ## MCP

    Add the local ControlKeel stdio server from inside the repo:

    ```text
    /mcp add --transport stdio controlkeel ./.letta/controlkeel-mcp.sh
    ```

    If you want hosted MCP instead, point Letta at the CK HTTP endpoint:

    ```text
    /mcp add --transport http controlkeel-hosted https://your-controlkeel.example/mcp
    ```

    ## Headless

    Letta's headless path is useful for CI or outer-loop automation:

    ```bash
    letta -p "Review the current repo with ControlKeel" --output-format json
    letta -p --output-format stream-json --input-format stream-json
    ```

    ## Remote / listener

    Letta's remote/listener surface is `letta server`. Use that when you want a long-lived remote agent service rather than a local interactive session.

    ## Project root

    `#{project_root}`
    """
  end

  defp shell_escape(value) do
    escaped = String.replace(value, "'", "'\"'\"'")
    "'#{escaped}'"
  end

  defp continue_mcp_server_contents(project_root, opts) do
    %{
      "name" => "controlkeel",
      "transport" => "stdio",
      "command" => mcp_command(project_root, opts),
      "args" => mcp_args(project_root, opts)
    }
    |> yaml_document()
  end

  defp codex_agent_contents(project_root, skills, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    name = "controlkeel-operator"
    description = "Operate inside a ControlKeel-governed project with CK skills and MCP tools."
    model = "gpt-5.4-mini"

    [mcp]
    servers = ["controlkeel"]

    [skills]
    preload = [#{Enum.map_join(skills, ", ", &~s("#{&1.name}"))}]

    [context]
    project_root = "#{project_root}"
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

  defp augment_agent_contents(skills) do
    """
    ---
    name: controlkeel-operator
    description: Operate inside a ControlKeel-governed repository and use CK tools proactively.
    color: cyan
    tools:
      - "*"
    ---

    # ControlKeel Operator

    Start with the `controlkeel-governance` skill. Use these supporting skills when relevant:

    #{Enum.map_join(skills, "\n", &"- `#{&1.name}` — #{&1.description}")}

    Prefer CK MCP tools for plan review, validation, findings, budgets, routing, and proof state.
    Stay autonomous, but do not bypass explicit ControlKeel review gates.
    """
  end

  defp instructions_only_contents(target, project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # ControlKeel Companion Instructions

    This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, workspace snapshots, transcript state, and routing.

    Project root: `#{project_root}`
    Target: `#{target}`
    Primary CK loop: `#{ControlKeel.SetupAdvisor.core_loop()}`

    Required workflow:
    1. Call `ck_context` at the start of a task for mission, workspace, transcript, and resume context.
    2. Call `ck_validate` before writing code, config, shell, or deploy content.
    3. Submit plans or approval packets with `ck_review_submit` and check `ck_review_status` before execution.
    4. Record any human-review issue with `ck_finding`.
    5. Check `ck_budget` before expensive model or multi-agent work.
    6. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.

    Install ControlKeel:
    #{Enum.map_join(Distribution.install_channels(), "\n", fn channel -> "- #{channel.label}: `#{channel.command}`" end)}

    ControlKeel auto-bootstraps project binding on first use. Provider access resolves through agent bridge, CK-owned provider profiles, local Ollama, then heuristic fallback.
    """
  end

  defp cloudflare_workers_runtime_contents(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # Cloudflare Workers Agent + ControlKeel

    This export provides a governed Cloudflare Workers AI agent with built-in MCP governance tools.

    ## Project Context

    - Repo root: `#{project_root}`
    - Keep `AGENTS.md` at the repo root for shared governance context

    ## Architecture

    - **Runtime**: Cloudflare Workers (serverless)
    - **AI**: Workers AI (default) or BYOM (bring your own model)
    - **Storage**: D1 (SQLite), KV, R2 (file system)
    - **Governance**: MCP server via npx

    ## Setup

    1. Install dependencies:
       ```bash
       cd cloudflare-workers
       npm install
       ```

    2. Copy `.env.example` to `.dev.vars` and add your CK_API_KEY

    3. Deploy:
       ```bash
       npm run deploy
       ```

    ## ControlKeel Integration

    - Use `ck_context`, `ck_validate`, `ck_finding`, `ck_budget` via MCP
    - `ck_context` returns bounded workspace and transcript state alongside governance data
    - The agent includes built-in governance tools wired to the MCP server
    - All AI requests pass through ControlKeel policy gates

    ## Available Tools

    - D1 SQL: `env.DB` from Cloudflare
    - R2: `env.BUCKET` for file storage
    - KV: `env.KV` for key-value
    - AI: Workers AI or custom model via BYOM
    """
  end

  defp cloudflare_workers_wrangler_contents(_project_root, _opts) do
    """
    name = "controlkeel-agent"
    main = "src/agent.ts"
    compatibility_date = "2024-01-01"
    compatibility_flags = ["nodejs_compat"]

    [observability]
    enabled = true

    [[d1_databases]]
    binding = "DB"
    database_name = "controlkeel-agent"
    database_id = "your-database-id"

    [[kv_namespaces]]
    binding = "KV"
    id = "your-kv-namespace-id"

    [[r2_buckets]]
    binding = "BUCKET"
    bucket_name = "controlkeel-agent"

    [ai]
    binding = "AI"
    """
  end

  defp cloudflare_workers_agent_contents(_opts) do
    """
    import { Agents } from "agents";
    import type { AssistantMessage, TextDelta } from "@cloudflare/workers-types";

    export interface Env {
      DB: D1Database;
      KV: KVNamespace;
      BUCKET: R2Bucket;
      AI: Ai;
      CK_API_KEY: string;
    }

    export default {
      async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);

        if (url.pathname === "/health") {
          return new Response(JSON.stringify({ status: "ok" }), {
            headers: { "Content-Type": "application/json" }
          });
        }

        if (url.pathname === "/chat" && request.method === "POST") {
          const { messages, sessionId } = await request.json();
          
          // Initialize governance context
          const governanceResult = await this.runGovernance("context", {
            project_root: "/",
            task: "chat"
          }, env);

          // Run AI with governance
          const response = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
            messages,
            governance_context: governanceResult
          });

          // Record findings if any
          await this.runGovernance("finding", {
            session_id: sessionId,
            response: response.response
          }, env);

          return new Response(JSON.stringify({ 
            response: response.response,
            governance: governanceResult
          }), {
            headers: { "Content-Type": "application/json" }
          });
        }

        return new Response("Not Found", { status: 404 });
      },

      async runGovernance(action: string, payload: any, env: Env): Promise<any> {
        // MCP governance calls via npx
        const mcpResult = await fetch("http://localhost:3000/mcp", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${env.CK_API_KEY}`
          },
          body: JSON.stringify({
            action,
            payload
          })
        });

        return mcpResult.json();
      }
    } satisfies ExportedHandler<Env>;
    """
  end

  defp yaml_document(value) do
    yaml_encode(value, 0)
  end

  defp yaml_encode(value, indent) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("", fn {key, nested} ->
      yaml_key_value(to_string(key), nested, indent)
    end)
  end

  defp yaml_encode(value, indent) when is_list(value) do
    Enum.map_join(value, "", fn
      nested when is_map(nested) ->
        "#{String.duplicate(" ", indent)}-\n" <> yaml_encode(nested, indent + 2)

      nested ->
        "#{String.duplicate(" ", indent)}- #{yaml_scalar(nested)}\n"
    end)
  end

  defp yaml_key_value(key, value, indent) when is_map(value) do
    if map_size(value) == 0 do
      "#{String.duplicate(" ", indent)}#{key}: {}\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) when is_list(value) do
    if value == [] do
      "#{String.duplicate(" ", indent)}#{key}: []\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) do
    "#{String.duplicate(" ", indent)}#{key}: #{yaml_scalar(value)}\n"
  end

  defp yaml_scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_scalar(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end

  # ── OpenCode native helpers ────────────────────────────────────────────────

  defp opencode_plugin_contents do
    ~S"""
    import type { Plugin } from "@opencode-ai/plugin"
    import { tool } from "@opencode-ai/plugin"

    /**
     * ControlKeel Review Bridge for OpenCode
     *
     * Host-specific adapter behavior:
     * - injects a submit_plan review tool for planning agents
     * - suppresses plan_exit in favor of ControlKeel browser review
     * - keeps the review tool primary-agent only by default
     * - routes plan submission and wait decisions through the CK CLI
     */
    export const ControlKeelGovernance: Plugin = async ({ project, client, $, directory }) => {
      const parseJson = (output: string) => {
        try {
          return JSON.parse(output)
        } catch (_error) {
          throw new Error(`ControlKeel returned invalid JSON: ${output}`)
        }
      }

      const toText = async (output: unknown) => {
        if (typeof output === "string") {
          return output
        }

        if (output instanceof Uint8Array) {
          return new TextDecoder().decode(output)
        }

        if (output instanceof ArrayBuffer) {
          return new TextDecoder().decode(new Uint8Array(output))
        }

        if (output == null) {
          return ""
        }

        if (typeof output === "object") {
          if (typeof (output as { text?: unknown }).text === "function") {
            try {
              const direct = await (output as { text: () => Promise<string> }).text()
              if (typeof direct === "string") {
                return direct
              }
            } catch (_error) {
            }
          }

          const stdout = (output as { stdout?: unknown }).stdout
          if (typeof stdout === "string") {
            return stdout
          }

          if (stdout instanceof Uint8Array) {
            return new TextDecoder().decode(stdout)
          }

          if (stdout instanceof ArrayBuffer) {
            return new TextDecoder().decode(new Uint8Array(stdout))
          }

          if (stdout && typeof (stdout as { text?: unknown }).text === "function") {
            try {
              const streamed = await (stdout as { text: () => Promise<string> }).text()
              if (typeof streamed === "string") {
                return streamed
              }
            } catch (_error) {
            }
          }
        }

        return String(output)
      }

      const parseVersion = (output: string) => {
        const match = output.match(/(\d+)\.(\d+)\.(\d+)/)
        if (!match) {
          return null
        }

        return {
          major: Number(match[1]),
          minor: Number(match[2]),
          patch: Number(match[3]),
        }
      }

      const versionAtLeast = (
        current: { major: number; minor: number; patch: number },
        required: { major: number; minor: number; patch: number }
      ) => {
        if (current.major !== required.major) {
          return current.major > required.major
        }

        if (current.minor !== required.minor) {
          return current.minor > required.minor
        }

        return current.patch >= required.patch
      }

      const ensurePlanSubmitSupport = async () => {
        let versionOutput = ""

        try {
          const versionProc = Bun.spawn(["controlkeel", "version"], {
            stdout: "pipe",
            stderr: "pipe",
          })
          versionOutput = await new Response(versionProc.stdout).text()
          const versionExit = await versionProc.exited
          if (versionExit !== 0) {
            throw new Error(`controlkeel version exited with code ${versionExit}`)
          }
        } catch (error) {
          throw new Error(
            "Failed to run `controlkeel version`. Install ControlKeel >= 0.1.26 and ensure `controlkeel` is on PATH."
          )
        }

        const parsed = parseVersion(versionOutput)
        const required = { major: 0, minor: 1, patch: 26 }

        if (!parsed || !versionAtLeast(parsed, required)) {
          throw new Error(
            `ControlKeel CLI ${versionOutput.trim() || "unknown"} is too old for plan-review submit. Install >= 0.1.26.`
          )
        }
      }

      const submitPlan = async (
        body: string,
        submittedBy: string,
        title?: string,
        waitTimeoutSeconds?: number
      ) => {
        await ensurePlanSubmitSupport()

        const envTaskId = process.env.CONTROLKEEL_TASK_ID
        const envSessionId = process.env.CONTROLKEEL_SESSION_ID
        const waitTimeout = Number(waitTimeoutSeconds ?? process.env.CONTROLKEEL_REVIEW_WAIT_TIMEOUT ?? 30)
        const waitTimeoutSecondsSafe = Number.isFinite(waitTimeout) && waitTimeout > 0 ? waitTimeout : 30

        // Write body to temp file to avoid stdin piping issues
        const tmpFile = `${directory}/.opencode/review-plan-${Date.now()}.md`
        await Bun.write(tmpFile, body)

        try {
          const submitArgs = ["controlkeel", "review", "plan", "submit", "--body-file", tmpFile, "--submitted-by", submittedBy, "--json"]
          if (title) submitArgs.push("--title", title)
          if (envTaskId) submitArgs.push("--task-id", envTaskId)
          else if (envSessionId) submitArgs.push("--session-id", envSessionId)

          const submitProc = Bun.spawn(submitArgs, { stdout: "pipe", stderr: "pipe" })
          const submitOut = await new Response(submitProc.stdout).text()
          await submitProc.exited

          const submitPayload = parseJson(submitOut)

          if (typeof submitPayload?.error === "string" && submitPayload.error.includes("session_id")) {
            throw new Error(
              "ControlKeel plan submission requires review context. Set CONTROLKEEL_TASK_ID (preferred) or CONTROLKEEL_SESSION_ID, or pass --task-id/--session-id manually."
            )
          }

          const reviewId = submitPayload?.review?.id
          if (!reviewId) {
            throw new Error("ControlKeel did not return a review id")
          }

          const waitProc = Bun.spawn(["controlkeel", "review", "plan", "wait", "--id", String(reviewId), "--timeout", String(waitTimeoutSecondsSafe), "--json"], { stdout: "pipe", stderr: "pipe" })
          const waitOut = await new Response(waitProc.stdout).text()
          await waitProc.exited

          const waitPayload = parseJson(waitOut)
          return {
            reviewId,
            submitPayload,
            waitPayload,
            browserUrl: submitPayload?.browser_url,
            status: waitPayload?.review?.status,
            feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
          }
        } finally {
          // Clean up temp file
          try { await Bun.file(tmpFile).unlink?.() ?? (await $`rm -f ${tmpFile}`.quiet()) } catch {}
        }
      }

      return {
        "shell.env": async (input, output) => {
          output.env.CONTROLKEEL_PROJECT_ROOT = directory
          output.env.CONTROLKEEL_AGENT_ID = "opencode"

          if (input.sessionID) {
            output.env.CONTROLKEEL_THREAD_ID = input.sessionID
          }
        },

        config: async (config) => {
          const primaryTools = config.experimental?.primary_tools ?? []
          if (!primaryTools.includes("submit_plan")) {
            config.experimental = {
              ...config.experimental,
              primary_tools: [...primaryTools, "submit_plan"],
            }
          }
        },

        "tool.definition": async (input, output) => {
          if (input.toolID === "plan_exit") {
            output.description =
              "Do not call this tool. Use submit_plan so ControlKeel can collect approval in the browser review flow."
          }
        },

        "experimental.chat.system.transform": async (_input, output) => {
          output.system.push(
            "Use submit_plan when you are ready for human review. Do not proceed with implementation until ControlKeel approves the plan."
          )
        },

        tool: {
          "submit_plan": tool({
            description:
              "Submit a plan to ControlKeel for browser review. The tool waits for approval before execution continues.",
            args: {
              plan: tool.schema.string().describe("Markdown plan body to submit for review."),
              title: tool.schema.string().optional(),
              wait_timeout_seconds: tool.schema.number().int().positive().optional(),
            },
            async execute(args) {
              const result = await submitPlan(
                args.plan,
                "opencode",
                args.title,
                args.wait_timeout_seconds
              )
              return JSON.stringify(result, null, 2)
            },
          }),
        },
      }
    }
    """
  end

  defp opencode_agent_contents do
    """
    ---
    description: ControlKeel governed code review agent — validates changes against security, budget, and compliance policies.
    model: anthropic/claude-sonnet-4-5
    tools:
      write: false
      edit: false
    ---

    You are the ControlKeel governance operator. Your role is to review code changes
    and validate them against the project's security, budget, and compliance policies.

    ## Instructions

    1. Use `ck_context` first, then `ck_validate` before providing feedback.
    2. Report findings by severity: critical > high > medium > low.
    3. Never approve changes that have unresolved critical or high findings.
    4. Reference specific policy rules when flagging issues.
    5. Summarize budget impact if token/cost tracking is enabled.

    ## Available MCP Tools

    - `ck_context` — Load mission, findings, budget, and proof context
    - `ck_validate` — Run full governance validation
    - `ck_finding` — Record a governed finding when you detect a missed issue
    - `ck_review_submit` — Submit review material for human approval
    - `ck_review_status` — Check review status before execution
    - `ck_budget` — Check remaining budget and spend history
    - `ck_route` — Ask ControlKeel for the recommended specialist route
    """
  end

  defp opencode_command_contents do
    """
    ---
    description: Run ControlKeel governance review on the current project
    agent: controlkeel-operator
    ---

    Review the current project for governance compliance. Run `ck_validate` to check
    for security findings, budget status, and proof readiness. Summarize the results
    and highlight any blockers that need attention before shipping.

    Focus on:
    1. Open findings by severity
    2. Budget remaining vs. spent
    3. Proof coverage for completed tasks
    4. Any policy violations that block release
    """
  end

  defp opencode_submit_plan_command_contents do
    """
    ---
    description: Submit the current plan to ControlKeel browser review and wait for approval
    ---

    Save the current plan to a markdown file, then submit it through ControlKeel.

    Recommended flow:
    1. Save the plan to `.opencode/review-plan.md`
    2. Ensure `controlkeel version` reports `>= 0.1.26`
    3. Run `controlkeel review plan submit --body-file .opencode/review-plan.md --submitted-by opencode --task-id <task_id> --json` (or use `--session-id <session_id>`)
    4. Read the returned `review.id` and `browser_url`
    5. Wait with `controlkeel review plan wait --id <review_id> --timeout 30 --json`
    6. Do not execute until the review is approved

    Fallback when the `submit_plan` tool is stale in a long-running OpenCode session:
    - If the tool returns an error like `ControlKeel CLI [object Object] is too old`, run the CLI flow above directly.
    - Restart OpenCode after plugin updates so `.opencode/plugins/controlkeel-governance.ts` is reloaded.
    """
  end

  defp opencode_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-opencode",
      "version" => app_version(),
      "type" => "module",
      "description" => "ControlKeel OpenCode adapter bundle",
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => %{
        "type" => "git",
        "url" => "git+https://github.com/aryaminus/controlkeel.git"
      },
      "bugs" => %{"url" => "https://github.com/aryaminus/controlkeel/issues"},
      "keywords" => ["controlkeel", "opencode", "plugin", "governance", "mcp"],
      "exports" => %{
        "." => "./index.js",
        "./plugin" => "./index.js"
      },
      "main" => "./index.js",
      "dependencies" => %{
        "@opencode-ai/plugin" => "1.3.13"
      },
      "files" => [".opencode", "AGENTS.md", "README.md", "index.js"],
      "publishConfig" => %{"access" => "public"},
      "license" => "Apache-2.0"
    }
  end

  defp opencode_package_entry_contents do
    ~S"""
    import { tool } from "@opencode-ai/plugin"

    /**
     * Published OpenCode package entrypoint for ControlKeel.
     *
     * This mirrors the repo-local plugin in `.opencode/plugins/controlkeel-governance.ts`
     * but ships as plain JavaScript for npm-based installs.
     */
    export const ControlKeelGovernance = async ({ $, directory }) => {
      const parseJson = (output) => {
        try {
          return JSON.parse(output)
        } catch (_error) {
          throw new Error(`ControlKeel returned invalid JSON: ${output}`)
        }
      }

      const toText = async (output) => {
        if (typeof output === "string") {
          return output
        }

        if (output instanceof Uint8Array) {
          return new TextDecoder().decode(output)
        }

        if (output instanceof ArrayBuffer) {
          return new TextDecoder().decode(new Uint8Array(output))
        }

        if (output == null) {
          return ""
        }

        if (typeof output === "object") {
          if (typeof output.text === "function") {
            try {
              const direct = await output.text()
              if (typeof direct === "string") {
                return direct
              }
            } catch (_error) {
            }
          }

          const stdout = output.stdout
          if (typeof stdout === "string") {
            return stdout
          }

          if (stdout instanceof Uint8Array) {
            return new TextDecoder().decode(stdout)
          }

          if (stdout instanceof ArrayBuffer) {
            return new TextDecoder().decode(new Uint8Array(stdout))
          }

          if (stdout && typeof stdout.text === "function") {
            try {
              const streamed = await stdout.text()
              if (typeof streamed === "string") {
                return streamed
              }
            } catch (_error) {
            }
          }
        }

        return String(output)
      }

      const parseVersion = (output) => {
        const match = output.match(/(\d+)\.(\d+)\.(\d+)/)
        if (!match) {
          return null
        }

        return {
          major: Number(match[1]),
          minor: Number(match[2]),
          patch: Number(match[3]),
        }
      }

      const versionAtLeast = (current, required) => {
        if (current.major !== required.major) {
          return current.major > required.major
        }

        if (current.minor !== required.minor) {
          return current.minor > required.minor
        }

        return current.patch >= required.patch
      }

      const ensurePlanSubmitSupport = async () => {
        let versionOutput = ""

        try {
          const versionProc = Bun.spawn(["controlkeel", "version"], {
            stdout: "pipe",
            stderr: "pipe",
          })
          versionOutput = await new Response(versionProc.stdout).text()
          const versionExit = await versionProc.exited
          if (versionExit !== 0) {
            throw new Error(`controlkeel version exited with code ${versionExit}`)
          }
        } catch (_error) {
          throw new Error(
            "Failed to run `controlkeel version`. Install ControlKeel >= 0.1.26 and ensure `controlkeel` is on PATH."
          )
        }

        const parsed = parseVersion(versionOutput)
        const required = { major: 0, minor: 1, patch: 26 }

        if (!parsed || !versionAtLeast(parsed, required)) {
          throw new Error(
            `ControlKeel CLI ${versionOutput.trim() || "unknown"} is too old for plan-review submit. Install >= 0.1.26.`
          )
        }
      }

      const submitPlan = async (body, submittedBy, title, waitTimeoutSeconds) => {
        await ensurePlanSubmitSupport()

        const envTaskId = process.env.CONTROLKEEL_TASK_ID
        const envSessionId = process.env.CONTROLKEEL_SESSION_ID
        const waitTimeout = Number(waitTimeoutSeconds ?? process.env.CONTROLKEEL_REVIEW_WAIT_TIMEOUT ?? 30)
        const waitTimeoutSecondsSafe = Number.isFinite(waitTimeout) && waitTimeout > 0 ? waitTimeout : 30

        // Write body to temp file to avoid stdin piping issues
        const tmpFile = `${directory}/.opencode/review-plan-${Date.now()}.md`
        await Bun.write(tmpFile, body)

        try {
          const submitArgs = ["controlkeel", "review", "plan", "submit", "--body-file", tmpFile, "--submitted-by", submittedBy, "--json"]
          if (title) submitArgs.push("--title", title)
          if (envTaskId) submitArgs.push("--task-id", envTaskId)
          else if (envSessionId) submitArgs.push("--session-id", envSessionId)

          const submitProc = Bun.spawn(submitArgs, { stdout: "pipe", stderr: "pipe" })
          const submitOut = await new Response(submitProc.stdout).text()
          await submitProc.exited

          const submitPayload = parseJson(submitOut)

          if (typeof submitPayload?.error === "string" && submitPayload.error.includes("session_id")) {
            throw new Error(
              "ControlKeel plan submission requires review context. Set CONTROLKEEL_TASK_ID (preferred) or CONTROLKEEL_SESSION_ID, or pass --task-id/--session-id manually."
            )
          }

          const reviewId = submitPayload?.review?.id
          if (!reviewId) {
            throw new Error("ControlKeel did not return a review id")
          }

          const waitProc = Bun.spawn(["controlkeel", "review", "plan", "wait", "--id", String(reviewId), "--timeout", String(waitTimeoutSecondsSafe), "--json"], { stdout: "pipe", stderr: "pipe" })
          const waitOut = await new Response(waitProc.stdout).text()
          await waitProc.exited

          const waitPayload = parseJson(waitOut)
          return {
            reviewId,
            submitPayload,
            waitPayload,
            browserUrl: submitPayload?.browser_url,
            status: waitPayload?.review?.status,
            feedbackNotes: waitPayload?.review?.feedback_notes ?? null,
          }
        } finally {
          // Clean up temp file
          try { await Bun.file(tmpFile).unlink?.() ?? (await $`rm -f ${tmpFile}`.quiet()) } catch {}
        }
      }

      return {
        "shell.env": async (input, output) => {
          output.env.CONTROLKEEL_PROJECT_ROOT = directory
          output.env.CONTROLKEEL_AGENT_ID = "opencode"

          if (input.sessionID) {
            output.env.CONTROLKEEL_THREAD_ID = input.sessionID
          }
        },

        config: async (config) => {
          const primaryTools = config.experimental?.primary_tools ?? []
          if (!primaryTools.includes("submit_plan")) {
            config.experimental = {
              ...config.experimental,
              primary_tools: [...primaryTools, "submit_plan"],
            }
          }
        },

        "tool.definition": async (input, output) => {
          if (input.toolID === "plan_exit") {
            output.description =
              "Do not call this tool. Use submit_plan so ControlKeel can collect approval in the browser review flow."
          }
        },

        "experimental.chat.system.transform": async (_input, output) => {
          output.system.push(
            "Use submit_plan when you are ready for human review. Do not proceed with implementation until ControlKeel approves the plan."
          )
        },

        tool: {
          "submit_plan": tool({
            description:
              "Submit a plan to ControlKeel for browser review. The tool waits for approval before execution continues.",
            args: {
              plan: tool.schema.string().describe("Markdown plan body to submit for review."),
              title: tool.schema.string().optional(),
              wait_timeout_seconds: tool.schema.number().int().positive().optional(),
            },
            async execute(args) {
              const result = await submitPlan(
                args.plan,
                "opencode",
                args.title,
                args.wait_timeout_seconds
              )
              return JSON.stringify(result, null, 2)
            },
          }),
        },
      }
    }

    export default ControlKeelGovernance
    """
  end

  defp opencode_package_readme_contents do
    """
    # ControlKeel OpenCode plugin

    Direct install:

    ```json
    {
      "plugin": ["@aryaminus/controlkeel-opencode"]
    }
    ```

    This npm package exposes the ControlKeel OpenCode governance plugin entrypoint.
    For the full repo-local experience with commands, agents, and MCP config, also run:

    ```bash
    controlkeel attach opencode
    ```

    The repo-local command bundle now includes:
    - `/controlkeel-review`
    - `/controlkeel-submit-plan`
    - `/controlkeel-annotate`
    - `/controlkeel-last`
    """
  end

  # ── Gemini CLI native helpers ──────────────────────────────────────────────

  defp gemini_extension_manifest(project_root, opts) do
    %{
      "name" => "controlkeel-governance",
      "version" => "1.0.0",
      "contextFileName" => "GEMINI.md",
      "settings" => [
        %{
          "name" => "ControlKeel API Key",
          "description" => "API key for the ControlKeel governance proxy (optional).",
          "envVar" => "CONTROLKEEL_API_KEY",
          "sensitive" => true
        }
      ],
      "mcpServers" =>
        mcp_payload(project_root, opts)
        |> Map.get("mcpServers", %{})
    }
  end

  defp pi_extension_manifest(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    %{
      "name" => "controlkeel-pi-review",
      "version" => app_version(),
      "project_root" => project_root,
      "phase_model" => "file_plan_mode",
      "review_command" => "controlkeel-review",
      "submit_command" => "controlkeel-submit-plan",
      "browser_review" => true,
      "mcp" => %{
        "path" => ".pi/mcp.json",
        "hosted_template" => ".mcp.hosted.json"
      },
      "phase_config" => ".pi/controlkeel.json",
      "actions" => [
        %{
          "id" => "submit-plan-review",
          "label" => "Submit plan review",
          "command" =>
            "controlkeel review plan submit --body-file ${plan_file} --submitted-by pi --json"
        },
        %{
          "id" => "open-browser-review",
          "label" => "Open browser review",
          "command" => "controlkeel review plan open --id ${review_id} --json"
        },
        %{
          "id" => "wait-plan-review",
          "label" => "Wait for review decision",
          "command" => "controlkeel review plan wait --id ${review_id} --json"
        }
      ],
      "state" => %{
        "review_state_file" => ".pi/controlkeel-state.json",
        "progress_file" => "PLAN.md"
      }
    }
  end

  defp pi_phase_manifest(project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    %{
      "project_root" => project_root,
      "phases" => %{
        "planning" => %{
          "phase_model" => "file_plan_mode",
          "plan_file" => "PLAN.md",
          "allowed_tools" => [
            "read",
            "grep",
            "find",
            "ls",
            "write",
            "edit",
            "controlkeel-submit-plan"
          ],
          "write_scope" => ["PLAN.md"],
          "prompt" =>
            "Plan mode active. Only PLAN.md may be edited. Use controlkeel-submit-plan when the plan is ready."
        },
        "execution" => %{
          "phase_model" => "file_plan_mode",
          "progress_marker" => "[DONE:n]",
          "prompt" =>
            "Execution mode active after approval. Follow the approved plan in PLAN.md and mark completed steps with [DONE:n]."
        }
      }
    }
  end

  defp pi_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-pi-extension",
      "version" => app_version(),
      "description" => "ControlKeel Pi adapter bundle",
      "homepage" => "https://github.com/aryaminus/controlkeel",
      "repository" => %{
        "type" => "git",
        "url" => "git+https://github.com/aryaminus/controlkeel.git"
      },
      "bugs" => %{"url" => "https://github.com/aryaminus/controlkeel/issues"},
      "keywords" => ["controlkeel", "pi", "extension", "governance", "mcp"],
      "main" => "./pi-extension.json",
      "exports" => %{
        "." => "./pi-extension.json",
        "./manifest" => "./pi-extension.json"
      },
      "files" => [".pi", "pi-extension.json", "PI.md", "README.md"],
      "publishConfig" => %{"access" => "public"},
      "controlkeel" => %{
        "host" => "pi",
        "extension_manifest" => "pi-extension.json",
        "phase_config" => ".pi/controlkeel.json"
      },
      "license" => "Apache-2.0"
    }
  end

  defp pi_package_readme_contents do
    """
    # ControlKeel Pi extension

    Direct install on Pi builds that support npm-backed extensions:

    ```bash
    pi install npm:@aryaminus/controlkeel-pi-extension
    ```

    Short form:

    ```bash
    pi -e npm:@aryaminus/controlkeel-pi-extension
    ```

    For the full repo-local planning, commands, and MCP configuration, also run:

    ```bash
    controlkeel attach pi
    ```

    The repo-local command bundle now includes:
    - `/controlkeel-review`
    - `/controlkeel-submit-plan`
    - `/controlkeel-annotate`
    - `/controlkeel-last`
    """
  end

  defp gemini_command_contents do
    """
    # ControlKeel Governance Review
    # Usage: /controlkeel:review [scope]

    [command]
    version = 1

    prompt = \"\"\"
    Run a ControlKeel governance review on this project.

    Execute the following shell command and summarize the results:
    !{controlkeel findings --format json}

    Focus on:
    1. Open findings by severity (critical > high > medium > low)
    2. Budget remaining vs. spent
    3. Proof coverage for completed tasks
    4. Any policy violations that block release

    {{args}}
    \"\"\"
    """
  end

  defp gemini_submit_plan_command_contents do
    """
    # ControlKeel Submit Plan
    # Usage: /controlkeel:submit-plan

    [command]
    version = 1

    prompt = \"\"\"
    Save the current plan to `.gemini/review-plan.md`, then submit it with:
    !{controlkeel review plan submit --body-file .gemini/review-plan.md --submitted-by gemini-cli --json}

    Read the returned review id and wait with:
    !{controlkeel review plan wait --id <review_id> --json}

    Do not continue until the review is approved.
    \"\"\"
    """
  end

  defp gemini_annotate_command_contents do
    """
    # ControlKeel Annotate
    # Usage: /controlkeel:annotate <file>

    [command]
    version = 1

    prompt = \"\"\"
    Save focused annotation notes for {{args}} to `.gemini/annotate.md`, then submit them with:
    !{controlkeel review plan submit --title "File annotation review" --body-file .gemini/annotate.md --submitted-by gemini-cli --json}

    Wait for the review decision before making risky follow-up edits.
    \"\"\"
    """
  end

  defp gemini_last_command_contents do
    """
    # ControlKeel Last
    # Usage: /controlkeel:last

    [command]
    version = 1

    prompt = \"\"\"
    Re-open the most recent ControlKeel review you are tracking for this task:
    !{controlkeel review plan open --id <review_id> --json}

    If the review is still pending, wait with:
    !{controlkeel review plan wait --id <review_id> --json}
    \"\"\"
    """
  end

  defp gemini_extension_readme_contents do
    """
    # ControlKeel Gemini extension

    This extension provides:
    - `/controlkeel:review`
    - `/controlkeel:submit-plan`
    - `/controlkeel:annotate`
    - `/controlkeel:last`
    - the `controlkeel-governance` skill
    - MCP registration through `gemini-extension.json`
    """
  end

  defp pi_command_contents do
    """
    # /controlkeel-review

    Use this command when Pi has a plan, diff, or completion packet that needs approval before execution.

    Workflow:
    1. Save the current plan to a markdown file in the repo, for example `.pi/review-plan.md`.
    2. Run `controlkeel review plan submit --body-file .pi/review-plan.md --submitted-by pi --json`.
    3. Open the returned `browser_url` and wait for approval or denial notes.
    4. Poll `controlkeel review plan open --id <review_id> --json` or use `ck_review_status`.
    5. Do not continue execution until the review is approved.
    """
  end

  defp pi_submit_plan_command_contents do
    """
    # /controlkeel-submit-plan

    Use this command from Pi planning mode after the current plan has been written to `PLAN.md`.

    Workflow:
    1. Confirm the plan file is up to date.
    2. Run `controlkeel review plan submit --body-file PLAN.md --submitted-by pi --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Only switch into execution after approval.
    """
  end

  defp codex_diff_review_command_contents do
    """
    # /controlkeel-diff-review

    Submit the current diff for ControlKeel browser review.

    Suggested flow:
    1. Save the diff to `.codex/review.diff`
    2. Run `controlkeel review plan submit --title "Diff review" --body-file .codex/review.diff --submitted-by codex-cli --json`
    3. Open or wait on the returned review id before finalizing
    """
  end

  defp codex_completion_review_command_contents do
    """
    # /controlkeel-completion-review

    Submit the final completion summary for ControlKeel approval.

    Suggested flow:
    1. Save the completion notes to `.codex/completion.md`
    2. Run `controlkeel review plan submit --title "Completion review" --body-file .codex/completion.md --submitted-by codex-cli --json`
    3. Wait with `controlkeel review plan wait --id <review_id> --json` before presenting the task as complete
    """
  end

  defp codex_review_command_contents do
    """
    # /controlkeel-review

    Run a general ControlKeel review flow for the current task or working tree.

    Suggested flow:
    1. Save the current summary to `.codex/review.md`
    2. Run `controlkeel review plan submit --title "Codex review" --body-file .codex/review.md --submitted-by codex-cli --json`
    3. Wait with `controlkeel review plan wait --id <review_id> --json`
    """
  end

  defp codex_annotate_command_contents do
    """
    # /controlkeel-annotate <file>

    Use this when a single file needs focused human review notes.

    Suggested flow:
    1. Save the relevant notes to `.codex/annotate.md`
    2. Mention the target file path and risks at the top of the note
    3. Run `controlkeel review plan submit --title "File annotation review" --body-file .codex/annotate.md --submitted-by codex-cli --json`
    4. Wait for the response before applying risky edits
    """
  end

  defp codex_last_command_contents do
    """
    # /controlkeel-last

    Re-open the most recent ControlKeel review decision you are tracking for this task.

    Suggested flow:
    1. Read the last stored review id from your working notes or command output
    2. Run `controlkeel review plan open --id <review_id> --json`
    3. If still pending, run `controlkeel review plan wait --id <review_id> --json`
    """
  end

  defp host_review_command_contents(host_label, submitted_by) do
    """
    # /controlkeel-review

    Use this command in #{host_label} when the current work needs an explicit ControlKeel review pass.

    Suggested flow:
    1. Save the current summary or diff notes to a temporary markdown file in the repo.
    2. Run `controlkeel review plan submit --title "#{host_label} review" --body-file <path> --submitted-by #{submitted_by} --json`
    3. Open or wait on the returned review id before continuing risky work.
    """
  end

  defp host_submit_plan_command_contents(host_label, submitted_by, suggested_path) do
    """
    # /controlkeel-submit-plan

    Use this command in #{host_label} when the current plan is ready for ControlKeel approval.

    Suggested flow:
    1. Save the current plan to `#{suggested_path}`.
    2. Run `controlkeel review plan submit --body-file #{suggested_path} --submitted-by #{submitted_by} --json`
    3. Wait with `controlkeel review plan wait --id <review_id> --json`
    4. Do not begin implementation until approval is returned.
    """
  end

  defp host_annotate_command_contents(host_label, submitted_by, suggested_path) do
    """
    # /controlkeel-annotate <file>

    Use this command in #{host_label} when a specific file needs focused human notes.

    Suggested flow:
    1. Save the file path, risks, and requested annotation context to `#{suggested_path}`.
    2. Run `controlkeel review plan submit --title "File annotation review" --body-file #{suggested_path} --submitted-by #{submitted_by} --json`
    3. Wait for the response before applying risky edits.
    """
  end

  defp host_last_command_contents(host_label) do
    """
    # /controlkeel-last

    Use this command in #{host_label} to reopen the latest ControlKeel review you are tracking for the current task.

    Suggested flow:
    1. Read the last stored review id from your notes or prior command output.
    2. Run `controlkeel review plan open --id <review_id> --json`
    3. If the review is still pending, run `controlkeel review plan wait --id <review_id> --json`
    """
  end

  defp copilot_plan_review_command_contents do
    """
    ---
    description: Submit a plan to ControlKeel browser review and wait for approval
    ---

    When you are in plan mode, send the plan through ControlKeel before executing:

    1. Save the plan to `.github/controlkeel-plan.md`
    2. Run `controlkeel review plan submit --body-file .github/controlkeel-plan.md --submitted-by copilot --json`
    3. Wait with `controlkeel review plan wait --id <review_id> --json`
    4. Do not implement until the review is approved
    """
  end

  defp vscode_companion_extension_contents do
    """
    const vscode = require("vscode")

    function setEnv(collection, key, value) {
      collection.replace(key, value)
    }

    async function openUrl(url, title = "ControlKeel Review") {
      const panel = vscode.window.createWebviewPanel(
        "controlkeel-review",
        title,
        vscode.ViewColumn.Beside,
        { enableScripts: true }
      )

      panel.webview.html = `
      <!doctype html>
      <html>
        <body style="padding:0;margin:0">
          <iframe src="${url}" style="border:0;width:100vw;height:100vh"></iframe>
        </body>
      </html>`
    }

    async function openPayload(payload) {
      const data = typeof payload === "string" ? JSON.parse(payload) : payload
      const url = data.browser_url || data.url || data.review?.browser_url
      const title = data.review?.title || data.title || "ControlKeel Review"

      if (!url) {
        throw new Error("Payload did not include a browser_url")
      }

      await openUrl(url, title)
    }

    function activate(context) {
      const openCommand = vscode.commands.registerCommand("controlkeel-review.openUrl", async () => {
        const url = await vscode.window.showInputBox({
          prompt: "Enter the ControlKeel review URL",
          placeHolder: "https://..."
        })

        if (url) {
          await openUrl(url)
        }
      })

      const openPayloadCommand = vscode.commands.registerCommand(
        "controlkeel-review.openPayload",
        async payload => {
          if (!payload) {
            const raw = await vscode.window.showInputBox({
              prompt: "Paste ControlKeel review JSON",
              placeHolder: '{"browser_url":"https://..."}'
            })

            if (!raw) {
              return
            }

            payload = raw
          }

          await openPayload(payload)
        }
      )

      const annotateSelectionCommand = vscode.commands.registerCommand(
        "controlkeel-review.annotateSelection",
        async () => {
          const editor = vscode.window.activeTextEditor
          if (!editor || editor.selection.isEmpty) {
            vscode.window.showInformationMessage("Select text to attach a ControlKeel review note.")
            return
          }

          const note = await vscode.window.showInputBox({
            prompt: "ControlKeel review note for the selected code",
            placeHolder: "Needs a follow-up review before merge"
          })

          if (!note) {
            return
          }

          const key = `controlkeel.annotation.${Date.now()}`
          await context.workspaceState.update(key, {
            note,
            path: editor.document.uri.fsPath,
            selection: editor.selection
          })

          vscode.window.showInformationMessage("Stored ControlKeel annotation locally in the workspace.")
        }
      )

      context.subscriptions.push(openCommand, openPayloadCommand, annotateSelectionCommand)

      const config = vscode.workspace.getConfiguration("controlkeelReview")
      if (config.get("injectBrowser", true)) {
        setEnv(context.environmentVariableCollection, "CONTROLKEEL_REVIEW_EMBED", "vscode_webview")
        setEnv(context.environmentVariableCollection, "CONTROLKEEL_BROWSER_EMBED", "vscode_webview")
        setEnv(context.environmentVariableCollection, "CONTROLKEEL_VSCODE_WEBVIEW", "1")

        const workspace = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath
        if (workspace) {
          setEnv(context.environmentVariableCollection, "CONTROLKEEL_VSCODE_WORKSPACE", workspace)
        }
      }
    }

    function deactivate() {}

    module.exports = { activate, deactivate }
    """
  end

  defp vscode_companion_readme_contents do
    """
    # ControlKeel VS Code Companion

    This companion extension opens ControlKeel review URLs in a VS Code webview and
    injects terminal environment variables so ControlKeel-aware commands can prefer
    editor embedding over an external browser when appropriate.
    """
  end

  defp gemini_skill_contents do
    """
    ---
    name: controlkeel-governance
    description:
      Expertise in governance validation, security review, budget tracking,
      and compliance auditing. Use when the user asks to "review", "validate",
      "audit", or check "governance" status of the project.
    ---

    # ControlKeel Governance Operator

    You are a governance review specialist. When auditing code:

    1. Run `controlkeel findings --format json` to get the current status.
    2. Report findings by severity: critical > high > medium > low.
    3. Never approve changes that have unresolved critical or high findings.
    4. Reference specific policy rules when flagging issues.
    5. Summarize budget impact if token/cost tracking is enabled.
    6. Check proof coverage for completed tasks.
    """
  end

  # ── Kiro native helpers ────────────────────────────────────────────────────

  defp kiro_hook_spec do
    %{
      "name" => "ControlKeel Governance Validation",
      "description" =>
        "Runs ControlKeel governance checks after tool invocations to ensure compliance.",
      "version" => "1.0",
      "enabled" => true,
      "when" => %{
        "type" => "postToolUse",
        "tool" => "write"
      },
      "then" => %{
        "type" => "runCommand",
        "command" => "controlkeel findings --format summary --quiet"
      }
    }
  end

  defp kiro_review_hook_spec do
    %{
      "name" => "ControlKeel Plan Review Gate",
      "description" =>
        "Submits a plan review packet through ControlKeel before implementation leaves plan mode.",
      "version" => "1.0",
      "enabled" => true,
      "triggers" => [
        %{
          "type" => "PreToolUse",
          "toolNames" => ["write_file", "replace_in_file", "run_terminal_command"]
        }
      ],
      "actions" => [
        %{
          "type" => "command",
          "command" => "controlkeel review plan submit --stdin --submitted-by kiro --json"
        }
      ]
    }
  end

  defp kiro_tool_policy_manifest do
    %{
      "planning" => %{
        "allowed" => ["read_file", "search", "list_directory", "controlkeel"],
        "blocked" => ["write_file", "replace_in_file"]
      },
      "execution" => %{
        "allowed" => ["read_file", "search", "list_directory", "write_file", "replace_in_file"]
      }
    }
  end

  defp kiro_steering_contents do
    """
    # ControlKeel Governance

    This project uses ControlKeel for governance, security, and compliance management.

    ## Rules

    1. **Always** run `controlkeel findings` after making significant code changes.
    2. **Never** approve or merge changes with unresolved critical or high findings.
    3. Reference specific policy rules when flagging issues in code reviews.
    4. Summarize budget impact when token/cost tracking is enabled.
    5. Check proof coverage before marking tasks as complete.

    ## Available Tools

    - `controlkeel findings` — List open governance findings
    - `controlkeel validate` — Run full governance validation
    - `controlkeel budget` — Check remaining budget and spend history
    - `controlkeel approve <finding-id>` — Approve a finding (requires operator confirmation)
    """
  end

  defp kiro_command_contents do
    """
    # ControlKeel review

    Use this Kiro command to run a governed review pass:

    1. Read `.kiro/steering/controlkeel.md`.
    2. Use `ck_context` for task, workspace, and transcript context, then `ck_validate`.
    3. Surface blocked findings and proof status before completion.
    """
  end

  # ── Amp native helpers ─────────────────────────────────────────────────────

  defp amp_skill_contents do
    """
    ---
    name: controlkeel-governance
    description: Native ControlKeel governance skill for Amp with MCP-backed review, plan gating, and finding checks.
    ---

    # ControlKeel Governance For Amp

    Prefer this skill whenever you need to review a plan, annotate risky edits, or check the latest governed state.

    Primary flow:
    1. Use `/controlkeel-submit-plan` before leaving planning for risky work.
    2. Use `/controlkeel-review` before completion.
    3. Use `/controlkeel-annotate` for file-specific risk notes.
    4. Use `/controlkeel-last` to reopen the most recent active review.

    MCP expectations:
    - `ck_context` for task, workspace, transcript, and resume context
    - `ck_review_submit`, `ck_review_status`, and `ck_review_feedback` for review transport
    - `ck_validate` and `ck_finding` for governance results
    """
  end

  defp amp_plugin_contents do
    ~S"""
    /**
     * ControlKeel Governance Plugin for Amp
     *
     * Provides:
     * - Event hooks on tool calls for governance logging
     * - Custom ck-validate tool for on-demand governance checks
     * - /controlkeel-review command for full project review
     * - submit-plan tool for ControlKeel browser review gating
     *
     * Requires: PLUGINS=all environment variable to activate
     */

    // Hook into tool call events for governance logging
    amp.on("tool.call", async (ctx) => {
      if (ctx.tool === "bash" || ctx.tool === "shell") {
        ctx.ui.notify(`[CK] Tool execution: ${ctx.tool}`)
      }
    })

    // Register custom governance validation tool
    amp.registerTool("ck-validate", {
      description:
        "Run ControlKeel governance validation on the current project. " +
        "Returns findings, budget status, and proof readiness.",
      parameters: {
        scope: {
          type: "string",
          enum: ["full", "quick"],
          default: "quick",
          description: "Validation scope: 'full' for complete review, 'quick' for summary",
        },
      },
      async execute(args: { scope: string }) {
        const { stdout } = await amp.shell(
          `controlkeel findings --format json${args.scope === "full" ? " --full" : ""}`,
        )
        return stdout
      },
    })

    amp.registerTool("submit-plan", {
      description: "Submit a plan to ControlKeel and wait for approval.",
      parameters: {
        plan: { type: "string", description: "Markdown plan body" },
      },
      async execute(args: { plan: string }) {
        const { stdout } = await amp.shell(
          "controlkeel review plan submit --stdin --submitted-by amp --json",
          { stdin: args.plan },
        )
        return stdout
      },
    })

    // Register governance review command
    amp.registerCommand("controlkeel-review", {
      description: "Run a full ControlKeel governance review on the current project",
      async execute(ctx) {
        const result = await ctx.tool("ck-validate", { scope: "full" })
        return `Review the following governance results and provide a summary:\n\n${result}`
      },
    })
    """
  end

  defp amp_command_contents do
    """
    # /controlkeel-review

    Use this command to run a full ControlKeel review, then summarize:
    - blocked findings
    - proof status
    - budget or routing concerns
    """
  end

  defp amp_package_manifest do
    %{
      "name" => "@aryaminus/controlkeel-amp",
      "version" => app_version(),
      "private" => true,
      "description" => "ControlKeel Amp plugin bundle",
      "files" => [".amp"],
      "license" => "Apache-2.0"
    }
  end

  defp aider_instructions_contents do
    """
    # ControlKeel + Aider

    Use Aider for execution and ControlKeel for governance:

    1. Keep `AGENTS.md` in the repo root.
    2. Use `.aider/commands/controlkeel-review.md` for governed review flow.
    3. Use MCP plus command-driven review packets rather than pretending Aider has native plugin hooks.
    """
  end

  defp aider_config_contents(project_root, opts) do
    """
    mcpservers:
      controlkeel:
        command: #{mcp_command(project_root, opts)}
        args: [#{Enum.map_join(mcp_args(project_root, opts), ", ", &~s("#{&1}"))}]
    """
  end

  defp aider_command_contents do
    """
    # ControlKeel review

    1. Save the current plan or diff to a markdown file.
    2. Run `controlkeel review plan submit --body-file <file> --submitted-by aider --json`.
    3. Wait with `controlkeel review plan wait --id <review_id> --json`.
    4. Summarize blocked findings and proof status before completion.
    """
  end

  defp app_version do
    ControlKeel.CLI.version()
  end
end
