defmodule ControlKeel.SkillsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Skills
  alias ControlKeel.Skills.Activation
  alias ControlKeel.Skills.Parser
  alias ControlKeel.Skills.Renderer

  @root Path.expand("../..", __DIR__)

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-skills-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    original_home = System.get_env("HOME")
    original_controlkeel_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("HOME", tmp_dir)
    System.put_env("CONTROLKEEL_HOME", tmp_dir)

    on_exit(fn ->
      if original_home do
        System.put_env("HOME", original_home)
      else
        System.delete_env("HOME")
      end

      if original_controlkeel_home do
        System.put_env("CONTROLKEEL_HOME", original_controlkeel_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
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

  test "parser normalizes modern skill frontmatter and surfaces portability diagnostics", %{
    tmp_dir: tmp_dir
  } do
    skill_dir = Path.join(tmp_dir, "modern-skill")
    File.mkdir_p!(skill_dir)

    File.write!(Path.join(skill_dir, "SKILL.md"), """
    ---
    name: modern-skill
    description: Use this for isolated security review. Do not use for general coding.
    context: fork
    agent: Explore
    allowed-tools: Read Grep
    disallowed-tools:
      - Bash
    paths:
      - lib/**/*.ex
    hooks:
      PreToolUse:
        - matcher: Bash
          hooks:
            - type: command
              command: ./validate.sh
    model: sonnet
    effort: high
    shell: bash
    ---
    # Modern Skill

    ## Workflow
    1. Review the target.

    ## Output Format
    Return findings.

    ## Example
    One issue.

    Edge case: if input is missing, ask for a path.
    """)

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert skill.context == "fork"
    assert skill.agent == "Explore"
    assert skill.allowed_tools == ["Read", "Grep"]
    assert skill.disallowed_tools == ["Bash"]
    assert skill.paths == ["lib/**/*.ex"]
    assert skill.hooks["PreToolUse"]
    assert skill.model == "sonnet"
    assert skill.effort == "high"
    assert skill.shell == "bash"
    assert Enum.any?(skill.diagnostics, &(&1.code == "context_fork_target_variance"))
    assert Enum.any?(skill.diagnostics, &(&1.code == "skill_hooks_target_variance"))
  end

  test "parser populates owner from top-level frontmatter and metadata.owner fallback", %{
    tmp_dir: tmp_dir
  } do
    skill_dir_a = Path.join(tmp_dir, "owned-a")
    File.mkdir_p!(skill_dir_a)

    File.write!(Path.join(skill_dir_a, "SKILL.md"), """
    ---
    name: owned-a
    description: Use this for data pipeline work. Do not use for UI tasks.
    owner: data-team
    ---
    # Owned A
    """)

    assert {:ok, skill_a} = Parser.parse(Path.join(skill_dir_a, "SKILL.md"), "project")
    assert skill_a.owner == "data-team"

    skill_dir_b = Path.join(tmp_dir, "owned-b")
    File.mkdir_p!(skill_dir_b)

    File.write!(Path.join(skill_dir_b, "SKILL.md"), """
    ---
    name: owned-b
    description: Use this for security audits. Do not use for general reviews.
    metadata:
      owner: security-team
    ---
    # Owned B
    """)

    assert {:ok, skill_b} = Parser.parse(Path.join(skill_dir_b, "SKILL.md"), "project")
    assert skill_b.owner == "security-team"

    skill_dir_c = Path.join(tmp_dir, "unowned")
    File.mkdir_p!(skill_dir_c)

    File.write!(Path.join(skill_dir_c, "SKILL.md"), """
    ---
    name: unowned
    description: Use this for general tasks. Do not use for critical paths.
    ---
    # Unowned
    """)

    assert {:ok, skill_c} = Parser.parse(Path.join(skill_dir_c, "SKILL.md"), "project")
    assert skill_c.owner == nil
  end

  test "parser computes a stable content_hash over SKILL.md and resource files", %{
    tmp_dir: tmp_dir
  } do
    skill_dir = Path.join(tmp_dir, "hashable-skill")
    File.mkdir_p!(Path.join(skill_dir, "references"))

    skill_content = """
    ---
    name: hashable-skill
    description: Use for hashing tests. Do not use in production.
    ---
    # Hashable Skill
    """

    ref_content = "# Reference\nSome reference content.\n"

    File.write!(Path.join(skill_dir, "SKILL.md"), skill_content)
    File.write!(Path.join(skill_dir, "references/guide.md"), ref_content)

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert is_binary(skill.content_hash)
    assert String.length(skill.content_hash) == 64
    assert skill.content_hash =~ ~r/^[0-9a-f]+$/

    # Same content produces same hash (deterministic)
    assert {:ok, skill2} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert skill.content_hash == skill2.content_hash

    # Changing a resource changes the hash
    File.write!(Path.join(skill_dir, "references/guide.md"), ref_content <> "\nExtra line.\n")
    assert {:ok, skill3} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert skill.content_hash != skill3.content_hash

    # Changing SKILL.md itself changes the hash
    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      String.replace(skill_content, "# Hashable Skill", "# Modified Skill")
    )

    assert {:ok, skill4} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")
    assert skill.content_hash != skill4.content_hash
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

  test "parser warns about third-party skill frontmatter drift", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "third-party-skill")
    File.mkdir_p!(skill_dir)

    long_when_to_use = String.duplicate("Use for carefully scoped validation work. ", 45)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: third-party-skill
      description: >
        Use this skill whenever the user asks for third-party validation. Do not use for
        unrelated implementation work or production deploys.
      when_to_use: "#{long_when_to_use}"
      version: "1.0.0"
      triggers:
        - legacy-trigger
      bespoke-field: "host-specific"
      ---
      ## Overview

      Validate imported skill material without trusting it blindly.

      ## Workflow

      1. Inspect the skill metadata.
      2. Check examples and references.
      3. Report compatibility risks.

      ## Output Format

      - Markdown findings.

      ## Examples

      Happy path:
      - Input: "Review this external skill pack."
      - Expected behavior: flag drift and preserve useful patterns.

      Edge case:
      - Input: "Install this immediately."
      - Expected behavior: ask for review before installation if missing trust.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")

    codes = Enum.map(skill.diagnostics, & &1.code)

    assert "unsupported_frontmatter_field" in codes
    assert "activation_metadata_too_long" in codes
  end

  test "parser warns when daemon role fields are used as skill metadata", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "docs-librarian")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: docs-librarian
      description: Use this skill when asked to review documentation upkeep workflows. Do not use for direct production publishing.
      id: docs-librarian
      purpose: Keep docs aligned with shipped behavior.
      watch:
        - when a pull request is merged
      routines:
        - propose docs updates for changed behavior
      deny:
        - publish externally visible docs
      schedule: "0 9 * * *"
      ---
      ## Workflow

      1. Review the requested documentation workflow.
      2. Identify missing verification or approval gates.
      3. Return focused recommendations.

      ## Output Format

      - Findings
      - Suggested edits

      ## Examples

      Good:
      - Input: "Review this docs maintenance role."
      - Expected behavior: warn if role fields are mixed into skill metadata.
      """
    )

    assert {:ok, skill} = Parser.parse(Path.join(skill_dir, "SKILL.md"), "project")

    refute Enum.any?(skill.diagnostics, &(&1.code == "unsupported_frontmatter_field"))

    assert skill.diagnostics
           |> Enum.filter(&(&1.code == "daemon_frontmatter_in_skill"))
           |> Enum.map(& &1.message)
           |> tap(fn messages -> assert length(messages) == 6 end)
           |> Enum.any?(&String.contains?(&1, "DAEMON.md-style surface"))
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
             "agent-pattern-verification",
             "align",
             "architect-first",
             "benchmark-operator",
             "bounded-loop",
             "challenge",
             "cli-for-agents",
             "cloudflare-agent",
             "communication-style",
             "compliance-audit",
             "continual-learning",
             "continuity",
             "controlkeel-governance",
             "cost-optimization",
             "deep-code-quality-review",
             "deslop",
             "domain-audit",
             "end-of-shift",
             "false-confidence-test-audit",
             "handoff",
             "investigate",
             "orchestrate-tasks",
             "parallel-review",
             "plan-slice",
             "proof-memory",
             "reviewable-pr",
             "security-review",
             "ship-readiness",
             "standup-summary",
             "tdd-bugfix"
           ]

    governance = Enum.find(result.skills, &(&1.name == "controlkeel-governance"))
    assert "codex" in governance.compatibility_targets
    assert "claude-plugin" in governance.compatibility_targets
    assert governance.required_mcp_tools != []
  end

  test "consequential built-in skills require explicit model invocation" do
    result = Skills.validate(nil)

    for name <- [
          "cost-optimization",
          "end-of-shift",
          "false-confidence-test-audit",
          "handoff",
          "orchestrate-tasks",
          "parallel-review",
          "ship-readiness"
        ] do
      skill = Enum.find(result.skills, &(&1.name == name))
      assert skill, "missing built-in skill #{name}"
      assert skill.disable_model_invocation, "#{name} must require explicit invocation"
    end
  end

  test "closure and test audit skills expose typed result schemas" do
    result = Skills.validate(nil)

    for name <- ["end-of-shift", "false-confidence-test-audit"] do
      skill = Enum.find(result.skills, &(&1.name == name))
      assert skill.result_schema["type"] == "object"
      assert is_list(skill.result_schema["required"])
    end
  end

  test "built-in skills include observability loop guidance" do
    root = Path.expand("../..", __DIR__)
    skills = ["benchmark-operator", "proof-memory", "ship-readiness"]

    for skill <- skills do
      contents = File.read!(Path.join([root, "priv/skills", skill, "SKILL.md"]))
      assert contents =~ "ck_observability"
    end

    assert File.read!(Path.join([root, "priv/skills/ship-readiness/SKILL.md"])) =~
             "loop_status"

    for target <- [".claude/skills", ".github/skills"],
        File.dir?(Path.join(root, target)),
        skill <- skills do
      path = Path.join([root, target, skill, "SKILL.md"])

      if File.exists?(path) do
        assert File.read!(path) =~ "ck_observability"
      end
    end
  end

  test "governance requires explicit or plan-approved delegation" do
    contents =
      File.read!(Path.join([@root, "priv/skills/controlkeel-governance/SKILL.md"]))

    assert contents =~ "Delegate only when the user explicitly requests it"
    assert contents =~ "Tool availability alone is not a reason to delegate"
  end

  test "export writes codex and claude plugin bundles", %{tmp_dir: tmp_dir} do
    assert {:ok, codex_plan} = Skills.export("codex", tmp_dir, scope: "export")
    assert codex_plan.target == "codex"
    assert File.exists?(Path.join(codex_plan.output_dir, ".controlkeel-manifest.json"))

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

    codex_session_hook =
      File.read!(Path.join(codex_plan.output_dir, ".codex/hooks/ck-session-start.sh"))

    assert codex_session_hook =~ "ck_run context --session-id"
    assert codex_session_hook =~ "CONTROLKEEL_HOOK_TIMEOUT_SECONDS"
    refute codex_session_hook =~ "set -eu"

    codex_validate_hook =
      File.read!(Path.join(codex_plan.output_dir, ".codex/hooks/ck-validate-shell.sh"))

    assert codex_validate_hook =~ "ck_run validate --content"
    refute codex_validate_hook =~ "set -eu"

    codex_stop_hook =
      File.read!(Path.join(codex_plan.output_dir, ".codex/hooks/ck-stop.sh"))

    assert codex_stop_hook =~ "ck_run context --session-id"
    assert codex_stop_hook =~ "CONTROLKEEL_STOP_HOOK_TIMEOUT_SECONDS"
    refute codex_stop_hook =~ "set -eu"

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".agents/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(
             Path.join(codex_plan.output_dir, ".codex/skills/controlkeel-governance/SKILL.md")
           )

    assert File.exists?(Path.join(codex_plan.output_dir, "AGENTS.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, "CONTROLKEEL_INSTALL.md"))
    assert File.exists?(Path.join(codex_plan.output_dir, ".controlkeel-manifest.json"))
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

    codex_hooks_json = Jason.encode!(codex_hooks)
    assert codex_hooks_json =~ "CK_PROJECT_ROOT"
    assert codex_hooks_json =~ ".codex/hooks/ck-session-start.sh"
    assert codex_hooks_json =~ ".codex/hooks/ck-user-prompt-submit.sh"
    refute codex_hooks_json =~ "sh .codex/hooks"

    codex_prompt_hook = Path.join(codex_plan.output_dir, ".codex/hooks/ck-user-prompt-submit.sh")

    assert prompt_hook_output(codex_prompt_hook, "Use task-scoped review context") == ""

    assert prompt_hook_output(
             codex_prompt_hook,
             "Use " <> ("sk-" <> String.duplicate("a", 24)) <> " for this request"
           ) =~ "Potential secret material detected"

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

    assert skill_dir_names(Path.join(@root, "priv/skills")) ==
             skill_dir_names(Path.join(codex_plugin_plan.output_dir, "skills"))

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

    claude_review_sh =
      File.read!(Path.join(claude_plan.output_dir, "hooks/controlkeel-review.sh"))

    assert claude_review_sh =~ "ck_run review plan submit"
    refute claude_review_sh =~ "set -eu"

    claude_validate_shell =
      File.read!(Path.join(claude_plan.output_dir, "hooks/ck-validate-shell.sh"))

    assert claude_validate_shell =~ "ck_run validate --content"
    assert claude_validate_shell =~ "CONTROLKEEL_HOOK_TIMEOUT_SECONDS"
    refute claude_validate_shell =~ "set -eu"

    claude_session_end =
      File.read!(Path.join(claude_plan.output_dir, "hooks/ck-session-end.sh"))

    assert claude_session_end =~ "ck_run context --session-id"
    refute claude_session_end =~ "set -eu"
    assert File.exists?(Path.join(claude_plan.output_dir, "hooks/controlkeel-review.ps1"))
    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-review.md"))

    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-annotate.md"))

    assert File.exists?(Path.join(claude_plan.output_dir, "commands/controlkeel-last.md"))

    assert File.read!(Path.join(claude_plan.output_dir, "CONTROLKEEL_INSTALL.md")) =~
             "@aryaminus/controlkeel"

    claude_export_agent =
      File.read!(Path.join(claude_plan.output_dir, "agents/controlkeel-operator.md"))

    assert claude_export_agent =~ "controlkeel update --json"
  end

  test "export and claude install stay idempotent with pre-existing dist and partial skill trees",
       %{
         tmp_dir: tmp_dir
       } do
    dist_root = Path.join(tmp_dir, "controlkeel/dist/codex")
    File.mkdir_p!(dist_root)
    File.write!(Path.join(dist_root, "stale.txt"), "stale")

    assert {:ok, first_plan} = Skills.export("codex", tmp_dir, scope: "export")
    assert File.exists?(Path.join(first_plan.output_dir, ".codex/config.toml"))

    assert {:ok, second_plan} = Skills.export("codex", tmp_dir, scope: "export")
    assert second_plan.output_dir == first_plan.output_dir
    refute File.exists?(Path.join(second_plan.output_dir, "stale.txt"))

    stale_cloudflare_root = Path.join(tmp_dir, ".claude/skills/cloudflare-agent")
    File.mkdir_p!(stale_cloudflare_root)
    File.write!(Path.join(stale_cloudflare_root, "SKILL.md"), "stale\n")

    assert {:ok, install} = Skills.install("claude-standalone", tmp_dir, scope: "project")
    assert install.destination == Path.join(tmp_dir, ".claude/skills")

    assert File.exists?(
             Path.join(
               tmp_dir,
               ".claude/skills/cloudflare-agent/references/cloudflare-integration.md"
             )
           )
  end

  test "re-install prunes CK's stale skills but never user-authored ones", %{tmp_dir: tmp_dir} do
    assert {:ok, install} = Skills.install("claude-standalone", tmp_dir, scope: "project")
    skills_root = install.destination
    manifest_path = Path.join(skills_root, ".controlkeel-skills.json")

    # CK wrote a manifest of the skills it installed.
    assert File.exists?(manifest_path)
    %{"skills" => installed} = Jason.decode!(File.read!(manifest_path))
    assert is_list(installed) and installed != []

    # Simulate a skill CK installed in a PRIOR run that no longer exists, plus
    # a skill the USER authored by hand in the same directory.
    stale_ck = Path.join(skills_root, "retired-ck-skill")
    File.mkdir_p!(stale_ck)
    File.write!(Path.join(stale_ck, "SKILL.md"), "old\n")

    user_skill = Path.join(skills_root, "my-handwritten-skill")
    File.mkdir_p!(user_skill)
    File.write!(Path.join(user_skill, "SKILL.md"), "mine\n")

    # Record the stale skill (but NOT the user's) in CK's manifest.
    File.write!(
      manifest_path,
      Jason.encode!(%{"schema_version" => 1, "skills" => installed ++ ["retired-ck-skill"]}) <>
        "\n"
    )

    assert {:ok, _} = Skills.install("claude-standalone", tmp_dir, scope: "project")

    # CK's orphan is pruned; the user's hand-authored skill is untouched.
    refute File.exists?(stale_ck)
    assert File.exists?(Path.join(user_skill, "SKILL.md"))
    refute Jason.decode!(File.read!(manifest_path))["skills"] |> Enum.member?("retired-ck-skill")
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
          {"CK_PROJECT_ROOT", tmp_dir},
          {"PATH", "#{bin_dir}:#{System.get_env("PATH")}"}
        ]
      )

    refute output =~ "\"decision\":\"block\""
    assert output =~ "\"systemMessage\""
    assert output =~ "blocked findings"
  end

  test "codex stop hook tolerates malformed hook input", %{tmp_dir: tmp_dir} do
    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

    hook_path = Path.join(tmp_dir, ".codex/hooks/ck-stop.sh")

    {output, 0} =
      System.cmd("sh", ["-c", "printf '%s' \"$CK_TEST_INPUT\" | sh \"$CK_HOOK_PATH\""],
        env: [
          {"CK_TEST_INPUT", "not-json"},
          {"CK_HOOK_PATH", hook_path}
        ]
      )

    assert output == ""
  end

  test "installer removes broken ControlKeel comment fragments", %{tmp_dir: tmp_dir} do
    repo_instructions = """
    # Repo Instructions

    Keep Phoenix guidance here.

    <!-- controlkee
    """

    File.write!(Path.join(tmp_dir, "AGENTS.md"), repo_instructions)

    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

    agents_contents = File.read!(Path.join(tmp_dir, "AGENTS.md"))

    refute agents_contents =~ ~r/<!--\s*controlkee(?!l:(?:start|end))/i
    assert agents_contents =~ "<!-- controlkeel:start -->"
    assert agents_contents =~ "<!-- controlkeel:end -->"
    assert String.split(agents_contents, "<!-- controlkeel:start -->") |> length() == 2
    assert String.split(agents_contents, "<!-- controlkeel:end -->") |> length() == 2
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

    assert {:ok, _install} = Skills.install("codex", tmp_dir, scope: "project")

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

  test "cursor-native MCP stays portable when a bootstrap wrapper exists", %{tmp_dir: tmp_dir} do
    :ok = ControlKeel.Project.Binding.ensure_mcp_wrapper(tmp_dir)
    wrapper = ControlKeel.Project.Binding.mcp_wrapper_path(tmp_dir)
    assert File.exists?(wrapper)

    assert {:ok, _} = Skills.install("cursor-native", tmp_dir, scope: "project")

    mcp = Jason.decode!(File.read!(Path.join(tmp_dir, ".cursor/mcp.json")))
    command = get_in(mcp, ["mcpServers", "controlkeel", "command"])
    args = get_in(mcp, ["mcpServers", "controlkeel", "args"])

    refute String.contains?(command || "", tmp_dir)
    assert command == "controlkeel"
    assert args == ["mcp", "--project-root", "."]
  end

  test "cursor plugin manifest MCP stays portable for marketplace installs", %{tmp_dir: tmp_dir} do
    manifest = ControlKeel.Skills.Exporter.cursor_plugin_manifest(tmp_dir, version: "1.2.3")
    server = get_in(manifest, ["mcpServers", "controlkeel"])

    assert server["command"] == "controlkeel"
    assert server["args"] == ["mcp", "--project-root", "."]
    assert get_in(server, ["env", "CK_PROJECT_ROOT"]) == "${workspaceFolder}"
    refute String.contains?(inspect(server), tmp_dir)
  end

  test "project-local MCP configs stay portable even when a bootstrap wrapper exists", %{
    tmp_dir: tmp_dir
  } do
    # A bootstrap wrapper exists on disk — the legacy behavior baked its
    # absolute path into committed configs, breaking teammates/moves.
    :ok = ControlKeel.Project.Binding.ensure_mcp_wrapper(tmp_dir)
    wrapper = ControlKeel.Project.Binding.mcp_wrapper_path(tmp_dir)
    assert File.exists?(wrapper)

    assert {:ok, _} = Skills.install("opencode-native", tmp_dir, scope: "project")

    opencode_mcp = Jason.decode!(File.read!(Path.join(tmp_dir, ".opencode/mcp.json")))
    command = get_in(opencode_mcp, ["mcp", "controlkeel", "command"])

    # The absolute wrapper path must never leak into the committable config.
    refute command == [wrapper]
    refute Enum.any?(command, &String.starts_with?(&1, tmp_dir))
    assert hd(command) == "controlkeel"
    assert tl(command) == ["mcp", "--project-root", "."]
  end

  test "cursor-native install does not downgrade plugin.json when existing version is newer", %{
    tmp_dir: tmp_dir
  } do
    # Write a plugin.json that claims a far-future version — simulates a
    # source-synced install that is newer than the currently running binary.
    plugin_dir = Path.join(tmp_dir, ".cursor-plugin")
    File.mkdir_p!(plugin_dir)

    future_version = "99.0.0"

    File.write!(
      Path.join(plugin_dir, "plugin.json"),
      Jason.encode!(%{"name" => "controlkeel", "version" => future_version}, pretty: true) <> "\n"
    )

    # Install should succeed but must NOT overwrite the newer version.
    assert {:ok, result} = Skills.install("cursor-native", tmp_dir, scope: "project")

    plugin = Jason.decode!(File.read!(Path.join(plugin_dir, "plugin.json")))
    assert plugin["version"] == future_version

    # The install result must report the guard fired and carry the on-disk version
    # so the sync layer records the correct version in the binding.
    assert result[:version_guarded] == true
    assert result[:recorded_version] == future_version

    # AGENTS.md must still be written — the version guard only protects the
    # plugin bundle, not the instruction file.
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))
    assert File.read!(Path.join(tmp_dir, "AGENTS.md")) =~ "ControlKeel"
  end

  test "cursor-native install writes plugin.json when existing version is older", %{
    tmp_dir: tmp_dir
  } do
    plugin_dir = Path.join(tmp_dir, ".cursor-plugin")
    File.mkdir_p!(plugin_dir)

    File.write!(
      Path.join(plugin_dir, "plugin.json"),
      Jason.encode!(%{"name" => "controlkeel", "version" => "0.0.1"}, pretty: true) <> "\n"
    )

    assert {:ok, result} = Skills.install("cursor-native", tmp_dir, scope: "project")

    plugin = Jason.decode!(File.read!(Path.join(plugin_dir, "plugin.json")))
    current = to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")
    assert plugin["version"] == current

    # No version guard should fire when upgrading.
    assert result[:version_guarded] == false
    assert is_nil(result[:recorded_version])
  end

  test "install with write_agents_md: false does not overwrite AGENTS.md", %{tmp_dir: tmp_dir} do
    agents_md = Path.join(tmp_dir, "AGENTS.md")
    File.write!(agents_md, "# sentinel\n")

    assert {:ok, _} =
             Skills.install("cursor-native", tmp_dir, scope: "project", write_agents_md: false)

    assert File.read!(agents_md) == "# sentinel\n"
  end

  test "install with write_agents_md: true (default) updates AGENTS.md", %{tmp_dir: tmp_dir} do
    agents_md = Path.join(tmp_dir, "AGENTS.md")

    assert {:ok, _} = Skills.install("cursor-native", tmp_dir, scope: "project")

    assert File.exists?(agents_md)
    assert File.read!(agents_md) =~ "ControlKeel"
  end

  defp skill_dir_names(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.sort()
  end

  defp prompt_hook_output(hook_path, prompt) do
    input = Jason.encode!(%{"prompt" => prompt})

    {output, 0} =
      System.cmd("sh", ["-c", "printf '%s' \"$PROMPT_INPUT\" | sh \"$HOOK_PATH\""],
        env: [{"PROMPT_INPUT", input}, {"HOOK_PATH", hook_path}],
        stderr_to_stdout: true
      )

    output
  end

  test "every registered export target produces a plan (no host silently dropped)", %{
    tmp_dir: tmp_dir
  } do
    ids = ControlKeel.Skills.SkillTarget.ids()

    failures =
      for id <- ids, reduce: [] do
        acc ->
          dir = Path.join(tmp_dir, "export-#{id}")

          case Skills.export(id, dir, scope: "export") do
            {:ok, plan} ->
              if is_binary(plan.output_dir) and File.dir?(plan.output_dir) do
                acc
              else
                [{id, :no_output_dir} | acc]
              end

            other ->
              [{id, other} | acc]
          end
      end

    assert failures == [],
           "export targets that failed to produce a plan: #{inspect(failures)}"

    # Guards against the decomposition silently dropping a host (handlers were
    # lost-and-restored twice during the exporter/CLI refactors).
    assert length(ids) >= 40
  end

  test "invalid install scopes return an error instead of falling back", %{tmp_dir: tmp_dir} do
    assert {:error, {:unsupported_scope, "cursor-native", "user", ["project", "export"]}} =
             Skills.install("cursor-native", tmp_dir, scope: "user")

    refute File.exists?(Path.join(tmp_dir, ".cursor"))
  end

  test "multica installs concrete native artifacts for project and user scopes", %{
    tmp_dir: tmp_dir
  } do
    project = Path.join(tmp_dir, "project")
    File.mkdir_p!(project)

    assert {:ok, project_install} = Skills.install("multica-native", project, scope: "project")
    assert project_install.destination == Path.join(project, ".multica")
    assert project_install.skills_destination == Path.join(project, ".agents/skills")
    assert File.exists?(Path.join(project, ".multica/controlkeel-mcp.json"))
    assert File.exists?(Path.join(project, ".multica/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(project, ".agents/skills/controlkeel-governance/SKILL.md"))

    assert {:ok, user_install} = Skills.install("multica-native", project, scope: "user")
    assert user_install.destination == Path.join(tmp_dir, ".multica")
    assert user_install.skills_destination == Path.join(tmp_dir, ".agents/skills")
    assert File.exists?(Path.join(tmp_dir, ".multica/controlkeel-mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
  end

  test "antigravity installs its workspace-native bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, install} =
             Skills.install("antigravity-cli-native", tmp_dir, scope: "project")

    assert install.destination == Path.join(tmp_dir, ".agents")
    assert install.plugins_destination == Path.join(tmp_dir, ".agents/plugins/controlkeel")
    assert File.exists?(Path.join(tmp_dir, ".agents/plugins/controlkeel/plugin.json"))
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".agents/hooks.json"))
    assert File.exists?(Path.join(tmp_dir, ".agents/mcp_config.json"))
    assert File.exists?(Path.join(tmp_dir, "GEMINI.md"))
    assert File.exists?(Path.join(tmp_dir, "AGENTS.md"))
  end

  test "runtime targets with project scope return unsupported_install instead of crashing", %{
    tmp_dir: tmp_dir
  } do
    for target <- ~w(open-swe-runtime devin-runtime warp-oz-runtime executor-runtime
                     cloudflare-workers-runtime virtual-bash-runtime multica-cloud-runtime) do
      assert {:error, {:unsupported_install, ^target, "project"}} =
               Skills.install(target, tmp_dir, scope: "project"),
             "expected #{target} to return unsupported_install for project scope"
    end
  end

  test "export-only plugin targets reject project install scope", %{tmp_dir: tmp_dir} do
    for plugin <-
          ~w(claude-plugin augment-plugin openclaw-plugin droid-plugin antigravity-cli-plugin) do
      result = Skills.install(plugin, tmp_dir, scope: "project")

      assert match?({:error, {:unsupported_scope, ^plugin, "project", _}}, result) ||
               match?({:error, {:unsupported_install, ^plugin, "project"}}, result),
             "expected #{plugin} to reject project scope, got: #{inspect(result)}"
    end
  end

  describe "repo_hook_command/1 scope resolution" do
    alias ControlKeel.Skills.Exporter.Shared

    # Regression: claude-code's default attach scope is "user", which installs
    # hook scripts under $HOME/.claude/hooks while the generated settings.json
    # used a project-only "$root/.claude/hooks/..." reference -> every hook
    # exited 127 on a fresh install. The command must resolve from either scope.
    test "resolves a user-scope hook script that lives only under $HOME", %{tmp_dir: tmp_dir} do
      home = Path.join(tmp_dir, "home")
      project = Path.join(tmp_dir, "project")
      File.mkdir_p!(Path.join(home, ".claude/hooks"))
      File.mkdir_p!(project)

      script = Path.join(home, ".claude/hooks/session-start.sh")
      File.write!(script, "#!/usr/bin/env sh\nprintf RAN\n")
      File.chmod!(script, 0o755)

      cmd = Shared.repo_hook_command(".claude/hooks/session-start.sh")

      {out, status} =
        System.cmd("sh", ["-c", cmd], env: [{"HOME", home}, {"CK_PROJECT_ROOT", project}])

      assert status == 0
      assert out == "RAN"
    end

    test "no-ops cleanly (exit 0) when neither scope has the script", %{tmp_dir: tmp_dir} do
      home = Path.join(tmp_dir, "home")
      project = Path.join(tmp_dir, "project")
      File.mkdir_p!(home)
      File.mkdir_p!(project)

      cmd = Shared.repo_hook_command(".claude/hooks/missing.sh")

      {_out, status} =
        System.cmd("sh", ["-c", cmd], env: [{"HOME", home}, {"CK_PROJECT_ROOT", project}])

      assert status == 0
    end
  end
end
