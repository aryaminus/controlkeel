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

  defp do_install(%SkillTarget{id: "cline-native"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export("cline-native", project_root, scope: scope)

    case scope do
      "user" ->
        cline_root = cline_home()
        skill_root = Path.join(cline_root, "skills")
        rules_root = cline_documents_dir("Rules")
        workflows_root = cline_documents_dir("Workflows")
        config_root = Path.join([cline_root, "data", "settings"])

        copy_skills(skills, skill_root)
        File.mkdir_p!(rules_root)
        File.mkdir_p!(workflows_root)
        File.mkdir_p!(config_root)

        File.cp!(
          Path.join(plan.output_dir, ".clinerules/controlkeel.md"),
          Path.join(rules_root, "controlkeel.md")
        )

        File.cp!(
          Path.join(plan.output_dir, ".clinerules/workflows/controlkeel-review.md"),
          Path.join(workflows_root, "controlkeel-review.md")
        )

        merge_json_file!(
          Path.join(plan.output_dir, ".cline/data/settings/cline_mcp_settings.json"),
          Path.join(config_root, "cline_mcp_settings.json")
        )

        {:ok,
         %{
           target: "cline-native",
           scope: scope,
           destination: skill_root,
           agent_destination: config_root,
           rules_destination: rules_root,
           workflows_destination: workflows_root
         }}

      "project" ->
        skill_root = Path.join(project_root, ".cline/skills")
        rules_root = Path.join(project_root, ".clinerules")

        copy_skills(skills, skill_root)
        copy_tree_contents(Path.join(plan.output_dir, ".clinerules"), rules_root)
        File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))

        {:ok,
         %{
           target: "cline-native",
           scope: scope,
           destination: skill_root,
           rules_destination: rules_root
         }}
    end
  end

  defp do_install(%SkillTarget{id: "roo-native"}, "project", project_root, skills, _opts) do
    {:ok, plan} = Exporter.export("roo-native", project_root, scope: "project")

    skill_root = Path.join(project_root, ".roo/skills")
    roo_root = Path.join(project_root, ".roo")

    copy_skills(skills, skill_root)
    copy_tree_contents(Path.join(plan.output_dir, ".roo"), roo_root)
    File.cp!(Path.join(plan.output_dir, ".roomodes"), Path.join(project_root, ".roomodes"))
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))

    {:ok,
     %{
       target: "roo-native",
       scope: "project",
       destination: skill_root,
       rules_destination: Path.join(roo_root, "rules"),
       commands_destination: Path.join(roo_root, "commands"),
       guidance_destination: Path.join(roo_root, "guidance")
     }}
  end

  defp do_install(%SkillTarget{id: "goose-native"}, "project", project_root, _skills, _opts) do
    {:ok, plan} = Exporter.export("goose-native", project_root, scope: "project")

    workflow_root = Path.join(project_root, "goose/workflow_recipes")
    File.mkdir_p!(workflow_root)
    copy_tree_contents(Path.join(plan.output_dir, "goose"), Path.join(project_root, "goose"))
    File.cp!(Path.join(plan.output_dir, ".goosehints"), Path.join(project_root, ".goosehints"))
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))

    {:ok,
     %{
       target: "goose-native",
       scope: "project",
       destination: Path.join(project_root, ".goosehints"),
       workflows_destination: workflow_root,
       agent_destination: Path.join(project_root, "goose")
     }}
  end

  defp do_install(%SkillTarget{id: "hermes-native"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    base =
      if(scope == "user",
        do: Path.join(user_home(), ".hermes"),
        else: Path.join(project_root, ".hermes")
      )

    skill_root = Path.join(base, "skills")

    copy_skills(skills, skill_root)

    {:ok, plan} = Exporter.export("hermes-native", project_root, scope: scope)
    copy_tree_contents(Path.join(plan.output_dir, ".hermes"), base)

    if scope == "project" do
      File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))
    end

    {:ok,
     %{target: "hermes-native", scope: scope, destination: skill_root, agent_destination: base}}
  end

  defp do_install(%SkillTarget{id: "openclaw-native"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    {skill_root, config_root} =
      if scope == "user" do
        {Path.join(user_home(), ".openclaw/skills"), Path.join(user_home(), ".openclaw")}
      else
        {Path.join(project_root, "skills"), Path.join(project_root, ".openclaw")}
      end

    copy_skills(skills, skill_root)

    {:ok, plan} = Exporter.export("openclaw-native", project_root, scope: scope)
    File.mkdir_p!(config_root)

    File.cp!(
      Path.join(plan.output_dir, ".openclaw/openclaw.json"),
      Path.join(config_root, "openclaw.json")
    )

    if scope == "project" do
      File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))
    end

    {:ok,
     %{
       target: "openclaw-native",
       scope: scope,
       destination: skill_root,
       agent_destination: config_root
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

  defp do_install(%SkillTarget{id: "droid-bundle"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    base =
      if(scope == "user",
        do: Path.join(user_home(), ".factory"),
        else: Path.join(project_root, ".factory")
      )

    skill_root = Path.join(base, "skills")

    copy_skills(skills, skill_root)

    {:ok, plan} = Exporter.export("droid-bundle", project_root, scope: scope)
    copy_tree_contents(Path.join(plan.output_dir, ".factory"), base)

    if scope == "project" do
      File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))
    end

    {:ok,
     %{target: "droid-bundle", scope: scope, destination: skill_root, agent_destination: base}}
  end

  defp do_install(%SkillTarget{id: "forge-acp"}, scope, project_root, skills, _opts)
       when scope in ["user", "project"] do
    skill_root =
      if scope == "user",
        do: Path.join(user_home(), ".agents/skills"),
        else: Path.join(project_root, ".agents/skills")

    forge_root =
      if(scope == "user",
        do: Path.join(user_home(), ".forge"),
        else: Path.join(project_root, ".forge")
      )

    copy_skills(skills, skill_root)

    {:ok, plan} = Exporter.export("forge-acp", project_root, scope: scope)
    File.mkdir_p!(forge_root)

    File.cp!(
      Path.join(plan.output_dir, ".forge/controlkeel.acp.json"),
      Path.join(forge_root, "controlkeel.acp.json")
    )

    if scope == "project" do
      File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
      File.cp!(Path.join(plan.output_dir, "AGENTS.md"), Path.join(project_root, "AGENTS.md"))
    end

    {:ok,
     %{target: "forge-acp", scope: scope, destination: skill_root, agent_destination: forge_root}}
  end

  defp do_install(%SkillTarget{id: target}, "export", project_root, _skills, _opts)
       when is_binary(target) do
    Exporter.export(target, project_root, scope: "export")
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

  defp merge_json_file!(source_path, destination_path) do
    source =
      source_path
      |> File.read!()
      |> Jason.decode!()

    existing =
      case File.read(destination_path) do
        {:ok, contents} -> Jason.decode!(contents)
        _ -> %{}
      end

    updated =
      Map.merge(existing, source, fn _key, left, right ->
        if is_map(left) and is_map(right) do
          Map.merge(left, right)
        else
          right
        end
      end)

    File.write!(destination_path, Jason.encode!(updated, pretty: true) <> "\n")
  end

  defp same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  defp cline_home do
    System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
  end

  defp cline_documents_dir(name) do
    Path.join([user_home(), "Documents", "Cline", name])
  end
end
