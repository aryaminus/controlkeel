defmodule ControlKeel.ProjectRoot do
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
    start_path = normalize_start_path(path)

    start_path
    |> find_project_root(start_path)
    |> realpath()
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
        case System.find_executable("pwd") do
          nil ->
            expanded

          executable ->
            case System.cmd(executable, ["-P"], cd: expanded, stderr_to_stdout: true) do
              {realpath, 0} -> String.trim(realpath)
              {_output, _code} -> expanded
            end
        end
    end
  end
end
