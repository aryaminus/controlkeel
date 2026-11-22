defmodule ControlKeel.Project.Root do
  @moduledoc false

  @markers [
    ".git",
    "mix.exs",
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
    "requirements.txt",
    "Pipfile",
    "tox.ini",
    "DESCRIPTION",
    "renv.lock",
    "Project.toml",
    "JuliaProject.toml",
    "package.json",
    "deno.json",
    "Cargo.toml",
    "go.mod",
    "Gemfile",
    "composer.json",
    "pom.xml",
    "build.gradle",
    "stack.yaml",
    "pubspec.yaml",
    "Package.swift",
    "build.zig",
    "CMakeLists.txt",
    "meson.build",
    "Makefile",
    ".editorconfig"
  ]

  def resolve(path \\ File.cwd!()) do
    start_path = path |> normalize_start_path() |> realpath()

    start_path
    |> find_project_root(start_path)
    |> realpath()
  end

  def project_root?(path \\ File.cwd!()) do
    resolve(path)
    |> has_project_marker?()
  end

  defp normalize_start_path(path) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      expanded
    else
      Path.dirname(expanded)
    end
  end

  defp find_project_root(path, fallback) do
    cond do
      has_project_marker?(path) -> path
      Path.dirname(path) == path -> fallback
      true -> find_project_root(Path.dirname(path), fallback)
    end
  end

  defp has_project_marker?(path) do
    Enum.any?(@markers, &File.exists?(Path.join(path, &1)))
  end

  defp realpath(expanded) do
    case :os.type() do
      {:win32, _} ->
        expanded

      _ ->
        resolve_symlinks(expanded)
    end
  end

  # Resolve symlinks in the path without shelling out to `pwd -P`.
  # Walks each path component and resolves symlinks via :file.read_link/1.
  # Falls back to the expanded path if any step fails.
  defp resolve_symlinks(path) do
    [root | components] = Path.split(path)

    Enum.reduce_while(components, root, fn component, acc ->
      candidate = Path.join(acc, component)

      case :file.read_link(String.to_charlist(candidate)) do
        {:ok, target_charlist} ->
          target = List.to_string(target_charlist)

          absolute =
            if Path.type(target) == :absolute,
              do: target,
              else: Path.join(Path.dirname(candidate), target)

          {:cont, Path.expand(absolute)}

        {:error, _} ->
          # Not a symlink — keep accumulating.
          {:cont, candidate}
      end
    end)
  rescue
    _ -> path
  end
end
