defmodule ControlKeel.Skills.Pruner do
  @moduledoc """
  Collapses redundant duplicate skill copies.

  Only identical user-level copies (under CONTROLKEEL_HOME/HOME and outside the
  project root) are auto-removed; they are always redundant because hosts load
  project-level copies. Project host-specific copies are listed but kept — the
  user's primary host directory needs them. Shadowed copies (differing content)
  are never removed automatically.
  """

  alias ControlKeel.Skills.Registry

  def preview(project_root) do
    root = expand_root(project_root)
    analysis = Registry.analyze(root, report_identical_duplicates: true)

    duplicates =
      analysis.diagnostics
      |> Enum.filter(&(&1.code == "duplicate_skill_copy"))
      |> Enum.map(&duplicate_dir/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    user_level =
      duplicates
      |> Enum.filter(&user_level_dir?(&1, root))
      |> Enum.sort()

    project_groups =
      duplicates
      |> Enum.reject(&user_level_dir?(&1, root))
      |> Enum.group_by(&host_dir(&1, root))
      |> Enum.map(fn {host, dirs} ->
        %{host_dir: host, skills: dirs |> Enum.map(&Path.basename/1) |> Enum.sort()}
      end)
      |> Enum.sort_by(& &1.host_dir)

    %{
      user_level: user_level,
      user_level_count: length(user_level),
      project_groups: project_groups,
      identical_count: length(duplicates),
      shadowed_count: Enum.count(analysis.diagnostics, &(&1.code == "shadowed_skill"))
    }
  end

  def prune(project_root) do
    result = preview(project_root)

    removed =
      result.user_level
      |> Enum.filter(&removable?/1)
      |> Enum.map(fn dir ->
        File.rm_rf!(dir)
        dir
      end)

    {:ok, %{removed: removed, kept_project_groups: result.project_groups}}
  end

  defp duplicate_dir(%{path: path}) when is_binary(path),
    do: path |> Path.expand() |> Path.dirname()

  defp duplicate_dir(_diagnostic), do: nil

  defp user_level_dir?(dir, root) do
    path_within?(user_home(), dir) and not path_within?(root, dir)
  end

  defp host_dir(dir, root), do: dir |> Path.relative_to(root) |> Path.split() |> List.first()

  defp removable?(dir) do
    File.dir?(dir) and File.exists?(Path.join(dir, "SKILL.md")) and
      path_within?(user_home(), dir)
  end

  defp expand_root(project_root) when is_binary(project_root) and project_root != "",
    do: Path.expand(project_root)

  defp expand_root(_), do: File.cwd!()

  defp path_within?(root, candidate),
    do: String.starts_with?(candidate, Path.expand(root) <> "/")

  defp user_home do
    (System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!())
    |> Path.expand()
  end
end
