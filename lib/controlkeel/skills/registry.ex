defmodule ControlKeel.Skills.Registry do
  @moduledoc """
  Discovers and catalogs AgentSkills from standard skill directories.

  Project-level skills are only loaded when the project is trusted by ControlKeel
  or explicitly overridden.
  """

  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills.Parser
  alias ControlKeel.Skills.SkillDiagnostic

  @project_skill_dirs [".agents/skills", ".claude/skills", ".github/skills"]

  def catalog(project_root \\ nil, opts \\ []) do
    analyze(project_root, opts).skills
  end

  def analyze(project_root \\ nil, opts \\ []) do
    trusted_project? = project_trusted?(project_root, opts)

    {skills, diagnostics} =
      project_root
      |> skill_dirs(trusted_project?)
      |> Enum.reduce({[], []}, fn %{path: dir, scope: scope}, {skills, diagnostics} ->
        {parsed, new_diagnostics} = scan_dir(dir, scope)
        {skills ++ parsed, diagnostics ++ new_diagnostics}
      end)

    {deduped_skills, dedupe_diagnostics} = deduplicate_by_name(skills)

    diagnostics =
      diagnostics ++
        dedupe_diagnostics ++
        project_trust_diagnostics(project_root, trusted_project?)

    %{
      skills:
        Enum.map(deduped_skills, &Map.put(&1, :install_state, install_state(&1, project_root))),
      diagnostics: diagnostics,
      trusted_project?: trusted_project?
    }
  end

  def diagnostics(project_root \\ nil, opts \\ []) do
    analyze(project_root, opts).diagnostics
  end

  def get(name, project_root \\ nil, opts \\ []) do
    Enum.find(catalog(project_root, opts), &(&1.name == name))
  end

  def names(project_root \\ nil, opts \\ []) do
    catalog(project_root, opts) |> Enum.map(& &1.name)
  end

  def prompt_block(project_root \\ nil, opts \\ []) do
    skills = catalog(project_root, opts)

    if skills == [] do
      ""
    else
      entries =
        Enum.map(skills, fn skill ->
          "  <skill>\n" <>
            "    <name>#{skill.name}</name>\n" <>
            "    <description>#{xml_escape(skill.description)}</description>\n" <>
            "    <location>#{skill.path}</location>\n" <>
            "  </skill>"
        end)

      "<available_skills>\n#{Enum.join(entries, "\n")}\n</available_skills>"
    end
  end

  def project_trusted?(nil, _opts), do: false

  def project_trusted?(project_root, opts) do
    cond do
      Keyword.get(opts, :trust_project_skills) == true ->
        true

      System.get_env("CONTROLKEEL_TRUST_PROJECT_SKILLS") in ~w(1 true TRUE yes YES) ->
        true

      match?({:ok, _binding, _mode}, ProjectBinding.read_effective(project_root)) ->
        true

      true ->
        false
    end
  end

  defp scan_dir(dir, scope) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.reduce({[], []}, fn entry, {skills, diagnostics} ->
          skill_dir = Path.join(dir, entry)
          skill_path = Path.join(skill_dir, "SKILL.md")

          if File.dir?(skill_dir) and File.exists?(skill_path) do
            case Parser.parse(skill_path, scope) do
              {:ok, skill} ->
                {[skill | skills], diagnostics}

              {:error, %SkillDiagnostic{} = diagnostic} ->
                {skills, [diagnostic | diagnostics]}

              {:error, reason} ->
                {skills,
                 [
                   %SkillDiagnostic{
                     level: "error",
                     code: "parse_failed",
                     message: "Failed to parse skill: #{inspect(reason)}",
                     path: skill_path
                   }
                   | diagnostics
                 ]}
            end
          else
            {skills, diagnostics}
          end
        end)
        |> then(fn {skills, diagnostics} ->
          {Enum.reverse(skills), Enum.reverse(diagnostics)}
        end)

      _ ->
        {[], []}
    end
  end

  defp skill_dirs(nil, _trusted_project?) do
    (user_skill_dirs() ++ [priv_skills_dir()])
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&dir_entry(&1, classify_scope(&1)))
  end

  defp skill_dirs(project_root, trusted_project?) do
    root = Path.expand(project_root)

    project_dirs =
      if trusted_project? do
        @project_skill_dirs
        |> Enum.map(&Path.join(root, &1))
      else
        []
      end

    (project_dirs ++ user_skill_dirs() ++ [priv_skills_dir()])
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&dir_entry(&1, classify_scope(&1, root)))
  end

  defp dir_entry(path, scope), do: %{path: path, scope: scope}

  defp deduplicate_by_name(skills) do
    Enum.reduce(skills, {[], MapSet.new(), []}, fn skill, {kept, seen, diagnostics} ->
      if MapSet.member?(seen, skill.name) do
        diagnostic = %SkillDiagnostic{
          level: "warn",
          code: "shadowed_skill",
          message:
            "A higher-precedence skill with the same name already exists. This copy was ignored.",
          path: skill.path,
          skill_name: skill.name
        }

        {kept, seen, [diagnostic | diagnostics]}
      else
        {[skill | kept], MapSet.put(seen, skill.name), diagnostics}
      end
    end)
    |> then(fn {skills, _seen, diagnostics} ->
      {Enum.reverse(skills), Enum.reverse(diagnostics)}
    end)
  end

  defp install_state(skill, project_root) do
    targets =
      []
      |> maybe_mark_exported("codex", project_root, skill)
      |> maybe_mark_exported("claude-plugin", project_root, skill)
      |> maybe_mark_exported("copilot-plugin", project_root, skill)
      |> maybe_mark_exported("open-standard", project_root, skill)

    %{
      "exported_targets" => targets,
      "native_locations" => native_locations(skill, project_root)
    }
  end

  defp maybe_mark_exported(targets, _target, nil, _skill), do: targets

  defp maybe_mark_exported(targets, target, project_root, skill) do
    export_root = Path.join(Path.expand(project_root), "controlkeel/dist/#{target}")

    skill_locations = [
      Path.join(export_root, "skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".agents/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".claude/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".github/skills/#{skill.name}/SKILL.md")
    ]

    if Enum.any?(skill_locations, &File.exists?/1), do: targets ++ [target], else: targets
  end

  defp native_locations(skill, project_root) do
    locations =
      [
        user_location(".agents/skills/#{skill.name}/SKILL.md"),
        user_location(".claude/skills/#{skill.name}/SKILL.md"),
        user_location(".copilot/skills/#{skill.name}/SKILL.md")
      ] ++
        project_locations(project_root, skill.name)

    locations
    |> Enum.filter(&File.exists?/1)
    |> Enum.uniq()
  end

  defp project_locations(nil, _name), do: []

  defp project_locations(project_root, name) do
    root = Path.expand(project_root)

    [
      Path.join(root, ".agents/skills/#{name}/SKILL.md"),
      Path.join(root, ".claude/skills/#{name}/SKILL.md"),
      Path.join(root, ".github/skills/#{name}/SKILL.md")
    ]
  end

  defp user_location(relative_path), do: Path.join(user_home(), relative_path)

  defp project_trust_diagnostics(nil, _trusted?), do: []

  defp project_trust_diagnostics(project_root, false) do
    [
      %SkillDiagnostic{
        level: "warn",
        code: "project_skills_untrusted",
        message:
          "Project-level skills were skipped because this project is not trusted by ControlKeel. Run `controlkeel bootstrap`, `controlkeel init`, or use an explicit trust override to load them.",
        path: Path.expand(project_root)
      }
    ]
  end

  defp project_trust_diagnostics(_project_root, true), do: []

  defp classify_scope(path, project_root \\ nil) do
    home = user_home()
    priv = priv_skills_dir()

    cond do
      String.starts_with?(path, priv) -> "builtin"
      project_root && String.starts_with?(path, project_root) -> "project"
      String.starts_with?(path, home) -> "user"
      true -> "project"
    end
  end

  defp priv_skills_dir do
    :controlkeel
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("skills")
  end

  defp xml_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp user_skill_dirs do
    Enum.map([".agents/skills", ".claude/skills", ".copilot/skills"], &Path.join(user_home(), &1))
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end
end
