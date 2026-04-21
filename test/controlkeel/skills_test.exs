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

  test "registry discovers codex-native project skills when trusted", %{tmp_dir: tmp_dir} do
    project_root = Path.join(tmp_dir, "project")
    skill_dir = Path.join(project_root, ".codex/skills/codex-native")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: codex-native
      description: Native Codex skill
      ---
      # Codex native
      """
    )

    analysis = Skills.analyze(project_root, trust_project_skills: true)
    assert Enum.any?(analysis.skills, &(&1.name == "codex-native"))
  end

  test "registry prefers priv builtin when project copies the same skill name", %{
    tmp_dir: tmp_dir
  } do
    project_root = Path.join(tmp_dir, "project")
    agents_dir = Path.join(project_root, ".agents/skills/controlkeel-governance")
    File.mkdir_p!(agents_dir)

    File.write!(
      Path.join(agents_dir, "SKILL.md"),
      """
      ---
      name: controlkeel-governance
      description: project duplicate
      ---
      # Project duplicate body
      """
    )

    analysis = Skills.analyze(project_root, trust_project_skills: true)
    skill = Enum.find(analysis.skills, &(&1.name == "controlkeel-governance"))
    assert skill
    assert String.contains?(skill.path, "/priv/skills/")
    refute String.contains?(skill.body, "Project duplicate body")
    assert Enum.any?(analysis.diagnostics, &(&1.code == "shadowed_skill"))
  end

  test "registry does not warn when codex and open-standard copies mirror each other", %{
    tmp_dir: tmp_dir
  } do
    project_root = Path.join(tmp_dir, "project")
    codex_dir = Path.join(project_root, ".codex/skills/mirrored-skill")
    compat_dir = Path.join(project_root, ".agents/skills/mirrored-skill")
    File.mkdir_p!(codex_dir)
    File.mkdir_p!(compat_dir)

    skill_contents = """
    ---
    name: mirrored-skill
    description: Mirrored skill copy
    ---
    # Mirrored
    """

    File.write!(Path.join(codex_dir, "SKILL.md"), skill_contents)
    File.write!(Path.join(compat_dir, "SKILL.md"), skill_contents)

    analysis = Skills.analyze(project_root, trust_project_skills: true)
    assert Enum.count(analysis.skills, &(&1.name == "mirrored-skill")) == 1
    refute Enum.any?(analysis.diagnostics, &(&1.code == "shadowed_skill"))
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

  test "parser warns when a custom skill lacks trigger boundaries, workflow, and examples", %{
    tmp_dir: tmp_dir
  } do
    skill_dir = Path.join(tmp_dir, "fragile-skill")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: fragile-skill
      description: Helps with proposals
      ---
      # Fragile Skill

      Write something helpful for the user.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")

    codes = Enum.map(skill.diagnostics, & &1.code)

    assert "weak_trigger_description" in codes
    assert "missing_negative_boundaries" in codes
    assert "missing_workflow_section" in codes
    assert "missing_output_format_section" in codes
    assert "missing_examples_section" in codes
    assert "missing_edge_case_guidance" in codes
  end

  test "parser accepts a well-structured custom skill without skill-quality warnings", %{
    tmp_dir: tmp_dir
  } do
    skill_dir = Path.join(tmp_dir, "proposal-generator")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: proposal-generator
      description: >
        Generates professional business proposals. Use this skill whenever the user asks to
        write a proposal, draft a proposal, create a proposal, or prepare a client-ready
        proposal document. Do not use for internal project plans, SOWs, or technical specs.
      ---
      ## Overview

      Generate a client-ready proposal from project details.

      ## Workflow

      1. Collect the client name, scope, timeline, and pricing status.
      2. Draft the proposal sections in order.
      3. Review the output against the format rules below.

      ## Output Format

      - Markdown
      - 500-800 words
      - H2 headings for each main section

      ## Examples

      Happy path:
      - Input: "Proposal for Acme website redesign, 3 months, $15,000"
      - Expected behavior: produce a complete proposal with pricing.

      Edge case:
      - Input: "Proposal for a client, not sure about pricing yet"
      - Expected behavior: omit pricing and note that pricing is pending if missing.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")

    quality_codes =
      skill.diagnostics
      |> Enum.map(& &1.code)
      |> Enum.filter(&String.contains?(&1, ["trigger", "workflow", "output", "examples", "edge"]))

    assert quality_codes == []
  end

  test "parser warns when a custom skill becomes monolithic without linked references", %{
    tmp_dir: tmp_dir
  } do
    skill_dir = Path.join(tmp_dir, "mega-operator")
    File.mkdir_p!(skill_dir)

    long_sections =
      1..6
      |> Enum.map_join("\n\n", fn index ->
        """
        ## Section #{index}

        #{String.duplicate("Detailed instruction block for repeated operator behavior.\n", 18)}
        """
      end)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: mega-operator
      description: >
        Use this skill whenever the user asks for a multi-step repository workflow, repo analysis,
        release prep, or recurring operator task. Do not use for simple one-off edits or isolated
        questions.
      ---
      ## Overview

      This skill handles a large recurring operator workflow.

      #{long_sections}
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert Enum.any?(skill.diagnostics, &(&1.code == "monolithic_skill_body"))
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

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-reviewer.toml")
           )

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-docs-researcher.toml")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/config.toml"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks.json"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks/ck-session-start.sh"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks/ck-validate-shell.sh"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks/ck-post-tool-use.sh"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks/ck-user-prompt-submit.sh"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".codex/hooks/ck-stop.sh"))

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, "AGENTS.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, "CONTROLKEEL_INSTALL.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".mcp.hosted.json"))
    assert File.read!(Path.join(codex_plan.output_dir, "AGENTS.md")) =~ "Primary CK loop:"

    codex_export_agent =
      File.read!(Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-operator.toml"))

    assert codex_export_agent =~ "controlkeel update --json"
    assert codex_export_agent =~ "developer_instructions = "
    assert codex_export_agent =~ "nickname_candidates = "

    codex_reviewer =
      File.read!(Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-reviewer.toml"))

    assert codex_reviewer =~ ~s(name = "controlkeel-reviewer")
    assert codex_reviewer =~ ~s(sandbox_mode = "read-only")

    codex_docs_researcher =
      File.read!(
        Path.join(codex_plan.output_dir, ".codex/agents/controlkeel-docs-researcher.toml")
      )

    assert codex_docs_researcher =~ ~s(name = "controlkeel-docs-researcher")
    assert codex_docs_researcher =~ ~s(sandbox_mode = "read-only")

    assert File.read!(Path.join(codex_plan.output_dir, ".codex/config.toml")) =~
             "codex_hooks = true"

    codex_hooks =
      Path.join(codex_plan.output_dir, ".codex/hooks.json")
      |> File.read!()
      |> Jason.decode!()

    assert Map.has_key?(codex_hooks["hooks"], "PostToolUse")
    assert Map.has_key?(codex_hooks["hooks"], "UserPromptSubmit")

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

    claude_export_agent =
      File.read!(Path.join(claude_plan.output_dir, "agents/controlkeel-operator.md"))

    assert claude_export_agent =~ "controlkeel update --json"

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

    cline_taskstart_hook =
      File.read!(
        Path.join(cline_plan.output_dir, ".cline/hooks/TaskStart/controlkeel-context.sh")
      )

    assert cline_taskstart_hook =~ "controlkeel update --json"

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

    assert File.exists?(
             Path.join(droid_plan.output_dir, ".factory/commands/controlkeel-review.md")
           )

    assert File.exists?(
             Path.join(droid_plan.output_dir, ".factory/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(droid_plan.output_dir, ".factory/commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(droid_plan.output_dir, ".factory/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(droid_plan.output_dir, ".factory/mcp.json"))

    assert {:ok, droid_plugin_plan} = Skills.export("droid-plugin", tmp_dir, scope: "export")

    assert File.exists?(Path.join(droid_plugin_plan.output_dir, ".factory-plugin/plugin.json"))

    assert File.exists?(
             Path.join(droid_plugin_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "droids/controlkeel.md"))

    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(droid_plugin_plan.output_dir, "commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(
             Path.join(droid_plugin_plan.output_dir, "commands/controlkeel-annotate.md")
           )

    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "commands/controlkeel-last.md"))
    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "hooks/hooks.json"))
    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "mcp.json"))
    assert File.exists?(Path.join(droid_plugin_plan.output_dir, "README.md"))

    assert {:ok, provider_plan} = Skills.export("provider-profile", tmp_dir, scope: "export")
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/vllm.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/sglang.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/lmstudio.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/huggingface.json"))
    assert File.exists?(Path.join(provider_plan.output_dir, "provider-profiles/ollama.json"))

    assert {:ok, devin_plan} = Skills.export("devin-runtime", tmp_dir, scope: "export")
    assert File.exists?(Path.join(devin_plan.output_dir, "devin/README.md"))
    assert File.exists?(Path.join(devin_plan.output_dir, "devin/controlkeel-mcp.json"))

    assert {:ok, executor_plan} = Skills.export("executor-runtime", tmp_dir, scope: "export")
    assert File.exists?(Path.join(executor_plan.output_dir, "executor/README.md"))

    assert File.exists?(
             Path.join(executor_plan.output_dir, "executor/controlkeel-sources.example.ts")
           )

    assert {:ok, virtual_bash_plan} =
             Skills.export("virtual-bash-runtime", tmp_dir, scope: "export")

    assert File.exists?(Path.join(virtual_bash_plan.output_dir, "virtual-bash/README.md"))

    assert File.exists?(
             Path.join(virtual_bash_plan.output_dir, "virtual-bash/controlkeel-runtime.json")
           )

    assert {:ok, letta_plan} = Skills.export("letta-code-native", tmp_dir, scope: "export")

    assert File.exists?(
             Path.join(letta_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(letta_plan.output_dir, ".letta/settings.json"))
    assert File.exists?(Path.join(letta_plan.output_dir, ".letta/settings.local.example.json"))
    assert File.exists?(Path.join(letta_plan.output_dir, ".letta/hooks/controlkeel-findings.sh"))
    assert File.exists?(Path.join(letta_plan.output_dir, ".letta/controlkeel-mcp.sh"))
    assert File.exists?(Path.join(letta_plan.output_dir, ".letta/README.md"))
    assert File.exists?(Path.join(letta_plan.output_dir, ".mcp.json"))
    assert File.exists?(Path.join(letta_plan.output_dir, "AGENTS.md"))

    letta_session_hook =
      File.read!(Path.join(letta_plan.output_dir, ".letta/hooks/controlkeel-session-start.sh"))

    assert letta_session_hook =~ "controlkeel update --json"

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

    assert File.exists?(
             Path.join(
               opencode_plan.output_dir,
               ".opencode/skills/controlkeel-governance/SKILL.md"
             )
           )

    assert File.exists?(
             Path.join(opencode_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(opencode_plan.output_dir, ".opencode/mcp.json"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "index.js"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "README.md"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "AGENTS.md"))
    assert File.exists?(Path.join(opencode_plan.output_dir, "CONTROLKEEL_INSTALL.md"))
    assert File.exists?(Path.join(opencode_plan.output_dir, ".mcp.hosted.json"))

    opencode_install_guide =
      File.read!(Path.join(opencode_plan.output_dir, "CONTROLKEEL_INSTALL.md"))

    assert opencode_install_guide =~ "controlkeel mcp --project-root"
    assert opencode_install_guide =~ "Hosted MCP alternative"

    opencode_manifest =
      Path.join(opencode_plan.output_dir, "package.json")
      |> File.read!()
      |> Jason.decode!()

    assert opencode_manifest["version"] == ControlKeel.CLI.version()
    assert opencode_manifest["publishConfig"]["access"] == "public"
    assert opencode_manifest["exports"]["."] == "./index.js"
    assert opencode_manifest["dependencies"]["@opencode-ai/plugin"] == "1.3.13"

    opencode_plugin =
      Path.join(opencode_plan.output_dir, ".opencode/plugins/controlkeel-governance.ts")
      |> File.read!()

    assert opencode_plugin =~ "tool: {"
    assert opencode_plugin =~ "submit_plan\": tool("
    assert opencode_plugin =~ "--body-file"
    assert opencode_plugin =~ "submitArgs.push(\"--title\", title)"
    assert opencode_plugin =~ "controlkeel version"
    assert opencode_plugin =~ "submitArgs.push(\"--task-id\", reviewScope.taskId)"
    assert opencode_plugin =~ "submitArgs.push(\"--session-id\", reviewScope.sessionId)"
    assert opencode_plugin =~ "CONTROLKEEL_TASK_ID"
    assert opencode_plugin =~ "CONTROLKEEL_SESSION_ID"
    assert opencode_plugin =~ "--project-root"
    assert opencode_plugin =~ "task_id: tool.schema.number().int().positive().optional()"
    assert opencode_plugin =~ "session_id: tool.schema.number().int().positive().optional()"

    assert opencode_plugin =~
             ~S|["controlkeel", "context", "--json", "--project-root", directory]|

    assert opencode_plugin =~ "current_task?.id"
    assert opencode_plugin =~ "reviewScope.taskId"
    assert opencode_plugin =~ "CONTROLKEEL_REVIEW_WAIT_TIMEOUT"
    assert opencode_plugin =~ "String(waitTimeoutSecondsSafe)"
    assert opencode_plugin =~ "Bun.spawn"
    refute opencode_plugin =~ "submitCommand.text(body)"
    assert opencode_plugin =~ "wait_timeout_seconds"
    assert opencode_plugin =~ "Install >= 0.1.26"
    assert opencode_plugin =~ "extractJsonCandidates"
    assert opencode_plugin =~ "JSON.parse(trimmed)"
    assert opencode_plugin =~ "const seen = new Set"
    assert opencode_plugin =~ "pushCandidate(trimmed)"
    assert opencode_plugin =~ "pushCandidate(line)"
    assert opencode_plugin =~ "controlkeel review plan submit failed with exit code"
    assert opencode_plugin =~ "controlkeel review plan wait failed with exit code"
    assert opencode_plugin =~ "new Response(submitProc.stderr).text()"
    assert opencode_plugin =~ "new Response(waitProc.stderr).text()"
    assert opencode_plugin =~ "LOGGER_LEVEL: \"warning\""
    assert opencode_plugin =~ ~S|parseJson([submitOut, submitErr].filter(Boolean).join("\n"))|
    assert opencode_plugin =~ ~S|parseJson([waitOut, waitErr].filter(Boolean).join("\n"))|
    assert opencode_plugin =~ "waitTimedOut"
    assert opencode_plugin =~ "waitPayload?.review?.status === \"pending\""
    assert opencode_plugin =~ "waitMessage.includes(\"timeout\")"
    assert opencode_plugin =~ "waitError.includes(\"timed out\")"
    assert opencode_plugin =~ "timedOut: true"
    assert opencode_plugin =~ "controlkeel review plan open"
    assert opencode_plugin =~ "waitSkipped: true"
    assert opencode_plugin =~ "manualApprovalRequired: true"
    assert opencode_plugin =~ ~S|reason: "review_timeout"|
    assert opencode_plugin =~ "User approved in chat after timeout/browser issue"

    assert opencode_plugin =~
             ~S|reason: !browserUrl ? "browser_url_unavailable" : "browser_unreachable"|

    assert opencode_plugin =~
             "controlkeel review plan respond --id <review_id> --decision approved"

    opencode_agent =
      Path.join(opencode_plan.output_dir, ".opencode/agents/controlkeel-operator.md")
      |> File.read!()

    assert opencode_agent =~ "controlkeel update --json"
    assert opencode_agent =~ "`ck_context`"
    assert opencode_agent =~ "`ck_validate`"
    assert opencode_agent =~ "`ck_review_submit`"
    refute opencode_agent =~ "`ck_findings`"
    refute opencode_agent =~ "`ck_approve`"

    opencode_review_command =
      Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-review.md")
      |> File.read!()

    assert opencode_review_command =~ "`ck_validate`"
    refute opencode_review_command =~ "`ck-validate`"

    opencode_submit_plan_command =
      Path.join(opencode_plan.output_dir, ".opencode/commands/controlkeel-submit-plan.md")
      |> File.read!()

    assert opencode_submit_plan_command =~ "7. Do not execute until the review is approved"
    assert opencode_submit_plan_command =~ "controlkeel version"
    assert opencode_submit_plan_command =~ "--task-id <task_id>"
    assert opencode_submit_plan_command =~ "--session-id <session_id>"
    assert opencode_submit_plan_command =~ "--timeout 30"
    assert opencode_submit_plan_command =~ "`browser_url` is missing/unreachable **or** wait times out while still `pending`"
    assert opencode_submit_plan_command =~ "ControlKeel CLI [object Object] is too old"
    assert opencode_submit_plan_command =~ "Restart OpenCode"

    opencode_mcp =
      Path.join(opencode_plan.output_dir, ".opencode/mcp.json")
      |> File.read!()
      |> Jason.decode!()

    assert get_in(opencode_mcp, ["mcp", "controlkeel", "type"]) == "local"

    opencode_mcp_command = get_in(opencode_mcp, ["mcp", "controlkeel", "command"])
    assert is_list(opencode_mcp_command)
    assert length(opencode_mcp_command) >= 1

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

    assert pi_manifest["version"] == ControlKeel.CLI.version()
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

    assert {:ok, kilo_plan} = Skills.export("kilo-native", tmp_dir, scope: "export")

    assert File.exists?(
             Path.join(kilo_plan.output_dir, ".kilo/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(kilo_plan.output_dir, ".kilo/commands/controlkeel-review.md"))

    assert File.exists?(
             Path.join(kilo_plan.output_dir, ".kilo/commands/controlkeel-submit-plan.md")
           )

    assert File.exists?(Path.join(kilo_plan.output_dir, ".kilo/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(kilo_plan.output_dir, ".kilo/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(kilo_plan.output_dir, ".kilo/kilo.json"))
    assert File.exists?(Path.join(kilo_plan.output_dir, "AGENTS.md"))

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

    augment_export_agent =
      File.read!(Path.join(augment_plan.output_dir, ".augment/agents/controlkeel-operator.md"))

    assert augment_export_agent =~ "controlkeel update --json"

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
    assert codex_install.destination == Path.join(tmp_dir, ".codex/skills")
    assert codex_install.compat_destination == Path.join(tmp_dir, ".agents/skills")
    assert codex_install.hooks_destination == Path.join(tmp_dir, ".codex/hooks")
    assert File.exists?(Path.join(tmp_dir, ".codex/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-reviewer.toml"))
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-docs-researcher.toml"))
    assert File.exists?(Path.join(tmp_dir, ".codex/config.toml"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks.json"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks/ck-session-start.sh"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks/ck-validate-shell.sh"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks/ck-post-tool-use.sh"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks/ck-user-prompt-submit.sh"))
    assert File.exists?(Path.join(tmp_dir, ".codex/hooks/ck-stop.sh"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".mcp.json"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))

    codex_config = File.read!(Path.join(tmp_dir, ".codex/config.toml"))
    assert codex_config =~ "codex_hooks = true"
    assert codex_config =~ "[mcp_servers.controlkeel]"
    assert codex_config =~ ~s(config_file = "./agents/controlkeel-operator.toml")

    codex_agent = File.read!(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    assert codex_agent =~ "controlkeel update --json"
    assert codex_agent =~ "developer_instructions = "
    assert codex_agent =~ "nickname_candidates = "
    refute codex_agent =~ "[context]"
    refute codex_agent =~ "[mcp]"

    codex_reviewer = File.read!(Path.join(tmp_dir, ".codex/agents/controlkeel-reviewer.toml"))
    assert codex_reviewer =~ ~s(name = "controlkeel-reviewer")

    codex_docs_researcher =
      File.read!(Path.join(tmp_dir, ".codex/agents/controlkeel-docs-researcher.toml"))

    assert codex_docs_researcher =~ ~s(name = "controlkeel-docs-researcher")

    assert {:ok, claude_install} = Skills.install("claude-standalone", tmp_dir, scope: "project")
    assert claude_install.destination == Path.join(tmp_dir, ".claude/skills")
    assert File.exists?(Path.join(tmp_dir, ".claude/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".claude/agents/controlkeel-operator.md"))

    claude_install_agent =
      File.read!(Path.join(tmp_dir, ".claude/agents/controlkeel-operator.md"))

    assert claude_install_agent =~ "controlkeel update --json"

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

    cline_install_hook =
      File.read!(Path.join(tmp_dir, ".cline/hooks/TaskStart/controlkeel-context.sh"))

    assert cline_install_hook =~ "controlkeel update --json"

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
    assert File.exists?(Path.join(tmp_dir, ".opencode/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))
    assert opencode_install.skills_destination == Path.join(tmp_dir, ".opencode/skills")

    assert opencode_install.compat_skills_destination ==
             Path.join(tmp_dir, ".agents/skills")

    opencode_install_agent =
      File.read!(Path.join(tmp_dir, ".opencode/agents/controlkeel-operator.md"))

    assert opencode_install_agent =~ "controlkeel update --json"

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

    assert {:ok, kilo_install} = Skills.install("kilo-native", tmp_dir, scope: "project")
    assert kilo_install.destination == Path.join(tmp_dir, ".kilo")
    assert File.exists?(Path.join(tmp_dir, ".kilo/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/kilo.json"))

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

    augment_install_agent =
      File.read!(Path.join(tmp_dir, ".augment/agents/controlkeel-operator.md"))

    assert augment_install_agent =~ "controlkeel update --json"

    assert {:ok, cursor_install} = Skills.install("cursor-native", tmp_dir, scope: "project")
    assert cursor_install.destination == Path.join(tmp_dir, ".cursor")
    assert cursor_install.plugin_destination == Path.join(tmp_dir, ".cursor-plugin")
    assert File.exists?(Path.join(tmp_dir, ".cursor/rules/controlkeel.mdc"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-submit-plan.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-annotate.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-last.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/background-agents/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))

    cursor_mcp = Jason.decode!(File.read!(Path.join(tmp_dir, ".cursor/mcp.json")))

    assert get_in(cursor_mcp, ["mcpServers", "controlkeel", "env", "MIX_QUIET"]) == "1"
    assert get_in(cursor_mcp, ["mcpServers", "controlkeel", "env", "CK_MCP_MODE"]) == "1"

    assert File.exists?(Path.join(tmp_dir, ".cursor/hooks.json"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/hooks/ck-session-start.sh"))
    assert File.exists?(Path.join(tmp_dir, ".cursor-plugin/plugin.json"))
    assert File.exists?(Path.join(tmp_dir, ".cursor-plugin/hooks/hooks.json"))
    assert File.exists?(Path.join(tmp_dir, ".cursor-plugin/hooks/ck-mcp-gate.sh"))
    assert File.exists?(Path.join(tmp_dir, ".cursor-plugin/rules/controlkeel.mdc"))

    assert File.exists?(
             Path.join(tmp_dir, ".cursor-plugin/skills/controlkeel-governance/SKILL.md")
           )

    plugin = Jason.decode!(File.read!(Path.join(tmp_dir, ".cursor-plugin/plugin.json")))

    assert get_in(plugin, ["mcpServers", "controlkeel", "env", "CK_PROJECT_ROOT"]) ==
             "${workspaceFolder}"

    assert get_in(plugin, ["hooks"]) == "./hooks/hooks.json"

    session_start_hook = File.read!(Path.join(tmp_dir, ".cursor/hooks/ck-session-start.sh"))
    assert session_start_hook =~ "controlkeel update --json"
    assert session_start_hook =~ "CK_UPDATE_AVAILABLE"

    cursor_agent = File.read!(Path.join(tmp_dir, ".cursor/agents/controlkeel-governor.md"))
    assert cursor_agent =~ "controlkeel update --json"

    background_agent =
      File.read!(Path.join(tmp_dir, ".cursor/background-agents/controlkeel.md"))

    assert background_agent =~ "controlkeel update --json"

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

    assert {:ok, letta_install} = Skills.install("letta-code-native", tmp_dir, scope: "project")
    assert letta_install.destination == Path.join(tmp_dir, ".letta")
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".letta/settings.json"))
    assert File.exists?(Path.join(tmp_dir, ".letta/settings.local.example.json"))
    assert File.exists?(Path.join(tmp_dir, ".letta/hooks/controlkeel-session-start.sh"))
    assert File.exists?(Path.join(tmp_dir, ".letta/controlkeel-mcp.sh"))
    assert File.exists?(Path.join(tmp_dir, ".letta/README.md"))
    assert File.exists?(Path.join(tmp_dir, ".mcp.json"))

    letta_install_hook =
      File.read!(Path.join(tmp_dir, ".letta/hooks/controlkeel-session-start.sh"))

    assert letta_install_hook =~ "controlkeel update --json"

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

  test "codex post-tool-use hook only warns on explicit failures", %{tmp_dir: tmp_dir} do
    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

    hook_path = Path.join(tmp_dir, ".codex/hooks/ck-post-tool-use.sh")

    success_with_error_word =
      Jason.encode!(%{
        "tool_input" => %{"command" => "rg error lib"},
        "tool_response" => "docs mention error handling",
        "exit_code" => 0
      })

    {success_output, 0} =
      System.cmd("sh", ["-c", "printf '%s' \"$CK_TEST_INPUT\" | sh \"$CK_HOOK_PATH\""],
        env: [{"CK_TEST_INPUT", success_with_error_word}, {"CK_HOOK_PATH", hook_path}]
      )

    assert success_output == ""

    failing_test_command =
      Jason.encode!(%{
        "tool_input" => %{"command" => "mix test"},
        "tool_response" => "1 failure",
        "exit_code" => 2
      })

    {failure_output, 0} =
      System.cmd("sh", ["-c", "printf '%s' \"$CK_TEST_INPUT\" | sh \"$CK_HOOK_PATH\""],
        env: [{"CK_TEST_INPUT", failing_test_command}, {"CK_HOOK_PATH", hook_path}]
      )

    assert failure_output =~ "test-oriented shell step"
  end

  test "codex stop hook warns instead of blocking when blocked findings exist", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

    hook_path = Path.join(tmp_dir, ".codex/hooks/ck-stop.sh")
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    controlkeel_stub = Path.join(bin_dir, "controlkeel")

    File.write!(
      controlkeel_stub,
      """
      #!/usr/bin/env sh
      printf '%s' '{"active_findings":{"blocked":4}}'
      """
    )

    File.chmod!(controlkeel_stub, 0o755)

    payload =
      Jason.encode!(%{
        "session_id" => 1,
        "stop_hook_active" => false
      })

    {output, 0} =
      System.cmd("sh", ["-c", "printf '%s' \"$CK_TEST_INPUT\" | sh \"$CK_HOOK_PATH\""],
        env: [
          {"CK_TEST_INPUT", payload},
          {"CK_HOOK_PATH", hook_path},
          {"PATH", "#{bin_dir}:#{System.get_env("PATH")}"}
        ]
      )

    refute output =~ "\"decision\":\"block\""
    assert output =~ "\"systemMessage\""
    assert output =~ "blocked findings"
  end

  test "installer preserves existing AGENTS instructions and manages the CK block", %{
    tmp_dir: tmp_dir
  } do
    repo_instructions = """
    # Repo Instructions

    Keep Phoenix guidance here.
    """

    File.write!(Path.join(tmp_dir, "AGENTS.md"), repo_instructions)

    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

    agents_path = Path.join(tmp_dir, "AGENTS.md")
    agents_contents = File.read!(agents_path)

    assert agents_contents =~ "# Repo Instructions"
    assert agents_contents =~ "<!-- controlkeel:start -->"
    assert agents_contents =~ "Primary CK loop:"
    assert agents_contents =~ "<!-- controlkeel:end -->"

    assert {:ok, _install} = Skills.install("cline-native", tmp_dir, scope: "project")

    updated_contents = File.read!(agents_path)

    assert updated_contents =~ "# Repo Instructions"
    assert String.split(updated_contents, "<!-- controlkeel:start -->") |> length() == 2
    assert String.split(updated_contents, "<!-- controlkeel:end -->") |> length() == 2
  end

  test "codex plugin install writes a local marketplace entry and plugin bundle", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, codex_plugin_install} = Skills.install("codex-plugin", tmp_dir, scope: "project")

    assert codex_plugin_install.destination == Path.join(tmp_dir, "plugins/controlkeel")

    assert codex_plugin_install.marketplace_destination ==
             Path.join(tmp_dir, ".agents/plugins/marketplace.json")

    assert File.exists?(Path.join(tmp_dir, "plugins/controlkeel/.codex-plugin/plugin.json"))

    marketplace =
      Path.join(tmp_dir, ".agents/plugins/marketplace.json")
      |> File.read!()
      |> Jason.decode!()

    assert marketplace["name"] == "controlkeel"
    assert get_in(marketplace, ["interface", "displayName"]) == "ControlKeel"

    [plugin] = marketplace["plugins"]
    assert plugin["name"] == "controlkeel"
    assert get_in(plugin, ["source", "source"]) == "local"
    assert get_in(plugin, ["source", "path"]) == "./plugins/controlkeel"
  end

  test "cursor-native MCP uses bin/controlkeel-mcp when the tree looks like the source repo", %{
    tmp_dir: tmp_dir
  } do
    File.mkdir_p!(Path.join(tmp_dir, "lib/controlkeel"))
    File.write!(Path.join(tmp_dir, "lib/controlkeel/application.ex"), "# fixture\n")
    File.mkdir_p!(Path.join(tmp_dir, "bin"))
    File.write!(Path.join(tmp_dir, "bin/controlkeel-mcp"), "#!/bin/sh\necho ok\n")

    assert {:ok, _} = Skills.install("cursor-native", tmp_dir, scope: "project")

    mcp = Jason.decode!(File.read!(Path.join(tmp_dir, ".cursor/mcp.json")))

    assert get_in(mcp, ["mcpServers", "controlkeel", "command"]) ==
             "${workspaceFolder}/bin/controlkeel-mcp"

    assert get_in(mcp, ["mcpServers", "controlkeel", "args"]) == []
  end
end
