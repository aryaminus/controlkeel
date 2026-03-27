defmodule ControlKeel.Skills.Exporter do
  @moduledoc false

  alias ControlKeel.Distribution
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
    skill_root = Path.join(root, ".agents/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".codex/agents/controlkeel-operator.toml")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, codex_agent_contents(project_root, skills, opts))

    instructions_path = Path.join(root, "AGENTS.md")
    File.write!(instructions_path, instructions_only_contents("codex", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Copy .agents/skills into your repo or user skill folder.",
        "Copy .codex/agents/controlkeel-operator.toml into your Codex agents directory if you want a preconfigured operator."
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

    manifest_path = Path.join(root, ".claude-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(claude_plugin_manifest(), pretty: true) <> "\n")

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
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => settings_path, "kind" => "settings"}
      ],
      ["Run `claude --plugin-dir #{root}` to test the plugin locally."]
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
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.cline/skills` into your project or `~/.cline/skills`.",
        "Keep `.clinerules/` in the repo so Cline loads ControlKeel rules and workflows for the governed workspace.",
        "Merge `.cline/data/settings/cline_mcp_settings.json` into Cline MCP settings (`~/.cline/data/settings/cline_mcp_settings.json` or `$CLINE_DIR/data/settings/cline_mcp_settings.json`)."
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

    guidance_path = Path.join(root, ".roo/guidance/controlkeel.md")
    File.mkdir_p!(Path.dirname(guidance_path))
    File.write!(guidance_path, roo_guidance_contents())

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
        %{"path" => guidance_path, "kind" => "guidance"},
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
        %{"path" => extension_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.goosehints` and `AGENTS.md` at the repo root so Goose loads ControlKeel context automatically.",
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
        %{"name" => "controlkeel-openclaw", "private" => true, "version" => @app_version},
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

    manifest_path = Path.join(root, "plugin.json")
    File.write!(manifest_path, Jason.encode!(copilot_plugin_manifest(), pretty: true) <> "\n")

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
        %{"path" => mcp_path, "kind" => "mcp"}
      ],
      [
        "Use this bundle as a local Copilot / VS Code plugin or publish it through your plugin workflow."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "github-repo"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".github/skills")
    write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".github/agents/controlkeel-operator.agent.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, copilot_agent_contents(skills))

    github_mcp = Path.join(root, ".github/mcp.json")
    File.write!(github_mcp, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

    vscode_mcp = Path.join(root, ".vscode/mcp.json")
    File.mkdir_p!(Path.dirname(vscode_mcp))
    File.write!(vscode_mcp, Jason.encode!(mcp_payload(project_root, opts), pretty: true) <> "\n")

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
        %{"path" => github_mcp, "kind" => "mcp"},
        %{"path" => vscode_mcp, "kind" => "mcp"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Copy the .github and .vscode folders into your repository root.",
        "VS Code and Copilot can then discover the skills, custom agent, and MCP server config from the repo."
      ]
    )
  end

  defp write_target(%SkillTarget{id: "droid-bundle"}, root, project_root, skills, opts) do
    skill_root = Path.join(root, ".factory/skills")
    write_skill_tree(skills, skill_root)

    droid_path = Path.join(root, ".factory/droids/controlkeel.md")
    File.mkdir_p!(Path.dirname(droid_path))
    File.write!(droid_path, droid_profile_contents())

    command_path = Path.join(root, ".factory/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, droid_command_contents())

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
        %{"path" => command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.factory/` into the repo or your user Factory config directory.",
        "Use the generated droid profile and command as the governed ControlKeel entry point."
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

  defp write_target(%SkillTarget{id: "instructions-only"}, root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, instructions_only_contents("agents", project_root, opts))

    claude_path = Path.join(root, "CLAUDE.md")
    File.write!(claude_path, instructions_only_contents("claude", project_root, opts))

    copilot_path = Path.join(root, "copilot-instructions.md")
    File.write!(copilot_path, instructions_only_contents("copilot", project_root, opts))

    with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => claude_path, "kind" => "instructions"},
        %{"path" => copilot_path, "kind" => "instructions"}
      ],
      ["Use these snippets with MCP-only tools that do not support native skills or plugins."]
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
    3. Use `ck_context` and `ck_validate` before and after risky changes.
    4. Summarize findings, risk, proof state, and benchmark impact before finishing.
    """
  end

  defp roo_guidance_contents do
    """
    # ControlKeel + Roo Code

    Use ControlKeel as the governance layer for risky work. Treat CK findings as the safety boundary, not optional advice.

    Start with `controlkeel-governance`, then load domain skills as needed.
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

  defp openclaw_plugin_manifest do
    %{
      "name" => "controlkeel",
      "version" => @app_version,
      "description" => "ControlKeel governance skills and MCP companion for OpenClaw.",
      "skills" => "skills",
      "mcpServers" => ".mcp.json"
    }
  end

  defp droid_profile_contents do
    """
    # ControlKeel Droid

    Use ControlKeel governance, findings, proofs, budgets, and benchmark workflows before making risky code or deployment changes.

    Start each task by reading `AGENTS.md`, then use ControlKeel MCP tools for validation and finding escalation.
    """
  end

  defp droid_command_contents do
    """
    # ControlKeel review

    1. Review the current task or PR goal.
    2. Call ControlKeel context and validation surfaces.
    3. Summarize findings, risk, and next steps before execution.
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

  defp instructions_only_contents(target, project_root, opts) do
    project_root =
      if portable_project_root?(opts),
        do: Distribution.portable_project_root(),
        else: Path.expand(project_root)

    """
    # ControlKeel Companion Instructions

    This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, and routing.

    Project root: `#{project_root}`
    Target: `#{target}`

    Required workflow:
    1. Call `ck_context` at the start of a task.
    2. Call `ck_validate` before writing code, config, shell, or deploy content.
    3. Record any human-review issue with `ck_finding`.
    4. Check `ck_budget` before expensive model or multi-agent work.
    5. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.

    Install ControlKeel:
    #{Enum.map_join(Distribution.install_channels(), "\n", fn channel -> "- #{channel.label}: `#{channel.command}`" end)}

    ControlKeel auto-bootstraps project binding on first use. Provider access resolves through agent bridge, CK-owned provider profiles, local Ollama, then heuristic fallback.
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
end
