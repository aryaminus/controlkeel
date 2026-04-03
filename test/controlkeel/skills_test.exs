defmodule ControlKeel.SkillsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Skills
  alias ControlKeel.Skills.Activation
  alias ControlKeel.Skills.Parser
  alias ControlKeel.Skills.Renderer

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-skills-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    original_home = System.get_env("HOME")
    System.put_env("HOME", tmp_dir)

    on_exit(fn ->
      if original_home do
        System.put_env("HOME", original_home)
      else
        System.delete_env("HOME")
      end

      Activation.reset()
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "parser supports YAML lists, nested metadata, malformed description fallback, and recursive resources",
       %{tmp_dir: tmp_dir} do
    project_root = Path.join(tmp_dir, "project")
    skill_dir = Path.join(project_root, ".agents/skills/acme-skill")

    File.mkdir_p!(Path.join(skill_dir, "references"))
    File.mkdir_p!(Path.join(skill_dir, "scripts"))
    File.mkdir_p!(Path.join(skill_dir, "assets"))
    File.mkdir_p!(Path.join(skill_dir, "agents"))

    File.write!(Path.join(skill_dir, "references/guide.md"), "# Guide\n")
    File.write!(Path.join(skill_dir, "scripts/check.sh"), "#!/usr/bin/env sh\n")
    File.write!(Path.join(skill_dir, "assets/template.txt"), "template\n")

    File.write!(
      Path.join(skill_dir, "agents/openai.yaml"),
      """
      metadata:
        compatibility_targets:
          - github-repo
      """
    )

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: acme-skill
      description: Review code: security and costs
      compatibility:
        - codex
        - claude-plugin
      allowed-tools:
        - ck_validate
      metadata:
        ck_mcp_tools:
          - ck_budget
      ---
      # Acme Skill

      Read the [guide](references/guide.md) before acting.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert skill.name == "acme-skill"
    assert skill.description == "Review code: security and costs"
    assert Enum.sort(skill.compatibility_targets) == ["claude-plugin", "codex", "github-repo"]
    assert Enum.sort(skill.required_mcp_tools) == ["ck_budget", "ck_validate"]

    assert Enum.sort(skill.resources) == [
             "agents/openai.yaml",
             "assets/template.txt",
             "references/guide.md",
             "scripts/check.sh"
           ]

    assert skill.user_invocable == true
  end

  test "project-local skills are gated unless trusted", %{tmp_dir: tmp_dir} do
    project_root = Path.join(tmp_dir, "project")
    skill_dir = Path.join(project_root, ".agents/skills/project-only")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: project-only
      description: Only available when the project is trusted
      ---
      # Project only
      """
    )

    untrusted = Skills.analyze(project_root)
    refute Enum.any?(untrusted.skills, &(&1.name == "project-only"))
    assert untrusted.trusted_project? == false
    assert Enum.any?(untrusted.diagnostics, &(&1.code == "project_skills_untrusted"))

    trusted = Skills.analyze(project_root, trust_project_skills: true)
    assert trusted.trusted_project? == true
    assert Enum.any?(trusted.skills, &(&1.name == "project-only"))
  end

  test "renderer applies target-family metadata from agents yaml", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "render-skill")
    File.mkdir_p!(Path.join(skill_dir, "agents"))

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: render-skill
      description: Render target-aware instructions
      compatibility:
        - codex
      ---
      # Render Skill
      """
    )

    File.write!(
      Path.join(skill_dir, "agents/codex.yaml"),
      """
      frontmatter:
        role: codex
      instructions_prefix: Use the Codex plugin workflow.
      instructions_suffix: Finish with ControlKeel validation.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    rendered = Renderer.render(skill, target: "codex")

    assert rendered.target_family == "codex"
    assert rendered.metadata["instructions_prefix"] == "Use the Codex plugin workflow."
    assert rendered.content =~ "role: \"codex\""
    assert rendered.content =~ "Use the Codex plugin workflow."
    assert rendered.content =~ "Finish with ControlKeel validation."
  end

  test "built-in skills validate cleanly and expose the full operator catalog" do
    result = Skills.validate(nil)

    assert result.valid? == true
    assert result.error_count == 0

    names = Enum.map(result.skills, & &1.name)

    assert Enum.sort(names) == [
             "agent-integration",
             "benchmark-operator",
             "cloudflare-agent",
             "compliance-audit",
             "controlkeel-governance",
             "cost-optimization",
             "domain-audit",
             "policy-training",
             "proof-memory",
             "security-review",
             "ship-readiness"
           ]

    governance = Enum.find(result.skills, &(&1.name == "controlkeel-governance"))
    assert "codex" in governance.compatibility_targets
    assert "claude-plugin" in governance.compatibility_targets
    assert governance.required_mcp_tools != []
  end

  test "export writes codex and claude plugin bundles", %{tmp_dir: tmp_dir} do
    assert {:ok, codex_plan} = Skills.export("codex", tmp_dir, scope: "export")
    assert codex_plan.target == "codex"

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-operator.toml")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-last.md"))

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, "AGENTS.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, "CONTROLKEEL_INSTALL.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".mcp.hosted.json"))

    assert {:ok, codex_plugin_plan} = Skills.export("codex-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(codex_plugin_plan.output_dir, ".codex-plugin/plugin.json"))
    assert File.exists?(Path.join(codex_plugin_plan.output_dir, "commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(codex_plugin_plan.output_dir, "commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(codex_plugin_plan.output_dir, "commands/controlkeel-last.md"))

    assert File.exists?(
             Path.join(codex_plugin_plan.output_dir, ".agents/plugins/marketplace.json")
           )

    assert File.exists?(Path.join(codex_plugin_plan.output_dir, ".mcp.hosted.json"))

    assert {:ok, claude_plan} = Skills.export("claude-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(claude_plan.output_dir, ".claude-plugin/plugin.json"))

    assert File.exists?(
             Path.join(claude_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(claude_plan.output_dir, "agents/controlkeel-operator.md"))
    assert File.exists?(Path.join(claude_plan.output_dir, ".mcp.json"))
    assert File.exists?(Path.join(claude_plan.output_dir, ".mcp.hosted.json"))
    assert File.exists?(Path.join(claude_plan.output_dir, "settings.json"))
    assert File.exists?(Path.join(claude_plan.output_dir, "hooks/hooks.json"))
    assert File.exists?(Path.join(claude_plan.output_dir, "hooks/controlkeel-review.sh"))
    assert File.exists?(Path.join(claude_plan.output_dir, "hooks/controlkeel-review.ps1"))
    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-review.md"))

    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-annotate.md"))

    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-last.md"))

    assert File.read!(Path.join(claude_plan.output_dir, "CONTROLKEEL_INSTALL.md")) =~
             "@aryaminus/controlkeel"

    assert {:ok, openclaw_plan} = Skills.export("openclaw-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(openclaw_plan.output_dir, "openclaw.plugin.json"))

    assert {:ok, vscode_companion_plan} =
             Skills.export("vscode-companion", tmp_dir, scope: "export")

    assert File.exists?(Path.join(vscode_companion_plan.output_dir, "extension/package.json"))
    assert File.exists?(Path.join(vscode_companion_plan.output_dir, "extension/extension.js"))

    assert {:ok, cline_plan} = Skills.export("cline-native", tmp_dir, scope: "export")

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(cline_plan.output_dir, ".clinerules/controlkeel.md"))

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".clinerules/workflows/controlkeel-review.md")
           )

    assert File.exists?(Path.join(cline_plan.output_dir, ".cline/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(cline_plan.output_dir, ".cline/commands/controlkeel-last.md"))

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/hooks/PreToolUse/controlkeel-review.sh")
           )

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/hooks/TaskStart/controlkeel-context.sh")
           )

    assert File.exists?(
             Path.join(cline_plan.output_dir, ".cline/data/settings/cline_mcp_settings.json")
           )

    assert {:ok, roo_plan} = Skills.export("roo-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(roo_plan.output_dir, ".roo/rules/controlkeel.md"))
    assert File.exists?(Path.join(roo_plan.output_dir, ".roo/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(roo_plan.output_dir, ".roo/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(Path.join(roo_plan.output_dir, ".roo/commands/controlkeel-annotate.md"))

    assert File.exists?(Path.join(roo_plan.output_dir, ".roo/commands/controlkeel-last.md"))

    assert File.exists?(Path.join(roo_plan.output_dir, ".roo/guidance/controlkeel.md"))

    assert File.exists?(
             Path.join(roo_plan.output_dir, ".roo/guidance/controlkeel-cloud-agent.md")
           )

    assert File.exists?(Path.join(roo_plan.output_dir, ".roomodes"))

    assert {:ok, goose_plan} = Skills.export("goose-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(goose_plan.output_dir, ".goosehints"))

    assert File.exists?(
             Path.join(goose_plan.output_dir, "goose/workflow_recipes/controlkeel-review.yaml")
           )

    assert File.exists?(Path.join(goose_plan.output_dir, "goose/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(goose_plan.output_dir, "goose/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(goose_plan.output_dir, "goose/commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(goose_plan.output_dir, "goose/commands/controlkeel-last.md"))

    assert File.exists?(Path.join(goose_plan.output_dir, "goose/controlkeel-extension.yaml"))

    assert File.exists?(
             Path.join(openclaw_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert {:ok, copilot_plan} = Skills.export("copilot-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(copilot_plan.output_dir, "plugin.json"))
    assert File.exists?(Path.join(copilot_plan.output_dir, "hooks.json"))
    assert File.exists?(Path.join(copilot_plan.output_dir, ".mcp.hosted.json"))
    assert File.exists?(Path.join(copilot_plan.output_dir, "commands/controlkeel-plan-review.md"))
    assert File.exists?(Path.join(copilot_plan.output_dir, "commands/controlkeel-review.md"))

    assert File.exists?(Path.join(copilot_plan.output_dir, "commands/controlkeel-annotate.md"))

    assert File.exists?(Path.join(copilot_plan.output_dir, "commands/controlkeel-last.md"))

    assert {:ok, droid_plan} = Skills.export("droid-bundle", tmp_dir, scope: "export")

    assert File.exists?(
             Path.join(droid_plan.output_dir, ".factory/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(droid_plan.output_dir, ".factory/droids/controlkeel.md"))

    assert {:ok, provider_plan} = Skills.export("provider-profile", tmp_dir, scope: "export")
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/vllm.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/sglang.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/lmstudio.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/huggingface.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/ollama.json"))

    assert {:ok, devin_plan} = Skills.export("devin-runtime", tmp_dir, scope: "export")
    assert File.exists?(Path.join(devin_plan.output_dir, "devin/README.md"))
    assert File.exists?(Path.join(devin_plan.output_dir, "devin/controlkeel-mcp.json"))

    assert {:ok, opencode_plan} = Skills.export("opencode-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(opencode_plan.output_dir, "package.json"))

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/plugins/controlkeel-governance.ts")
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/agents/controlkeel-operator.md")
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-review.md")
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-annotate.md")
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-last.md")
           )

    assert File.exists?(Path.join(opencode_plan.output_dir, ".opencode/mcp.json"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "index.js"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "README.md"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "AGENTS.md"))

    opencode_manifest =
      Path.join(opencode_plan.output_dir, "package.json")
      |> File.read!()
      |> Jason.decode!()

    assert opencode_manifest["publishConfig"]["access"] == "public"
    assert opencode_manifest["exports"]["."] == "./index.js"

    assert {:ok, gemini_plan} = Skills.export("gemini-cli-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(gemini_plan.output_dir, "gemini-extension.json"))

    assert File.exists?(
             Path.join(gemini_plan.output_dir, ".gemini/commands/controlkeel/review.toml")
           )

    assert File.exists?(
             Path.join(gemini_plan.output_dir, ".gemini/commands/controlkeel/submit-plan.toml")
           )

    assert File.exists?(
             Path.join(gemini_plan.output_dir, ".gemini/commands/controlkeel/annotate.toml")
           )

    assert File.exists?(
             Path.join(gemini_plan.output_dir, ".gemini/commands/controlkeel/last.toml")
           )

    assert File.exists?(
             Path.join(gemini_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(gemini_plan.output_dir, "GEMINI.md"))
    assert File.exists?(Path.join(gemini_plan.output_dir, "README.md"))

    assert {:ok, pi_plan} = Skills.export("pi-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/controlkeel.json"))
    assert File.exists?(Path.join(pi_plan.output_dir, ".pi/mcp.json"))
    assert File.exists?(Path.join(pi_plan.output_dir, "pi-extension.json"))
    assert File.exists?(Path.join(pi_plan.output_dir, "package.json"))
    assert File.exists?(Path.join(pi_plan.output_dir, "README.md"))
    assert File.exists?(Path.join(pi_plan.output_dir, "PI.md"))

    pi_manifest =
      Path.join(pi_plan.output_dir, "package.json")
      |> File.read!()
      |> Jason.decode!()

    assert pi_manifest["publishConfig"]["access"] == "public"
    assert pi_manifest["exports"]["."] == "./pi-extension.json"

    assert {:ok, kiro_plan} = Skills.export("kiro-native", tmp_dir, scope: "export")
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/hooks/controlkeel-validate.json"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/hooks/controlkeel-review.json"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/steering/controlkeel.md"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/settings/controlkeel-tools.json"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(kiro_plan.output_dir, ".kiro/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(kiro_plan.output_dir, ".kiro/mcp.json"))
    assert File.exists?(Path.join(kiro_plan.output_dir, "AGENTS.md"))

    assert {:ok, amp_plan} = Skills.export("amp-native", tmp_dir, scope: "export")

    assert File.exists?(Path.join(amp_plan.output_dir, ".amp/plugins/controlkeel-governance.ts"))

    assert File.exists?(
             Path.join(amp_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(
             Path.join(amp_plan.output_dir, ".agents/skills/controlkeel-governance/mcp.json")
           )

    assert File.exists?(Path.join(amp_plan.output_dir, ".amp/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(amp_plan.output_dir, ".amp/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(Path.join(amp_plan.output_dir, ".amp/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(amp_plan.output_dir, ".amp/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(amp_plan.output_dir, ".amp/package.json"))

    assert File.exists?(Path.join(amp_plan.output_dir, ".mcp.json"))
    assert File.exists?(Path.join(amp_plan.output_dir, "AGENTS.md"))

    assert {:ok, augment_plan} = Skills.export("augment-native", tmp_dir, scope: "export")

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/agents/controlkeel-operator.md")
           )

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/commands/controlkeel-review.md")
           )

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/commands/controlkeel-annotate.md")
           )

    assert File.exists?(
             Path.join(augment_plan.output_dir, ".augment/commands/controlkeel-last.md")
           )

    assert File.exists?(Path.join(augment_plan.output_dir, ".augment/rules/controlkeel.md"))
    assert File.exists?(Path.join(augment_plan.output_dir, ".augment/mcp.json"))
    assert File.exists?(Path.join(augment_plan.output_dir, ".augment/settings.controlkeel.json"))
    assert File.exists?(Path.join(augment_plan.output_dir, "AUGMENT.md"))
    assert File.exists?(Path.join(augment_plan.output_dir, "AGENTS.md"))

    assert {:ok, augment_plugin_plan} = Skills.export("augment-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, ".augment-plugin/plugin.json"))

    assert File.exists?(
             Path.join(augment_plugin_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(
             Path.join(augment_plugin_plan.output_dir, "agents/controlkeel-operator.md")
           )

    assert File.exists?(
             Path.join(augment_plugin_plan.output_dir, "commands/controlkeel-review.md")
           )

    assert File.exists?(
             Path.join(augment_plugin_plan.output_dir, "commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(augment_plugin_plan.output_dir, "commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(augment_plugin_plan.output_dir, "commands/controlkeel-last.md"))
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, "rules/controlkeel.md"))
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, "hooks/hooks.json"))
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, "hooks/controlkeel-review.sh"))
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, ".mcp.json"))
    assert File.exists?(Path.join(augment_plugin_plan.output_dir, "README.md"))

    assert {:ok, instructions_plan} = Skills.export("instructions-only", tmp_dir, scope: "export")
    assert File.exists?(Path.join(instructions_plan.output_dir, "AIDER.md"))
    assert File.exists?(Path.join(instructions_plan.output_dir, ".aider.conf.yml"))

    assert File.exists?(
             Path.join(instructions_plan.output_dir, ".aider/commands/controlkeel-review.md")
           )

    assert File.exists?(
             Path.join(instructions_plan.output_dir, ".aider/commands/controlkeel-annotate.md")
           )

    assert File.exists?(
             Path.join(instructions_plan.output_dir, ".aider/commands/controlkeel-last.md")
           )
  end

  test "installer writes project-scoped native bundles without nesting agent directories", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, codex_install} = Skills.install("codex", tmp_dir, scope: "project")
    assert codex_install.destination == Path.join(tmp_dir, ".agents/skills")
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".mcp.json"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))

    assert {:ok, claude_install} = Skills.install("claude-standalone", tmp_dir, scope: "project")
    assert claude_install.destination == Path.join(tmp_dir, ".claude/skills")
    assert File.exists?(Path.join(tmp_dir, ".claude/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".claude/agents/controlkeel-operator.md"))

    assert {:ok, github_install} = Skills.install("github-repo", tmp_dir, scope: "project")
    assert github_install.destination == Path.join(tmp_dir, ".github/skills")
    assert File.exists?(Path.join(tmp_dir, ".github/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/agents/controlkeel-operator.agent.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/commands/controlkeel-plan-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/commands/controlkeel-review.md"))

    assert File.exists?(Path.join(tmp_dir, ".github/commands/controlkeel-annotate.md"))

    assert File.exists?(Path.join(tmp_dir, ".github/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".vscode/mcp.json"))

    assert {:ok, hermes_install} = Skills.install("hermes-native", tmp_dir, scope: "project")
    assert hermes_install.destination == Path.join(tmp_dir, ".hermes/skills")
    assert File.exists?(Path.join(tmp_dir, ".hermes/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".hermes/mcp.json"))

    assert {:ok, cline_install} = Skills.install("cline-native", tmp_dir, scope: "project")
    assert cline_install.destination == Path.join(tmp_dir, ".cline/skills")
    assert File.exists?(Path.join(tmp_dir, ".cline/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".clinerules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".clinerules/workflows/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".cline/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".cline/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".cline/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".cline/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".cline/hooks/PreToolUse/controlkeel-review.sh"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))

    assert {:ok, roo_install} = Skills.install("roo-native", tmp_dir, scope: "project")
    assert roo_install.destination == Path.join(tmp_dir, ".roo/skills")
    assert File.exists?(Path.join(tmp_dir, ".roo/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/rules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/guidance/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/guidance/controlkeel-cloud-agent.md"))
    assert File.exists?(Path.join(tmp_dir, ".roomodes"))

    assert {:ok, goose_install} = Skills.install("goose-native", tmp_dir, scope: "project")
    assert goose_install.destination == Path.join(tmp_dir, ".goosehints")
    assert File.exists?(Path.join(tmp_dir, ".goosehints"))
    assert File.exists?(Path.join(tmp_dir, "goose/workflow_recipes/controlkeel-review.yaml"))
    assert File.exists?(Path.join(tmp_dir, "goose/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, "goose/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, "goose/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, "goose/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, "goose/controlkeel-extension.yaml"))

    assert {:ok, opencode_install} =
             Skills.install("opencode-native", tmp_dir, scope: "project")

    assert opencode_install.destination == Path.join(tmp_dir, ".opencode")
    assert File.exists?(Path.join(tmp_dir, ".opencode/plugins/controlkeel-governance.ts"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/agents/controlkeel-operator.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))

    assert {:ok, gemini_install} =
             Skills.install("gemini-cli-native", tmp_dir, scope: "project")

    assert gemini_install.destination == Path.join(tmp_dir, ".gemini")
    assert File.exists?(Path.join(tmp_dir, "gemini-extension.json"))
    assert File.exists?(Path.join(tmp_dir, ".gemini/commands/controlkeel/review.toml"))
    assert File.exists?(Path.join(tmp_dir, ".gemini/commands/controlkeel/submit-plan.toml"))
    assert File.exists?(Path.join(tmp_dir, ".gemini/commands/controlkeel/annotate.toml"))
    assert File.exists?(Path.join(tmp_dir, ".gemini/commands/controlkeel/last.toml"))
    assert File.exists?(Path.join(tmp_dir, "skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, "GEMINI.md"))

    assert {:ok, kiro_install} = Skills.install("kiro-native", tmp_dir, scope: "project")
    assert kiro_install.destination == Path.join(tmp_dir, ".kiro")
    assert File.exists?(Path.join(tmp_dir, ".kiro/hooks/controlkeel-validate.json"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/hooks/controlkeel-review.json"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/steering/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/settings/controlkeel-tools.json"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".kiro/mcp.json"))

    assert {:ok, amp_install} = Skills.install("amp-native", tmp_dir, scope: "project")
    assert amp_install.destination == Path.join(tmp_dir, ".amp")
    assert File.exists?(Path.join(tmp_dir, ".amp/plugins/controlkeel-governance.ts"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".amp/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".amp/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".amp/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".amp/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".mcp.json"))

    assert {:ok, augment_install} = Skills.install("augment-native", tmp_dir, scope: "project")
    assert augment_install.destination == Path.join(tmp_dir, ".augment")
    assert File.exists?(Path.join(tmp_dir, ".augment/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/agents/controlkeel-operator.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/rules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".augment/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".augment/settings.controlkeel.json"))
    assert File.exists?(Path.join(tmp_dir, "AUGMENT.md"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))

    assert {:ok, cursor_install} = Skills.install("cursor-native", tmp_dir, scope: "project")
    assert cursor_install.destination == Path.join(tmp_dir, ".cursor")
    assert File.exists?(Path.join(tmp_dir, ".cursor/rules/controlkeel.mdc"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/background-agents/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))

    assert {:ok, windsurf_install} = Skills.install("windsurf-native", tmp_dir, scope: "project")
    assert windsurf_install.destination == Path.join(tmp_dir, ".windsurf")
    assert File.exists?(Path.join(tmp_dir, ".windsurf/rules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/workflows/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/hooks.json"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/hooks/controlkeel-review.json"))
    assert File.exists?(Path.join(tmp_dir, ".windsurf/mcp.json"))

    assert {:ok, continue_install} = Skills.install("continue-native", tmp_dir, scope: "project")
    assert continue_install.destination == Path.join(tmp_dir, ".continue")
    assert File.exists?(Path.join(tmp_dir, ".continue/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".continue/prompts/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".continue/prompts/controlkeel-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".continue/commands/controlkeel-review.prompt"))
    assert File.exists?(Path.join(tmp_dir, ".continue/commands/controlkeel-submit-plan.prompt"))
    assert File.exists?(Path.join(tmp_dir, ".continue/commands/controlkeel-annotate.prompt"))
    assert File.exists?(Path.join(tmp_dir, ".continue/commands/controlkeel-last.prompt"))
    assert File.exists?(Path.join(tmp_dir, ".continue/mcpServers/controlkeel.yaml"))
    assert File.exists?(Path.join(tmp_dir, ".continue/mcp.json"))

    assert {:ok, aider_install} = Skills.install("instructions-only", tmp_dir, scope: "project")
    assert aider_install.destination == tmp_dir
    assert File.exists?(Path.join(tmp_dir, "AIDER.md"))
    assert File.exists?(Path.join(tmp_dir, ".aider.conf.yml"))
    assert File.exists?(Path.join(tmp_dir, ".aider/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".aider/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".aider/commands/controlkeel-last.md"))

    assert {:ok, codex_plugin_install} = Skills.install("codex-plugin", tmp_dir, scope: "project")
    assert File.exists?(Path.join(codex_plugin_install.destination, ".codex-plugin/plugin.json"))
    assert File.exists?(Path.join(tmp_dir, ".agents/plugins/marketplace.json"))
  end
end
