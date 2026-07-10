defmodule ControlKeel.Skills.Installer do
  @moduledoc false

  alias ControlKeel.Project.Binding
  alias ControlKeel.Skills.Exporter
  alias ControlKeel.Skills.Registry
  alias ControlKeel.Skills.SkillTarget

  @managed_agents_start "<!-- controlkeel:start -->"
  @managed_agents_end "<!-- controlkeel:end -->"

  # Per-destination record of the skill names CK last installed there, so a
  # later install can prune only CK's own orphans without touching user skills.
  @skills_manifest_file ".controlkeel-skills.json"

  def install(target_id, project_root, opts \\ []) do
    with %SkillTarget{} = target <- SkillTarget.get(target_id),
         {:ok, scope} <- normalize_scope(target, Keyword.get(opts, :scope, target.default_scope)),
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

      maybe_ignore_project_artifacts(scope, project_root, result)

      {:ok, result}
    else
      nil -> {:error, :unknown_target}
      {:error, reason} -> {:error, reason}
    end
  end

  # After a project-scoped install, add the exact repo-relative paths CK wrote
  # to the managed .gitignore block. Specific subpaths (not parent dirs) are
  # used so shared dirs like .github/.vscode are never wholesale-ignored.
  # Best-effort: a gitignore failure must never fail the install itself.
  defp maybe_ignore_project_artifacts("project", project_root, result) do
    root = Path.expand(project_root)

    entries =
      result
      |> collect_destination_paths()
      |> Enum.map(&Path.expand(&1, root))
      |> Enum.filter(&path_within?(root, &1))
      |> Enum.map(&gitignore_entry_for(root, &1))
      |> Enum.uniq()

    if entries != [], do: Binding.ensure_gitignore(root, entries)
    :ok
  rescue
    _ -> :ok
  end

  defp maybe_ignore_project_artifacts(_scope, _project_root, _result), do: :ok

  @doc """
  Remove CK-installed skill directories that are no longer in the current skill set.

  Uses the per-destination manifest (`.controlkeel-skills.json`) to identify
  CK-owned skills, then removes any that are not in the current canonical set.
  User-authored skills are never touched.
  """
  def cleanup_stale_skills(project_root, attached_agents) when is_map(attached_agents) do
    analysis = Registry.analyze(project_root, trust_project_skills: true)
    current_names = Enum.map(analysis.skills, & &1.name)

    skill_dirs =
      attached_agents
      |> Enum.flat_map(fn {_key, attrs} ->
        [
          Map.get(attrs, "skills_destination"),
          Map.get(attrs, "compat_skills_destination"),
          Map.get(attrs, "compat_destination")
        ]
        |> Enum.filter(&is_binary/1)
      end)
      |> Enum.filter(fn dir ->
        is_binary(dir) and File.dir?(dir)
      end)
      |> Enum.uniq()

    Enum.each(skill_dirs, fn dir ->
      prune_orphaned_skills(dir, current_names)
    end)

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Re-sync all attached targets' skill directories from the canonical skill source.

  Called after any target sync to ensure all skill copies stay identical.
  Safe to call multiple times — idempotent via manifest-based pruning.
  """
  def sync_all_skill_dirs(project_root, attached_agents) when is_map(attached_agents) do
    analysis = Registry.analyze(project_root, trust_project_skills: true)
    skills = analysis.skills

    root = Path.expand(project_root)

    # Collect all unique skill destination paths across all attached agents
    skill_dirs =
      attached_agents
      |> Enum.flat_map(fn {_key, attrs} ->
        [
          Map.get(attrs, "skills_destination"),
          Map.get(attrs, "compat_skills_destination"),
          Map.get(attrs, "compat_destination")
        ]
        |> Enum.filter(&is_binary/1)
      end)
      |> Enum.filter(fn dir ->
        # Only sync dirs that exist and are within the project root
        is_binary(dir) and File.dir?(dir) and path_within?(root, dir)
      end)
      |> Enum.uniq()

    Enum.each(skill_dirs, fn dir ->
      copy_skills(skills, dir)
    end)

    :ok
  rescue
    _ -> :ok
  end

  @gitignore_destination_keys ~w(
    skills_destination compat_skills_destination compat_destination skill_destination
    agent_destination agents_destination commands_destination plugins_destination
    rules_destination guidance_destination workflows_destination hooks_destination
    config_destination settings_destination instructions_destination marketplace_destination
    mcp_destination
  )

  defp collect_destination_paths(result) when is_map(result) do
    result
    |> Enum.filter(fn {key, _value} -> to_string(key) in @gitignore_destination_keys end)
    |> Enum.map(fn {_key, value} -> value end)
    |> Enum.filter(&is_binary/1)
  end

  defp collect_destination_paths(_), do: []

  defp path_within?(root, candidate), do: String.starts_with?(candidate, root <> "/")

  defp gitignore_entry_for(root, path) do
    rel = Path.relative_to(path, root)
    if File.dir?(path), do: "/" <> rel <> "/", else: "/" <> rel
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

  defp do_install(%SkillTarget{id: "codex"}, scope, project_root, skills, opts)
       when scope in ["user", "project"] do
    compat_skill_root =
      if scope == "user",
        do: Path.join(user_home(), ".agents/skills"),
        else: Path.join(project_root, ".agents/skills")

    native_skill_root =
      if scope == "user",
        do: Path.join(user_home(), ".codex/skills"),
        else: Path.join(project_root, ".codex/skills")

    agent_root =
      if scope == "user",
        do: Path.join(user_home(), ".codex/agents"),
        else: Path.join(project_root, ".codex/agents")

    unless compat_skills_already_populated?(compat_skill_root, skills) do
      copy_skills(skills, compat_skill_root)
    end

    copy_skills(skills, native_skill_root)
    File.mkdir_p!(agent_root)

    {:ok, plan} = Exporter.export("codex", project_root, scope: scope)
    copy_tree_contents(Path.join(plan.output_dir, ".codex/agents"), agent_root)

    commands_root =
      if scope == "user",
        do: Path.join(user_home(), ".codex/commands"),
        else: Path.join(project_root, ".codex/commands")

    File.mkdir_p!(commands_root)
    copy_tree_contents(Path.join(plan.output_dir, ".codex/commands"), commands_root)

    config_root =
      if scope == "user",
        do: Path.join(user_home(), ".codex"),
        else: Path.join(project_root, ".codex")

    File.mkdir_p!(config_root)

    hooks_root = Path.join(config_root, "hooks")
    File.mkdir_p!(hooks_root)
    copy_tree_contents(Path.join(plan.output_dir, ".codex/hooks"), hooks_root)

    File.cp!(
      Path.join(plan.output_dir, ".codex/config.toml"),
      Path.join(config_root, "config.toml")
    )

    File.cp!(
      Path.join(plan.output_dir, ".codex/hooks.json"),
      Path.join(config_root, "hooks.json")
    )

    if scope == "project" do
      File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{
       target: "codex",
       scope: scope,
       destination: native_skill_root,
       compat_destination: compat_skill_root,
       agent_destination: agent_root,
       commands_destination: commands_root,
       config_destination: Path.join(config_root, "config.toml"),
       hooks_destination: hooks_root
     }}
  end

  defp do_install(%SkillTarget{id: "codex-plugin"}, scope, project_root, _skills, _opts)
       when scope in ["user", "project", "export"] do
    if scope == "export" do
      Exporter.export("codex-plugin", project_root, scope: scope)
    else
      {:ok, plan} = Exporter.export("codex-plugin", project_root, scope: scope)
      plugin_root = plugin_install_root("codex", scope, project_root)

      File.rm_rf!(plugin_root)
      File.mkdir_p!(Path.dirname(plugin_root))
      File.cp_r!(plan.output_dir, plugin_root)

      marketplace_destination = codex_marketplace_destination(scope, project_root)
      File.mkdir_p!(Path.dirname(marketplace_destination))

      File.cp!(
        Path.join(plugin_root, ".agents/plugins/marketplace.json"),
        marketplace_destination
      )

      {:ok,
       %{
         target: "codex-plugin",
         scope: scope,
         destination: plugin_root,
         marketplace_destination: marketplace_destination
       }}
    end
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

    hooks_src = Path.join(plan.output_dir, ".claude/hooks")
    hooks_dst = Path.join(base, "hooks")

    if File.dir?(hooks_src) do
      copy_tree_contents(hooks_src, hooks_dst)
    end

    settings_path = Path.join(base, "settings.json")
    merge_claude_settings(settings_path, Exporter.claude_manual_settings())

    claude_md_dst = Path.join(project_root, "CLAUDE.md")

    claude_md_written =
      unless File.exists?(claude_md_dst) do
        claude_md_src = Path.join(plan.output_dir, "CLAUDE.md")

        if File.exists?(claude_md_src) do
          File.copy!(claude_md_src, claude_md_dst)
          claude_md_dst
        end
      end

    {:ok,
     %{
       target: "claude-standalone",
       scope: scope,
       destination: skill_root,
       agent_destination: agent_root,
       settings_destination: settings_path,
       instructions_destination: claude_md_written
     }}
  end

  defp do_install(%SkillTarget{id: "claude-plugin"}, scope, project_root, _skills, _opts)
       when scope in ["user", "project", "export"] do
    install_plugin_bundle("claude-plugin", "claude", scope, project_root)
  end

  defp do_install(%SkillTarget{id: "devin-terminal-native"}, scope, project_root, _skills, opts)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export("devin-terminal-native", project_root, scope: scope)

    {devin_root, compat_root} =
      if scope == "user" do
        {Path.join(user_home(), ".config/devin"), Path.join(user_home(), ".agents/skills")}
      else
        {Path.join(project_root, ".devin"), Path.join(project_root, ".agents/skills")}
      end

    native_skill_root = Path.join(devin_root, "skills")
    agent_root = Path.join(devin_root, "agents")
    hooks_root = Path.join(devin_root, "hooks")

    File.mkdir_p!(devin_root)
    File.mkdir_p!(native_skill_root)
    File.mkdir_p!(agent_root)
    File.mkdir_p!(hooks_root)
    File.mkdir_p!(compat_root)

    copy_tree_contents(Path.join(plan.output_dir, ".devin/skills"), native_skill_root)
    copy_tree_contents(Path.join(plan.output_dir, ".devin/agents"), agent_root)
    copy_tree_contents(Path.join(plan.output_dir, ".devin/hooks"), hooks_root)

    unless compat_dir_populated?(compat_root) do
      copy_tree_contents(Path.join(plan.output_dir, ".agents/skills"), compat_root)
    end

    merge_json_file!(
      Path.join(plan.output_dir, ".devin/config.json"),
      Path.join(devin_root, "config.json")
    )

    merge_json_file!(
      Path.join(plan.output_dir, ".devin/hooks.v1.json"),
      Path.join(devin_root, "hooks.v1.json")
    )

    File.cp!(Path.join(plan.output_dir, ".devin/README.md"), Path.join(devin_root, "README.md"))

    if scope == "project" do
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{
       target: "devin-terminal-native",
       scope: scope,
       destination: devin_root,
       skills_destination: native_skill_root,
       compat_skills_destination: compat_root,
       agents_destination: agent_root,
       hooks_destination: hooks_root,
       config_destination: Path.join(devin_root, "config.json")
     }}
  end

  defp do_install(%SkillTarget{id: "cline-native"}, scope, project_root, skills, opts)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export("cline-native", project_root, scope: scope)

    case scope do
      "user" ->
        cline_root = cline_home()
        skill_root = Path.join(cline_root, "skills")
        rules_root = cline_documents_dir("Rules")
        workflows_root = cline_documents_dir("Workflows")
        config_root = Path.join([cline_root, "data", "settings"])
        commands_root = Path.join(cline_root, "commands")
        hooks_root = Path.join(cline_root, "hooks")

        copy_skills(skills, skill_root)
        File.mkdir_p!(rules_root)
        File.mkdir_p!(workflows_root)
        File.mkdir_p!(config_root)
        File.mkdir_p!(commands_root)
        File.mkdir_p!(hooks_root)

        File.cp!(
          Path.join(plan.output_dir, ".clinerules/controlkeel.md"),
          Path.join(rules_root, "controlkeel.md")
        )

        File.cp!(
          Path.join(plan.output_dir, ".clinerules/workflows/controlkeel-review.md"),
          Path.join(workflows_root, "controlkeel-review.md")
        )

        copy_tree_contents(Path.join(plan.output_dir, ".cline/commands"), commands_root)
        copy_tree_contents(Path.join(plan.output_dir, ".cline/hooks"), hooks_root)

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
           workflows_destination: workflows_root,
           commands_destination: commands_root,
           hooks_destination: hooks_root
         }}

      "project" ->
        skill_root = Path.join(project_root, ".cline/skills")
        rules_root = Path.join(project_root, ".clinerules")

        copy_skills(skills, skill_root)
        copy_tree_contents(Path.join(plan.output_dir, ".clinerules"), rules_root)

        copy_tree_contents(
          Path.join(plan.output_dir, ".cline/commands"),
          Path.join(project_root, ".cline/commands")
        )

        copy_tree_contents(
          Path.join(plan.output_dir, ".cline/hooks"),
          Path.join(project_root, ".cline/hooks")
        )

        maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

        {:ok,
         %{
           target: "cline-native",
           scope: scope,
           destination: skill_root,
           rules_destination: rules_root,
           commands_destination: Path.join(project_root, ".cline/commands"),
           hooks_destination: Path.join(project_root, ".cline/hooks")
         }}
    end
  end

  defp do_install(%SkillTarget{id: "cursor-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("cursor-native", project_root, scope: "project")

    copy_skills(skills, Path.join(project_root, ".agents/skills"))
    copy_tree_contents(Path.join(plan.output_dir, ".cursor"), Path.join(project_root, ".cursor"))

    # Guard: do not overwrite an existing plugin.json if the exported version is
    # older than what is already on disk. This prevents the installed binary
    # (which runs Stop hooks) from downgrading a source-synced plugin bundle.
    dest_plugin_json = Path.join(project_root, ".cursor-plugin/plugin.json")
    src_plugin_json = Path.join(plan.output_dir, ".cursor-plugin/plugin.json")

    guarded? = plugin_version_downgrade?(src_plugin_json, dest_plugin_json)

    unless guarded? do
      copy_tree_contents(
        Path.join(plan.output_dir, ".cursor-plugin"),
        Path.join(project_root, ".cursor-plugin")
      )
    end

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    # When the version guard blocked the plugin copy, report the on-disk
    # plugin version so the sync layer records the correct (newer) version
    # in the binding instead of the running binary's older version.
    recorded_version =
      if guarded? do
        read_plugin_version(dest_plugin_json)
      end

    {:ok,
     %{
       target: "cursor-native",
       scope: "project",
       destination: Path.join(project_root, ".cursor"),
       plugin_destination: Path.join(project_root, ".cursor-plugin"),
       skill_destination: Path.join(project_root, ".agents/skills"),
       version_guarded: guarded?,
       recorded_version: recorded_version
     }}
  end

  defp do_install(%SkillTarget{id: "windsurf-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("windsurf-native", project_root, scope: "project")

    copy_skills(skills, Path.join(project_root, ".agents/skills"))

    copy_tree_contents(
      Path.join(plan.output_dir, ".windsurf"),
      Path.join(project_root, ".windsurf")
    )

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "windsurf-native",
       scope: "project",
       destination: Path.join(project_root, ".windsurf"),
       skill_destination: Path.join(project_root, ".agents/skills")
     }}
  end

  defp do_install(%SkillTarget{id: "continue-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("continue-native", project_root, scope: "project")

    copy_skills(skills, Path.join(project_root, ".continue/skills"))

    copy_tree_contents(
      Path.join(plan.output_dir, ".continue"),
      Path.join(project_root, ".continue")
    )

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "continue-native",
       scope: "project",
       destination: Path.join(project_root, ".continue")
     }}
  end

  defp do_install(%SkillTarget{id: "letta-code-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("letta-code-native", project_root, scope: "project")

    skill_root = Path.join(project_root, ".agents/skills")
    letta_root = Path.join(project_root, ".letta")

    copy_skills(skills, skill_root)
    copy_tree_contents(Path.join(plan.output_dir, ".letta"), letta_root)
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "letta-code-native",
       scope: "project",
       destination: letta_root,
       skill_destination: skill_root
     }}
  end

  defp do_install(%SkillTarget{id: "pi-native"}, "project", project_root, skills, _opts) do
    {:ok, plan} = Exporter.export("pi-native", project_root, scope: "project")

    copy_skills(skills, Path.join(project_root, ".agents/skills"))
    copy_tree_contents(Path.join(plan.output_dir, ".pi"), Path.join(project_root, ".pi"))

    File.cp!(
      Path.join(plan.output_dir, "pi-extension.json"),
      Path.join(project_root, "pi-extension.json")
    )

    File.cp!(Path.join(plan.output_dir, "PI.md"), Path.join(project_root, "PI.md"))

    {:ok,
     %{
       target: "pi-native",
       scope: "project",
       destination: Path.join(project_root, ".pi"),
       skill_destination: Path.join(project_root, ".agents/skills")
     }}
  end

  defp do_install(%SkillTarget{id: "roo-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("roo-native", project_root, scope: "project")

    skill_root = Path.join(project_root, ".roo/skills")
    roo_root = Path.join(project_root, ".roo")

    copy_skills(skills, skill_root)
    copy_tree_contents(Path.join(plan.output_dir, ".roo"), roo_root)
    File.cp!(Path.join(plan.output_dir, ".roomodes"), Path.join(project_root, ".roomodes"))
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

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

  defp do_install(%SkillTarget{id: "warp-native"}, scope, project_root, _skills, opts)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export("warp-native", project_root, scope: scope)

    {warp_root, compat_root} =
      if scope == "user" do
        {Path.join(user_home(), ".warp"), Path.join(user_home(), ".agents/skills")}
      else
        {Path.join(project_root, ".warp"), Path.join(project_root, ".agents/skills")}
      end

    native_skill_root = Path.join(warp_root, "skills")

    File.mkdir_p!(warp_root)
    File.mkdir_p!(native_skill_root)
    File.mkdir_p!(compat_root)

    copy_tree_contents(Path.join(plan.output_dir, ".warp/skills"), native_skill_root)

    unless compat_dir_populated?(compat_root) do
      copy_tree_contents(Path.join(plan.output_dir, ".agents/skills"), compat_root)
    end

    File.cp!(
      Path.join(plan.output_dir, ".warp/controlkeel-mcp.json"),
      Path.join(warp_root, "controlkeel-mcp.json")
    )

    File.cp!(Path.join(plan.output_dir, ".warp/README.md"), Path.join(warp_root, "README.md"))

    if scope == "project" do
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{
       target: "warp-native",
       scope: scope,
       destination: warp_root,
       skills_destination: native_skill_root,
       compat_skills_destination: compat_root,
       config_destination: Path.join(warp_root, "controlkeel-mcp.json")
     }}
  end

  defp do_install(%SkillTarget{id: "goose-native"}, "project", project_root, _skills, opts) do
    {:ok, plan} = Exporter.export("goose-native", project_root, scope: "project")

    workflow_root = Path.join(project_root, "goose/workflow_recipes")
    File.mkdir_p!(workflow_root)
    copy_tree_contents(Path.join(plan.output_dir, "goose"), Path.join(project_root, "goose"))
    File.cp!(Path.join(plan.output_dir, ".goosehints"), Path.join(project_root, ".goosehints"))
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "goose-native",
       scope: "project",
       destination: Path.join(project_root, ".goosehints"),
       workflows_destination: workflow_root,
       agent_destination: Path.join(project_root, "goose")
     }}
  end

  defp do_install(%SkillTarget{id: "opencode-native"}, "project", project_root, skills, opts) do
    {:ok, plan} = Exporter.export("opencode-native", project_root, scope: "project")

    opencode_root = Path.join(project_root, ".opencode")
    native_skills_root = Path.join(opencode_root, "skills")
    compat_skills_root = Path.join(project_root, ".agents/skills")
    plugins_root = Path.join(opencode_root, "plugins")
    agents_root = Path.join(opencode_root, "agents")
    commands_root = Path.join(opencode_root, "commands")

    copy_skills(skills, native_skills_root)
    # Only write compat .agents/skills/ if not already populated by another
    # agent with native skill support — avoids redundant copies wasting tokens.
    unless compat_skills_already_populated?(compat_skills_root, skills) do
      copy_skills(skills, compat_skills_root)
    end

    File.mkdir_p!(plugins_root)
    File.mkdir_p!(agents_root)
    File.mkdir_p!(commands_root)

    copy_tree_contents(Path.join(plan.output_dir, ".opencode/plugins"), plugins_root)
    copy_tree_contents(Path.join(plan.output_dir, ".opencode/agents"), agents_root)
    copy_tree_contents(Path.join(plan.output_dir, ".opencode/commands"), commands_root)

    mcp_path = Path.join(opencode_root, "mcp.json")

    File.cp!(
      Path.join(plan.output_dir, ".opencode/mcp.json"),
      mcp_path
    )

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "opencode-native",
       scope: "project",
       destination: Path.join(project_root, ".opencode"),
       skills_destination: native_skills_root,
       compat_skills_destination: compat_skills_root,
       plugins_destination: plugins_root,
       agents_destination: agents_root,
       commands_destination: commands_root
     }}
  end

  defp do_install(%SkillTarget{id: "gemini-cli-native"}, "project", project_root, _skills, _opts) do
    {:ok, plan} = Exporter.export("gemini-cli-native", project_root, scope: "project")

    gemini_root = Path.join(project_root, ".gemini")
    commands_root = Path.join(gemini_root, "commands")

    File.mkdir_p!(commands_root)

    copy_tree_contents(
      Path.join(plan.output_dir, ".gemini/commands"),
      commands_root
    )

    File.cp!(
      Path.join(plan.output_dir, "gemini-extension.json"),
      Path.join(project_root, "gemini-extension.json")
    )

    skills_root = Path.join(project_root, "skills")
    File.mkdir_p!(skills_root)
    copy_tree_contents(Path.join(plan.output_dir, "skills"), skills_root)

    File.cp!(Path.join(plan.output_dir, "GEMINI.md"), Path.join(project_root, "GEMINI.md"))

    File.cp!(
      Path.join(plan.output_dir, "README.md"),
      Path.join(project_root, "README.gemini-controlkeel.md")
    )

    {:ok,
     %{
       target: "gemini-cli-native",
       scope: "project",
       destination: gemini_root,
       commands_destination: commands_root,
       skills_destination: skills_root
     }}
  end

  defp do_install(%SkillTarget{id: "kiro-native"}, "project", project_root, _skills, opts) do
    {:ok, plan} = Exporter.export("kiro-native", project_root, scope: "project")

    kiro_root = Path.join(project_root, ".kiro")
    hooks_root = Path.join(kiro_root, "hooks")
    steering_root = Path.join(kiro_root, "steering")
    settings_root = Path.join(kiro_root, "settings")
    commands_root = Path.join(kiro_root, "commands")

    File.mkdir_p!(hooks_root)
    File.mkdir_p!(steering_root)
    File.mkdir_p!(settings_root)
    File.mkdir_p!(commands_root)

    copy_tree_contents(Path.join(plan.output_dir, ".kiro/hooks"), hooks_root)
    copy_tree_contents(Path.join(plan.output_dir, ".kiro/steering"), steering_root)
    copy_tree_contents(Path.join(plan.output_dir, ".kiro/settings"), settings_root)
    copy_tree_contents(Path.join(plan.output_dir, ".kiro/commands"), commands_root)

    File.cp!(
      Path.join(plan.output_dir, ".kiro/mcp.json"),
      Path.join(kiro_root, "mcp.json")
    )

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "kiro-native",
       scope: "project",
       destination: kiro_root,
       hooks_destination: hooks_root,
       steering_destination: steering_root,
       settings_destination: settings_root,
       commands_destination: commands_root
     }}
  end

  defp do_install(%SkillTarget{id: "kilo-native"}, "project", project_root, skills, opts) do
    kilo_root = Path.join(project_root, ".kilo")
    skills_root = Path.join(kilo_root, "skills")

    copy_skills(skills, skills_root)

    {:ok, plan} = Exporter.export("kilo-native", project_root, scope: "project")

    commands_root = Path.join(kilo_root, "commands")
    File.mkdir_p!(commands_root)

    copy_tree_contents(Path.join(plan.output_dir, ".kilo/commands"), commands_root)

    File.cp!(
      Path.join(plan.output_dir, ".kilo/kilo.json"),
      Path.join(kilo_root, "kilo.json")
    )

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "kilo-native",
       scope: "project",
       destination: kilo_root,
       skills_destination: skills_root,
       commands_destination: commands_root
     }}
  end

  defp do_install(%SkillTarget{id: "amp-native"}, "project", project_root, _skills, opts) do
    {:ok, plan} = Exporter.export("amp-native", project_root, scope: "project")

    amp_root = Path.join(project_root, ".amp")
    skill_root = Path.join(project_root, ".agents/skills")
    File.mkdir_p!(amp_root)
    File.mkdir_p!(skill_root)

    copy_tree_contents(Path.join(plan.output_dir, ".amp"), amp_root)
    copy_tree_contents(Path.join(plan.output_dir, ".agents/skills"), skill_root)
    File.cp!(Path.join(plan.output_dir, ".mcp.json"), Path.join(project_root, ".mcp.json"))
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "amp-native",
       scope: "project",
       destination: amp_root,
       skill_destination: skill_root,
       plugins_destination: Path.join(amp_root, "plugins"),
       commands_destination: Path.join(amp_root, "commands")
     }}
  end

  defp do_install(%SkillTarget{id: "augment-native"}, "project", project_root, _skills, opts) do
    {:ok, plan} = Exporter.export("augment-native", project_root, scope: "project")

    augment_root = Path.join(project_root, ".augment")
    File.mkdir_p!(augment_root)

    copy_tree_contents(Path.join(plan.output_dir, ".augment"), augment_root)
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    File.cp!(Path.join(plan.output_dir, "AUGMENT.md"), Path.join(project_root, "AUGMENT.md"))

    {:ok,
     %{
       target: "augment-native",
       scope: "project",
       destination: augment_root,
       skills_destination: Path.join(augment_root, "skills"),
       agents_destination: Path.join(augment_root, "agents"),
       commands_destination: Path.join(augment_root, "commands"),
       rules_destination: Path.join(augment_root, "rules")
     }}
  end

  defp do_install(%SkillTarget{id: "instructions-only"}, "project", project_root, _skills, opts) do
    {:ok, plan} = Exporter.export("instructions-only", project_root, scope: "project")

    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    File.cp!(Path.join(plan.output_dir, "CLAUDE.md"), Path.join(project_root, "CLAUDE.md"))

    File.cp!(
      Path.join(plan.output_dir, "copilot-instructions.md"),
      Path.join(project_root, "copilot-instructions.md")
    )

    File.cp!(Path.join(plan.output_dir, "AIDER.md"), Path.join(project_root, "AIDER.md"))

    File.cp!(
      Path.join(plan.output_dir, ".aider.conf.yml"),
      Path.join(project_root, ".aider.conf.yml")
    )

    copy_tree_contents(Path.join(plan.output_dir, ".aider"), Path.join(project_root, ".aider"))

    {:ok,
     %{
       target: "instructions-only",
       scope: "project",
       destination: project_root
     }}
  end

  defp do_install(%SkillTarget{id: "hermes-native"}, scope, project_root, skills, opts)
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
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{target: "hermes-native", scope: scope, destination: skill_root, agent_destination: base}}
  end

  defp do_install(%SkillTarget{id: "openclaw-native"}, scope, project_root, skills, opts)
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
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{
       target: "openclaw-native",
       scope: scope,
       destination: skill_root,
       agent_destination: config_root
     }}
  end

  defp do_install(%SkillTarget{id: "openclaw-plugin"}, scope, project_root, _skills, _opts)
       when scope in ["user", "project", "export"] do
    install_plugin_bundle("openclaw-plugin", "openclaw", scope, project_root)
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

  defp do_install(%SkillTarget{id: "droid-bundle"}, scope, project_root, skills, opts)
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
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{target: "droid-bundle", scope: scope, destination: skill_root, agent_destination: base}}
  end

  defp do_install(%SkillTarget{id: "forge-acp"}, scope, project_root, skills, opts)
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
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{target: "forge-acp", scope: scope, destination: skill_root, agent_destination: forge_root}}
  end

  defp do_install(%SkillTarget{id: "copilot-plugin"}, scope, project_root, _skills, _opts)
       when scope in ["user", "project", "export"] do
    install_plugin_bundle("copilot-plugin", "copilot", scope, project_root)
  end

  defp do_install(%SkillTarget{id: "multica-native"}, scope, project_root, _skills, opts)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export("multica-native", project_root, scope: scope)

    {skills_root, multica_root} =
      if scope == "user" do
        {Path.join(user_home(), ".agents/skills"), Path.join(user_home(), ".multica")}
      else
        {Path.join(project_root, ".agents/skills"), Path.join(project_root, ".multica")}
      end

    copy_tree_contents(Path.join(plan.output_dir, ".agents/skills"), skills_root)
    copy_tree_contents(Path.join(plan.output_dir, ".multica"), multica_root)

    if scope == "project" do
      maybe_install_project_agents_md!(plan.output_dir, project_root, opts)
    end

    {:ok,
     %{
       target: "multica-native",
       scope: scope,
       destination: multica_root,
       skills_destination: skills_root,
       commands_destination: Path.join(multica_root, "commands"),
       config_destination: Path.join(multica_root, "controlkeel-mcp.json")
     }}
  end

  defp do_install(
         %SkillTarget{id: "antigravity-cli-native"},
         "project",
         project_root,
         _skills,
         opts
       ) do
    {:ok, plan} = Exporter.export("antigravity-cli-native", project_root, scope: "project")
    agents_root = Path.join(project_root, ".agents")

    copy_tree_contents(Path.join(plan.output_dir, ".agents"), agents_root)
    File.cp!(Path.join(plan.output_dir, "GEMINI.md"), Path.join(project_root, "GEMINI.md"))
    maybe_install_project_agents_md!(plan.output_dir, project_root, opts)

    {:ok,
     %{
       target: "antigravity-cli-native",
       scope: "project",
       destination: agents_root,
       skills_destination: Path.join(agents_root, "skills"),
       plugins_destination: Path.join(agents_root, "plugins/controlkeel"),
       rules_destination: Path.join(agents_root, "rules"),
       hooks_destination: Path.join(agents_root, "hooks.json"),
       config_destination: Path.join(agents_root, "mcp_config.json")
     }}
  end

  defp do_install(%SkillTarget{id: target}, "export", project_root, _skills, _opts)
       when is_binary(target) do
    Exporter.export(target, project_root, scope: "export")
  end

  # Catch-all: any target/scope combination without an explicit installer returns
  # an explicit error instead of crashing with FunctionClauseError. This covers
  # runtime targets that declare project scope but are only installable via export.
  defp do_install(%SkillTarget{id: target}, scope, _project_root, _skills, _opts) do
    {:error, {:unsupported_install, target, scope}}
  end

  defp normalize_scope(target, scope) do
    scope = to_string(scope || target.default_scope)

    if scope in target.supported_scopes do
      {:ok, scope}
    else
      {:error, {:unsupported_scope, target.id, scope, target.supported_scopes}}
    end
  end

  defp merge_claude_settings(path, new_settings) do
    existing =
      case File.read(path) do
        {:ok, contents} -> Jason.decode!(contents)
        {:error, _} -> %{}
      end

    merged =
      Map.merge(existing, new_settings, fn
        "hooks", old_hooks, new_hooks ->
          Map.merge(old_hooks, new_hooks)

        _key, _old, new_val ->
          new_val
      end)

    File.write!(path, Jason.encode!(merged, pretty: true) <> "\n")
  end

  # Check whether .agents/skills/ already has all the skills we'd write,
  # meaning another agent with native skill support already populated it.
  # Avoids redundant copies that waste MCP host context tokens.
  defp compat_skills_already_populated?(compat_root, skills) do
    manifest = read_skills_manifest(compat_root)
    current_names = Enum.map(skills, & &1.name)
    Enum.all?(current_names, &(&1 in manifest))
  end

  # Variant for copy_tree_contents-based flows that don't have a skills list.
  # Checks if the compat dir already has any CK-managed skill directories.
  defp compat_dir_populated?(compat_root) do
    manifest = read_skills_manifest(compat_root)
    length(manifest) > 0
  end

  defp copy_skills(skills, destination_root) do
    File.mkdir_p!(destination_root)

    current_names = Enum.map(skills, & &1.name)
    prune_orphaned_skills(destination_root, current_names)

    Enum.each(skills, fn skill ->
      destination = Path.join(destination_root, skill.name)

      unless same_path?(skill.skill_dir, destination) do
        replace_directory!(skill.skill_dir, destination)
      end
    end)

    write_skills_manifest(destination_root, current_names)
  end

  # Remove skill dirs CK installed on a previous run but is no longer
  # installing. Only names recorded in CK's own per-destination manifest are
  # pruned, so user-authored skills sharing the directory are never deleted.
  defp prune_orphaned_skills(destination_root, current_names) do
    orphans = read_skills_manifest(destination_root) -- current_names

    Enum.each(orphans, fn name ->
      if safe_skill_name?(name), do: File.rm_rf!(Path.join(destination_root, name))
    end)
  end

  defp safe_skill_name?(name) do
    is_binary(name) and name not in ["", ".", ".."] and
      not String.contains?(name, "/") and not String.contains?(name, "\\")
  end

  defp read_skills_manifest(destination_root) do
    path = Path.join(destination_root, @skills_manifest_file)

    with {:ok, body} <- File.read(path),
         {:ok, %{"skills" => skills}} when is_list(skills) <- Jason.decode(body) do
      Enum.filter(skills, &is_binary/1)
    else
      _ -> []
    end
  end

  defp write_skills_manifest(destination_root, names) do
    payload = %{
      "schema_version" => 1,
      "controlkeel_version" => to_string(Application.spec(:controlkeel, :vsn) || "unknown"),
      "updated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "skills" => names
    }

    File.write!(
      Path.join(destination_root, @skills_manifest_file),
      Jason.encode!(payload, pretty: true) <> "\n"
    )
  end

  defp copy_tree_contents(source_root, destination_root) do
    File.mkdir_p!(destination_root)

    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      source = Path.join(source_root, entry)
      destination = Path.join(destination_root, entry)
      File.rm_rf!(destination)
      copy_path!(source, destination)
    end)
  end

  defp replace_directory!(source_root, destination_root) do
    File.rm_rf!(destination_root)
    File.mkdir_p!(destination_root)

    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      copy_path!(Path.join(source_root, entry), Path.join(destination_root, entry))
    end)
  end

  defp copy_path!(source, destination) do
    cond do
      File.dir?(source) ->
        File.mkdir_p!(destination)

        source
        |> File.ls!()
        |> Enum.each(fn entry ->
          copy_path!(Path.join(source, entry), Path.join(destination, entry))
        end)

      true ->
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(source, destination)
    end
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

  defp maybe_install_project_agents_md!(plan_output_dir, project_root, opts) do
    if Keyword.get(opts, :write_agents_md, true) != false do
      install_project_agents_md!(plan_output_dir, project_root)
    end
  end

  defp install_project_agents_md!(plan_output_dir, project_root) do
    generated_path = Path.join(plan_output_dir, "AGENTS.md")
    destination_path = Path.join(project_root, "AGENTS.md")
    generated = File.read!(generated_path) |> String.trim()

    destination =
      case File.read(destination_path) do
        {:ok, contents} -> sanitize_agents_md(contents)
        {:error, _reason} -> nil
      end

    updated =
      cond do
        generated == "" ->
          destination

        destination in [nil, ""] ->
          generated <> "\n"

        String.trim(destination) == generated ->
          destination

        true ->
          upsert_managed_block(destination, generated)
      end

    updated =
      case updated do
        nil -> nil
        contents -> sanitize_agents_md(contents)
      end

    if updated do
      File.write!(destination_path, updated)
    end
  end

  defp upsert_managed_block(existing, generated) do
    block = Enum.join([@managed_agents_start, generated, @managed_agents_end], "\n")

    case split_managed_block(existing) do
      {prefix, _existing_block, suffix} ->
        join_sections(prefix, block, suffix)

      nil ->
        [String.trim_trailing(existing), block]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
        |> Kernel.<>("\n")
    end
  end

  defp split_managed_block(existing) do
    with {start_index, _} <- :binary.match(existing, @managed_agents_start),
         {end_index, _} <- :binary.match(existing, @managed_agents_end) do
      prefix = String.slice(existing, 0, start_index) |> String.trim_trailing()
      suffix_start = end_index + byte_size(@managed_agents_end)
      suffix = String.slice(existing, suffix_start..-1//1) |> String.trim_leading()
      block = String.slice(existing, start_index, suffix_start - start_index)
      {prefix, block, suffix}
    else
      _ -> nil
    end
  end

  defp join_sections(prefix, block, suffix) do
    [prefix, block, suffix]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp sanitize_agents_md(nil), do: nil

  defp sanitize_agents_md(contents) do
    contents
    # Strip orphaned partial HTML comment prefixes left by earlier broken writes.
    |> String.replace(~r/(?:\n[ \t]*<![ \t]*)+(?=\n[ \t]*<!-- controlkeel:start -->)/m, "\n")
    # Strip a lone "<!" line before the managed block (do not use \s* here — it would eat newlines).
    |> String.replace(~r/\n<!\n+(?=<!-- controlkeel:start -->)/, "\n")
    # Strip broken ControlKeel comment lines WITHOUT closing --> (e.g. "<!-- controlkee" alone on a line).
    |> String.replace(~r/\n[ \t]*<!--\s*controlkee(?!l:(?:start|end))[^>\n]*\n/i, "\n")
    # Strip orphaned well-formed ControlKeel comment fragments (with closing -->, but not start/end markers).
    |> String.replace(~r/\n[ \t]*<!--\s*controlkee(?!l:(?:start|end))[^>]*-->\s*\n/i, "\n")
    |> String.replace(~r/\n[ \t]*<!--\s*controlkeel(?!:(?:start|end))\s*-->\s*\n/i, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  defp same_path?(left, right) do
    Path.expand(left) == Path.expand(right)
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  defp plugin_install_root("codex", "user", _project_root),
    do: Path.join(user_home(), "plugins/controlkeel")

  defp plugin_install_root("codex", "project", project_root),
    do: Path.join(project_root, "plugins/controlkeel")

  defp plugin_install_root("claude", "user", _project_root),
    do: Path.join(user_home(), ".claude/plugins/controlkeel")

  defp plugin_install_root("claude", "project", project_root),
    do: Path.join(project_root, ".claude/plugins/controlkeel")

  defp plugin_install_root("copilot", "user", _project_root),
    do: Path.join(user_home(), ".copilot/plugins/controlkeel")

  defp plugin_install_root("copilot", "project", project_root),
    do: Path.join(project_root, ".copilot/plugins/controlkeel")

  defp plugin_install_root("openclaw", "user", _project_root),
    do: Path.join(user_home(), ".openclaw/plugins/controlkeel")

  defp plugin_install_root("openclaw", "project", project_root),
    do: Path.join(project_root, ".openclaw/plugins/controlkeel")

  defp codex_marketplace_destination("user", _project_root),
    do: Path.join(user_home(), ".agents/plugins/marketplace.json")

  defp codex_marketplace_destination("project", project_root),
    do: Path.join(project_root, ".agents/plugins/marketplace.json")

  defp install_plugin_bundle(target_id, _plugin_id, "export", project_root) do
    Exporter.export(target_id, project_root, scope: "export")
  end

  defp install_plugin_bundle(target_id, plugin_id, scope, project_root)
       when scope in ["user", "project"] do
    {:ok, plan} = Exporter.export(target_id, project_root, scope: scope)
    plugin_root = plugin_install_root(plugin_id, scope, project_root)

    File.rm_rf!(plugin_root)
    File.mkdir_p!(Path.dirname(plugin_root))
    File.cp_r!(plan.output_dir, plugin_root)

    result = %{
      target: target_id,
      scope: scope,
      destination: plugin_root
    }

    case plugin_id do
      "codex" ->
        marketplace_destination = codex_marketplace_destination(scope, project_root)
        File.mkdir_p!(Path.dirname(marketplace_destination))

        File.cp!(
          Path.join(plugin_root, ".agents/plugins/marketplace.json"),
          marketplace_destination
        )

        {:ok, Map.put(result, :marketplace_destination, marketplace_destination)}

      _ ->
        {:ok, result}
    end
  end

  # Returns true when the source plugin.json version is strictly older than the
  # version already recorded in the destination plugin.json on disk.
  defp plugin_version_downgrade?(src_path, dest_path) do
    with {:ok, src_raw} <- File.read(src_path),
         {:ok, src_data} <- Jason.decode(src_raw),
         src_vsn when is_binary(src_vsn) <- Map.get(src_data, "version"),
         {:ok, dest_raw} <- File.read(dest_path),
         {:ok, dest_data} <- Jason.decode(dest_raw),
         dest_vsn when is_binary(dest_vsn) <- Map.get(dest_data, "version") do
      parse_plugin_vsn(src_vsn) < parse_plugin_vsn(dest_vsn)
    else
      _ -> false
    end
  end

  defp parse_plugin_vsn(vsn) when is_binary(vsn) do
    vsn
    |> String.split(".")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, _} -> n
        :error -> 0
      end
    end)
  end

  defp cline_home do
    System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
  end

  defp cline_documents_dir(name) do
    Path.join([user_home(), "Documents", "Cline", name])
  end

  defp read_plugin_version(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, data} <- Jason.decode(raw),
         vsn when is_binary(vsn) <- Map.get(data, "version") do
      vsn
    else
      _ -> nil
    end
  end
end
