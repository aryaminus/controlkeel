defmodule ControlKeel.Skills.Installer do
  @moduledoc false

  alias ControlKeel.Skills.Exporter
  alias ControlKeel.Skills.Registry
  alias ControlKeel.Skills.SkillTarget

  def install(target_id, project_root, opts \\ []) do
    with %SkillTarget{} = target <- SkillTarget.get(target_id),
         scope <- normalize_scope(target, Keyword.get(opts, :scope, target.default_scope)),
         analysis <- Registry.analyze(project_root, trust_project_skills: true),
         {:ok, result} <- do_install(target, scope, project_root, analysis.skills, opts) do
      :telemetry.execute(
        [:controlkeel, :skills, :installed],
        %{count: 1},
        %{
          target: target.id,
          scope: scope,
          project_root: Path.expand(project_root),
          skill_count: length(analysis.skills)
        }
      )

      {:ok, result}
    else
      nil -> {:error, :unknown_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_install(%SkillTarget{id: "open-standard"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    root =
      if scope == "user",
        do: Path.join(user_home(), ".agents/skills"),
        else: Path.join(project_root, ".agents/skills")

    copy_skills(skills, root)

    {:ok,
     %{
       target: "open-standard",
       scope: scope,
       destination: root,
       installed: Enum.map(skills, & &1.name)
     }}
  end

  defp do_install(%SkillTarget{id: "codex"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    skill_root =
      if scope == "user",
        do: Path.join(user_home(), ".agents/skills"),
        else: Path.join(project_root, ".agents/skills")

    agent_root =
      if scope == "user",
        do: Path.join(user_home(), ".codex/agents"),
        else: Path.join(project_root, ".codex/agents")

    copy_skills(skills, skill_root)
    File.mkdir_p!(agent_root)

    {:ok, plan} = Exporter.export("codex", project_root, scope: scope)
    copy_tree_contents(Path.join(plan.output_dir, ".codex/agents"), agent_root)

    {:ok,
     %{target: "codex", scope: scope, destination: skill_root, agent_destination: agent_root}}
  end

  defp do_install(%SkillTarget{id: "claude-standalone"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    base =
      if scope == "user",
        do: Path.join(user_home(), ".claude"),
        else: Path.join(project_root, ".claude")

    skill_root = Path.join(base, "skills")
    agent_root = Path.join(base, "agents")

    copy_skills(skills, skill_root)
    File.mkdir_p!(agent_root)

    {:ok, plan} = Exporter.export("claude-standalone", project_root, scope: scope)
    copy_tree_contents(Path.join(plan.output_dir, ".claude/agents"), agent_root)

    {:ok,
     %{
       target: "claude-standalone",
       scope: scope,
       destination: skill_root,
       agent_destination: agent_root
     }}
  end

  defp do_install(%SkillTarget{id: "github-repo"}, scope, project_root, skills, _opts)
       when scope in ["project", "export"] do
    if scope == "project" do
      skill_root = Path.join(project_root, ".github/skills")
      copy_skills(skills, skill_root)

      {:ok, plan} = Exporter.export("github-repo", project_root, scope: scope)

      copy_tree_contents(
        Path.join(plan.output_dir, ".github"),
        Path.join(project_root, ".github")
      )

      copy_tree_contents(
        Path.join(plan.output_dir, ".vscode"),
        Path.join(project_root, ".vscode")
      )

      {:ok, %{target: "github-repo", scope: scope, destination: skill_root}}
    else
      Exporter.export("github-repo", project_root, scope: scope)
    end
  end

  defp do_install(%SkillTarget{id: "claude-plugin"}, _scope, project_root, _skills, _opts) do
    Exporter.export("claude-plugin", project_root, scope: "export")
  end

  defp do_install(%SkillTarget{id: "copilot-plugin"}, _scope, project_root, _skills, _opts) do
    Exporter.export("copilot-plugin", project_root, scope: "export")
  end

  defp do_install(%SkillTarget{id: "instructions-only"}, _scope, project_root, _skills, _opts) do
    Exporter.export("instructions-only", project_root, scope: "export")
  end

  defp normalize_scope(target, scope) do
    scope = to_string(scope || target.default_scope)
    if scope in target.supported_scopes, do: scope, else: target.default_scope
  end

  defp copy_skills(skills, destination_root) do
    File.mkdir_p!(destination_root)

    Enum.each(skills, fn skill ->
      destination = Path.join(destination_root, skill.name)

      unless same_path?(skill.skill_dir, destination) do
        File.rm_rf!(destination)
        File.cp_r!(skill.skill_dir, destination)
      end
    end)
  end

  defp copy_tree_contents(source_root, destination_root) do
    File.mkdir_p!(destination_root)

    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      source = Path.join(source_root, entry)
      destination = Path.join(destination_root, entry)
      File.rm_rf!(destination)
      File.cp_r!(source, destination)
    end)
  end

  defp same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end
end
