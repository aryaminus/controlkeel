defmodule ControlKeel.SkillsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Skills
  alias ControlKeel.Skills.Activation
  alias ControlKeel.Skills.Parser

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

  test "built-in skills validate cleanly and expose the full operator catalog" do
    result = Skills.validate(nil)

    assert result.valid? == true
    assert result.error_count == 0

    names = Enum.map(result.skills, & &1.name)

    assert Enum.sort(names) == [
             "agent-integration",
             "benchmark-operator",
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
             Path.join(codex_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, "AGENTS.md"))

    assert {:ok, claude_plan} = Skills.export("claude-plugin", tmp_dir, scope: "export")
    assert File.exists?(Path.join(claude_plan.output_dir, ".claude-plugin/plugin.json"))

    assert File.exists?(
             Path.join(claude_plan.output_dir, "skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(claude_plan.output_dir, "agents/controlkeel-operator.md"))
    assert File.exists?(Path.join(claude_plan.output_dir, ".mcp.json"))
    assert File.exists?(Path.join(claude_plan.output_dir, "settings.json"))
  end

  test "installer writes project-scoped native bundles without nesting agent directories", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, claude_install} = Skills.install("claude-standalone", tmp_dir, scope: "project")
    assert claude_install.destination == Path.join(tmp_dir, ".claude/skills")
    assert File.exists?(Path.join(tmp_dir, ".claude/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".claude/agents/controlkeel-operator.md"))

    assert {:ok, github_install} = Skills.install("github-repo", tmp_dir, scope: "project")
    assert github_install.destination == Path.join(tmp_dir, ".github/skills")
    assert File.exists?(Path.join(tmp_dir, ".github/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/agents/controlkeel-operator.agent.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".vscode/mcp.json"))
  end
end
