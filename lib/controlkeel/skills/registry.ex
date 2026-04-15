defmodule ControlKeel.Skills.Registry do
  @moduledoc """
  Discovers and catalogs AgentSkills from standard skill directories.

  Project-level skills are only loaded when the project is trusted by ControlKeel
  or explicitly overridden.
  """

  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills.Parser
  alias ControlKeel.Skills.SkillDiagnostic
  alias ControlKeel.Skills.SkillTarget

  @project_skill_dirs [
    ".agents/skills",
    ".codex/skills",
    ".claude/skills",
    ".copilot/skills",
    ".github/skills",
    ".cline/skills",
    ".roo/skills",
    ".hermes/skills",
    ".factory/skills",
    "skills"
  ]

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
    skills
    |> Enum.group_by(& &1.name)
    |> Enum.reduce({[], []}, fn {_name, group}, {kept, diagnostics} ->
      {winner, new_diags} = resolve_duplicate_skill_group(group)
      {[winner | kept], diagnostics ++ new_diags}
    end)
    |> then(fn {kept, diagnostics} ->
      {Enum.reverse(kept), Enum.reverse(diagnostics)}
    end)
  end

  defp resolve_duplicate_skill_group([only]), do: {only, []}

  defp resolve_duplicate_skill_group(group) do
    preferred = preferred_skill_definition(group)

    new_diags =
      Enum.flat_map(group, fn skill ->
        cond do
          skill.path == preferred.path ->
            []

          identical_skill_copy?(preferred, skill) ->
            []

          true ->
            [
              %SkillDiagnostic{
                level: "warn",
                code: "shadowed_skill",
                message:
                  "Another skill with the same name took precedence (canonical builtin or earlier discovery path). This copy was ignored.",
                path: skill.path,
                skill_name: skill.name
              }
            ]
        end
      end)

    {preferred, new_diags}
  end

  defp preferred_skill_definition(group) do
    builtins = Enum.filter(group, &builtin_skill_path?/1)

    case builtins do
      [] ->
        hd(group)

      [_ | _] ->
        Enum.min_by(builtins, & &1.path, :string)
    end
  end

  defp builtin_skill_path?(skill) do
    norm = skill.path |> to_string() |> String.replace("\\", "/")
    String.contains?(norm, "/priv/skills/")
  end

  defp identical_skill_copy?(first, second) do
    first.path != second.path and
      case {File.read(first.path), File.read(second.path)} do
        {{:ok, first_contents}, {:ok, second_contents}} -> first_contents == second_contents
        _ -> false
      end
  end

  defp install_state(skill, project_root) do
    targets =
      SkillTarget.ids()
      |> Enum.reduce([], fn target, acc ->
        maybe_mark_exported(acc, target, project_root, skill)
      end)

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
      Path.join(export_root, ".codex/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".claude/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".copilot/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".github/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".cline/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".roo/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".hermes/skills/#{skill.name}/SKILL.md"),
      Path.join(export_root, ".factory/skills/#{skill.name}/SKILL.md")
    ]

    if Enum.any?(skill_locations, &File.exists?/1), do: targets ++ [target], else: targets
  end

  defp native_locations(skill, project_root) do
    locations = user_locations(skill.name) ++ project_locations(project_root, skill.name)

    locations
    |> Enum.filter(&File.exists?/1)
    |> Enum.uniq()
  end

  defp project_locations(nil, _name), do: []

  defp project_locations(project_root, name) do
    root = Path.expand(project_root)

    [
      Path.join(root, ".agents/skills/#{name}/SKILL.md"),
      Path.join(root, ".codex/skills/#{name}/SKILL.md"),
      Path.join(root, ".claude/skills/#{name}/SKILL.md"),
      Path.join(root, ".copilot/skills/#{name}/SKILL.md"),
      Path.join(root, ".github/skills/#{name}/SKILL.md"),
      Path.join(root, ".cline/skills/#{name}/SKILL.md"),
      Path.join(root, ".roo/skills/#{name}/SKILL.md"),
      Path.join(root, ".hermes/skills/#{name}/SKILL.md"),
      Path.join(root, ".factory/skills/#{name}/SKILL.md"),
      Path.join(root, "skills/#{name}/SKILL.md")
    ]
  end

  defp user_locations(name) do
    [
      user_location(".agents/skills/#{name}/SKILL.md"),
      user_location(".codex/skills/#{name}/SKILL.md"),
      user_location(".claude/skills/#{name}/SKILL.md"),
      user_location(".copilot/skills/#{name}/SKILL.md"),
      user_location(".cline/skills/#{name}/SKILL.md"),
      user_location(".roo/skills/#{name}/SKILL.md"),
      user_location(".hermes/skills/#{name}/SKILL.md"),
      user_location(".factory/skills/#{name}/SKILL.md"),
      user_location(".openclaw/skills/#{name}/SKILL.md")
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
    Enum.map(
      [
        ".agents/skills",
        ".codex/skills",
        ".claude/skills",
        ".copilot/skills",
        ".cline/skills",
        ".roo/skills",
        ".hermes/skills",
        ".factory/skills",
        ".openclaw/skills"
      ],
      &Path.join(user_home(), &1)
    )
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end
end
