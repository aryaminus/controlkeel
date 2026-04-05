defmodule ControlKeel.WorkspaceContext do
  @moduledoc false

  alias ControlKeel.ProjectBinding

  @instruction_candidates [
    {"AGENTS.md", "instructions"},
    {".github/controlkeel/README.md", "controlkeel_guidance"},
    {"README.md", "readme"}
  ]

  @manifest_candidates [
    {"mix.exs", "manifest"},
    {"mix.lock", "manifest"},
    {"package.json", "manifest"},
    {"Dockerfile", "manifest"},
    {"docker-compose.yml", "manifest"}
  ]

  def build(project_root) when is_binary(project_root) do
    root = Path.expand(project_root)

    cond do
      not File.dir?(root) ->
        unavailable_context(root, "project_root_missing")

      true ->
        build_from_root(root)
    end
  end

  def build(_project_root), do: unavailable_context(nil, "project_root_missing")

  def resolve_project_root(session, fallback_root \\ File.cwd!())

  def resolve_project_root(%{id: session_id, metadata: metadata}, fallback_root) do
    runtime_root = get_in(metadata || %{}, ["runtime_context", "project_root"])

    cond do
      is_binary(runtime_root) and runtime_root != "" ->
        Path.expand(runtime_root)

      true ->
        case ProjectBinding.read_effective(fallback_root) do
          {:ok, binding, _mode} ->
            if binding["session_id"] == session_id do
              binding["project_root"]
            else
              nil
            end

          _ ->
            nil
        end
    end
  end

  def resolve_project_root(_session, _fallback_root), do: nil

  defp build_from_root(root) do
    case repo_root(root) do
      {:ok, repo_root} ->
        status_counts = git_status_counts(repo_root)
        instruction_files = discovered_files(repo_root, @instruction_candidates)
        key_files = discovered_files(repo_root, @manifest_candidates)
        branch = git_value(repo_root, ["rev-parse", "--abbrev-ref", "HEAD"])
        head_sha = git_value(repo_root, ["rev-parse", "HEAD"])

        context = %{
          "available" => true,
          "project_root" => root,
          "repo_root" => repo_root,
          "git" => %{
            "available" => true,
            "branch" => branch,
            "head_sha" => head_sha,
            "status_counts" => status_counts
          },
          "instruction_files" => instruction_files,
          "key_files" => key_files
        }

        summary = summary_text(context)
        cache_key = cache_key(context)

        Map.merge(context, %{
          "summary_text" => summary,
          "cache_key" => cache_key
        })

      {:error, reason} ->
        unavailable_context(root, reason)
    end
  end

  defp unavailable_context(project_root, reason) do
    %{
      "available" => false,
      "project_root" => project_root,
      "repo_root" => nil,
      "git" => %{
        "available" => false,
        "branch" => nil,
        "head_sha" => nil,
        "status_counts" => %{"modified" => 0, "staged" => 0, "untracked" => 0}
      },
      "instruction_files" => [],
      "key_files" => [],
      "summary_text" => "Workspace context unavailable.",
      "cache_key" => cache_key(%{"project_root" => project_root, "reason" => reason}),
      "reason" => reason
    }
  end

  defp repo_root(root) do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], cd: root, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> {:error, "git_unavailable"}
    end
  end

  defp git_value(root, args) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  end

  defp git_status_counts(root) do
    case System.cmd("git", ["status", "--porcelain"], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{"modified" => 0, "staged" => 0, "untracked" => 0}, fn line, acc ->
          cond do
            String.starts_with?(line, "??") ->
              Map.update!(acc, "untracked", &(&1 + 1))

            true ->
              acc
              |> maybe_increment("staged", String.at(line, 0) not in [nil, " "])
              |> maybe_increment("modified", String.at(line, 1) not in [nil, " "])
          end
        end)

      _ ->
        %{"modified" => 0, "staged" => 0, "untracked" => 0}
    end
  end

  defp discovered_files(root, candidates) do
    Enum.flat_map(candidates, fn {relative_path, kind} ->
      path = Path.join(root, relative_path)

      if File.regular?(path) do
        {:ok, stat} = File.stat(path)
        contents = File.read!(path)

        [
          %{
            "path" => relative_path,
            "kind" => kind,
            "size_bytes" => stat.size,
            "sha256" => Base.encode16(:crypto.hash(:sha256, contents), case: :lower)
          }
        ]
      else
        []
      end
    end)
  end

  defp summary_text(context) do
    branch = get_in(context, ["git", "branch"]) || "unknown"
    sha = get_in(context, ["git", "head_sha"]) || "unknown"
    counts = get_in(context, ["git", "status_counts"]) || %{}

    instruction_names =
      context
      |> Map.get("instruction_files", [])
      |> Enum.map(& &1["path"])
      |> Enum.join(", ")

    manifest_names =
      context
      |> Map.get("key_files", [])
      |> Enum.map(& &1["path"])
      |> Enum.join(", ")

    "Repo #{Path.basename(context["repo_root"] || context["project_root"] || ".")} on #{branch}@#{String.slice(sha, 0, 7)} with #{counts["modified"] || 0} modified, #{counts["staged"] || 0} staged, and #{counts["untracked"] || 0} untracked files. Instructions: #{blank_or_none(instruction_names)}. Key files: #{blank_or_none(manifest_names)}."
  end

  defp cache_key(context) do
    payload =
      context
      |> Map.take([
        "available",
        "project_root",
        "repo_root",
        "git",
        "instruction_files",
        "key_files"
      ])
      |> Jason.encode!()

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
  end

  defp maybe_increment(map, _key, false), do: map
  defp maybe_increment(map, key, true), do: Map.update!(map, key, &(&1 + 1))

  defp blank_or_none(""), do: "none"
  defp blank_or_none(value), do: value
end
