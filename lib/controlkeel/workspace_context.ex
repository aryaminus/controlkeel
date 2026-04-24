defmodule ControlKeel.WorkspaceContext do
  @moduledoc false

  alias ControlKeel.ProjectBinding

  @preview_bytes 220
  @recent_commit_limit 5
  @hotspot_commit_window 20
  @large_file_threshold_lines 500
  @very_large_file_threshold_lines 800
  @source_extensions ~w(.css .ex .exs .heex .js .json .md .ts .tsx .yaml .yml)

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
        orientation = orientation_snapshot(repo_root, instruction_files, key_files)
        design_drift = design_drift_snapshot(repo_root, status_counts)

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
          "key_files" => key_files,
          "orientation" => orientation,
          "design_drift" => design_drift
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
      "orientation" => %{
        "recent_commits" => [],
        "instruction_previews" => [],
        "key_file_previews" => [],
        "active_assumptions" => []
      },
      "design_drift" => %{
        "high_risk" => false,
        "signals" => [],
        "large_files" => [],
        "recent_hotspots" => [],
        "complexity_budget" => complexity_budget([], [], []),
        "summary" => "Design drift unavailable."
      },
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
        file_info(root, relative_path, kind)
        |> List.wrap()
      else
        []
      end
    end)
  end

  defp file_info(root, relative_path, kind) do
    path = Path.join(root, relative_path)

    with true <- File.regular?(path),
         {:ok, stat} <- File.stat(path),
         {:ok, contents} <- File.read(path) do
      [
        %{
          "path" => relative_path,
          "kind" => kind,
          "size_bytes" => stat.size,
          "sha256" => Base.encode16(:crypto.hash(:sha256, contents), case: :lower),
          "preview" => preview_text(contents),
          "line_count" => line_count(contents)
        }
      ]
    else
      _ -> []
    end
  end

  defp orientation_snapshot(repo_root, instruction_files, key_files) do
    %{
      "recent_commits" => recent_commits(repo_root),
      "instruction_previews" => preview_entries(instruction_files),
      "key_file_previews" => preview_entries(key_files),
      "active_assumptions" => active_assumptions(instruction_files, key_files)
    }
  end

  defp design_drift_snapshot(repo_root, status_counts) do
    large_files = large_file_signals(repo_root)
    hotspots = recent_hotspots(repo_root)
    signals = drift_signals(status_counts, large_files, hotspots)
    complexity_budget = complexity_budget(signals, large_files, hotspots)

    %{
      "high_risk" => Enum.any?(signals, &(&1["severity"] == "high")),
      "signals" => signals,
      "large_files" => large_files,
      "recent_hotspots" => hotspots,
      "complexity_budget" => complexity_budget,
      "diagnostic_findings" =>
        complexity_budget_findings(%{
          "signals" => signals,
          "large_files" => large_files,
          "recent_hotspots" => hotspots,
          "complexity_budget" => complexity_budget
        }),
      "summary" => drift_summary(signals)
    }
  end

  def complexity_budget(signals, large_files, hotspots)
      when is_list(signals) and is_list(large_files) and is_list(hotspots) do
    score =
      Enum.reduce(signals, 0, fn signal, acc ->
        acc +
          case signal["severity"] do
            "high" -> 50
            "medium" -> 25
            "low" -> 10
            _ -> 0
          end
      end)
      |> Kernel.+(min(length(large_files), 5) * 5)
      |> Kernel.+(min(length(hotspots), 5) * 5)
      |> min(100)

    level =
      cond do
        score >= 75 -> "high"
        score >= 40 -> "medium"
        score > 0 -> "low"
        true -> "clear"
      end

    %{
      "level" => level,
      "score" => score,
      "review_pressure" => review_pressure(level),
      "recommended_action" => complexity_budget_action(level)
    }
  end

  def complexity_budget_findings(design_drift, attrs \\ %{}) when is_map(design_drift) do
    budget = design_drift["complexity_budget"] || complexity_budget([], [], [])
    signals = design_drift["signals"] || []
    large_files = design_drift["large_files"] || []
    hotspots = design_drift["recent_hotspots"] || []

    base_finding =
      case budget["level"] do
        level when level in ["high", "medium"] ->
          [
            %{
              "category" => "design-drift",
              "severity" => if(level == "high", do: "high", else: "medium"),
              "rule_id" => "design.complexity_budget.#{level}",
              "title" => "Workspace complexity budget is #{level}",
              "plain_message" => budget["recommended_action"],
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "workspace_complexity_budget",
                  "complexity_budget" => budget,
                  "signals" => signals,
                  "large_files" => large_files,
                  "recent_hotspots" => hotspots
                })
            }
          ]

        _ ->
          []
      end

    large_file_findings =
      case budget["level"] do
        level when level in ["high", "medium"] ->
          Enum.map(large_files, fn file ->
            %{
              "category" => "design-drift",
              "severity" => if(file["line_count"] >= 800, do: "high", else: "medium"),
              "rule_id" => "design.large_file_budget_exceeded",
              "title" => "Large file contributes to complexity budget",
              "plain_message" =>
                "#{file["path"]} is #{file["line_count"]} lines. Large files increase review difficulty and make agent edits harder to validate.",
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "workspace_complexity_budget",
                  "file_path" => file["path"],
                  "line_count" => file["line_count"],
                  "complexity_level" => level
                })
            }
          end)

        _ ->
          []
      end

    hotspot_findings =
      case budget["level"] do
        level when level in ["high", "medium"] ->
          Enum.map(hotspots, fn hotspot ->
            %{
              "category" => "design-drift",
              "severity" => "medium",
              "rule_id" => "design.hotspot_churn",
              "title" => "Edit hotspot contributes to complexity budget",
              "plain_message" =>
                "#{hotspot["path"]} changed in #{hotspot["commit_count"]} of the last 20 commits. Repeated edits in a high-complexity workspace suggest unstable boundaries.",
              "metadata" =>
                Map.merge(attrs, %{
                  "diagnostic_source" => "workspace_complexity_budget",
                  "file_path" => hotspot["path"],
                  "commit_count" => hotspot["commit_count"],
                  "complexity_level" => level
                })
            }
          end)

        _ ->
          []
      end

    second_system_findings =
      if budget["level"] == "high" and budget["score"] >= 75 do
        [
          %{
            "category" => "design-drift",
            "severity" => "medium",
            "rule_id" => "planning.second_system_risk",
            "title" => "Second-system effect risk in high-complexity workspace",
            "plain_message" =>
              "Workspace complexity is very high (score #{budget["score"]}/100). Consider whether new features are genuinely needed or whether simplification and deletion would be more valuable.",
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "workspace_complexity_budget",
                "complexity_budget" => budget
              })
          }
        ]
      else
        []
      end

    base_finding ++ large_file_findings ++ hotspot_findings ++ second_system_findings
  end

  defp recent_commits(repo_root) do
    case System.cmd(
           "git",
           [
             "log",
             "--max-count=#{@recent_commit_limit}",
             "--pretty=format:%H%x1f%h%x1f%s%x1f%an"
           ],
           cd: repo_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          case String.split(line, <<31>>, parts: 4) do
            [sha, short_sha, subject, author] ->
              %{
                "sha" => sha,
                "short_sha" => short_sha,
                "subject" => subject,
                "author" => author
              }

            _other ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp preview_entries(files) do
    Enum.map(files, fn file ->
      %{
        "path" => file["path"],
        "kind" => file["kind"],
        "preview" => file["preview"],
        "line_count" => file["line_count"]
      }
    end)
  end

  defp active_assumptions(instruction_files, key_files) do
    (instruction_files ++ key_files)
    |> Enum.flat_map(fn file -> assumptions_from_preview(file["preview"]) end)
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp assumptions_from_preview(nil), do: []

  defp assumptions_from_preview(preview) do
    preview
    |> String.split(~r/[\n\.]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.length(&1) >= 12))
    |> Enum.take(2)
  end

  defp large_file_signals(repo_root) do
    repo_root
    |> tracked_source_files()
    |> Enum.map(fn relative_path ->
      path = Path.join(repo_root, relative_path)

      case File.read(path) do
        {:ok, contents} ->
          %{
            "path" => relative_path,
            "line_count" => line_count(contents)
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1["line_count"] >= @large_file_threshold_lines))
    |> Enum.sort_by(&{-&1["line_count"], &1["path"]})
    |> Enum.take(5)
  end

  defp recent_hotspots(repo_root) do
    case System.cmd(
           "git",
           ["log", "--max-count=#{@hotspot_commit_window}", "--name-only", "--pretty=format:"],
           cd: repo_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 == ""))
        |> Enum.filter(&source_like_path?/1)
        |> Enum.frequencies()
        |> Enum.filter(fn {_path, count} -> count >= 3 end)
        |> Enum.map(fn {path, count} -> %{"path" => path, "commit_count" => count} end)
        |> Enum.sort_by(&{-&1["commit_count"], &1["path"]})
        |> Enum.take(5)

      _ ->
        []
    end
  end

  defp drift_signals(status_counts, large_files, hotspots) do
    []
    |> maybe_add_uncommitted_signal(status_counts)
    |> maybe_add_large_file_signal(large_files)
    |> maybe_add_hotspot_signal(hotspots)
  end

  defp maybe_add_uncommitted_signal(signals, status_counts) do
    total =
      (status_counts["modified"] || 0) +
        (status_counts["staged"] || 0) +
        (status_counts["untracked"] || 0)

    if total >= 12 do
      [
        %{
          "code" => "uncommitted_worktree_pressure",
          "severity" => "medium",
          "summary" =>
            "The repo has #{total} outstanding file changes. Reacquiring context will get harder until the change set is narrowed or checkpointed."
        }
        | signals
      ]
    else
      signals
    end
  end

  defp maybe_add_large_file_signal(signals, large_files) do
    case large_files do
      [%{"path" => path, "line_count" => line_count} | _rest]
      when line_count >= @very_large_file_threshold_lines ->
        [
          %{
            "code" => "very_large_source_file",
            "severity" => "high",
            "summary" =>
              "#{path} is #{line_count} lines long. Large source files are a strong design-drift indicator and make agent edits harder to review."
          }
          | signals
        ]

      [%{"path" => path, "line_count" => line_count} | _rest] ->
        [
          %{
            "code" => "large_source_file",
            "severity" => "medium",
            "summary" =>
              "#{path} is #{line_count} lines long. Consider splitting boundaries before more generated code accumulates there."
          }
          | signals
        ]

      [] ->
        signals
    end
  end

  defp maybe_add_hotspot_signal(signals, hotspots) do
    case hotspots do
      [%{"path" => path, "commit_count" => count} | _rest] ->
        [
          %{
            "code" => "recent_edit_hotspot",
            "severity" => "medium",
            "summary" =>
              "#{path} changed in #{count} of the last #{@hotspot_commit_window} commits. Repeated edits often indicate unstable boundaries or unresolved design choices."
          }
          | signals
        ]

      [] ->
        signals
    end
  end

  defp drift_summary([]), do: "No obvious design-drift signals."

  defp drift_summary(signals) do
    signals
    |> Enum.map(& &1["summary"])
    |> Enum.join(" ")
  end

  defp review_pressure("high"), do: "require_small_steps_and_stronger_tests"
  defp review_pressure("medium"), do: "prefer_smaller_plan_or_refactor_note"
  defp review_pressure("low"), do: "watch"
  defp review_pressure(_level), do: "none"

  defp complexity_budget_action("high") do
    "Treat edits in drift-heavy modules as higher review pressure; ask for smaller steps, explicit tests, or a boundary-splitting note."
  end

  defp complexity_budget_action("medium") do
    "Call out drift in review packets and prefer scoped changes with targeted validation."
  end

  defp complexity_budget_action("low"), do: "Keep drift visible while work continues."
  defp complexity_budget_action(_level), do: "No complexity-budget action needed."

  defp tracked_source_files(repo_root) do
    case System.cmd("git", ["ls-files"], cd: repo_root, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&source_like_path?/1)

      _ ->
        []
    end
  end

  defp source_like_path?(path) do
    path
    |> Path.extname()
    |> then(&(&1 in @source_extensions))
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

    drift_summary =
      get_in(context, ["design_drift", "summary"]) || "No obvious design-drift signals."

    "Repo #{Path.basename(context["repo_root"] || context["project_root"] || ".")} on #{branch}@#{String.slice(sha, 0, 7)} with #{counts["modified"] || 0} modified, #{counts["staged"] || 0} staged, and #{counts["untracked"] || 0} untracked files. Instructions: #{blank_or_none(instruction_names)}. Key files: #{blank_or_none(manifest_names)}. Drift: #{drift_summary}"
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
        "key_files",
        "orientation",
        "design_drift"
      ])
      |> Jason.encode!()

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
  end

  defp maybe_increment(map, _key, false), do: map
  defp maybe_increment(map, key, true), do: Map.update!(map, key, &(&1 + 1))

  defp preview_text(contents) when is_binary(contents) do
    contents
    |> String.slice(0, @preview_bytes)
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(3)
    |> Enum.join(" ")
  end

  defp line_count(contents) when is_binary(contents) do
    contents
    |> String.split("\n", trim: false)
    |> length()
  end

  defp blank_or_none(""), do: "none"
  defp blank_or_none(value), do: value
end
