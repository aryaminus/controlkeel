defmodule ControlKeel.Governance.TechDebtDetector do
  @moduledoc """
  Detects accumulating tech-debt patterns across sessions in a workspace.

  When an AI agent silently patches the same module repeatedly without an
  intervening refactor, the work feels productive but the codebase accumulates
  the kind of hacks a human writing by hand would have noticed and cleaned up.

  Two signal families:
    * CK-TECHDEBT-001 ("repeated_patches"): >= threshold findings have been
      recorded against the same `Finding.metadata["path"]` without an
      intervening refactor/cleanup commit on that path.
    * CK-TECHDEBT-002 ("unresolved_pattern"): the same `rule_id` (excluding
      the CK-TECHDEBT-* family itself) has fired across >= threshold distinct
      sessions in the workspace, suggesting the underlying issue is being
      patched, not resolved.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Session}

  @default_lookback_sessions 10
  @default_threshold 3
  @refactor_pattern ~r/refactor|cleanup|tech[-_ ]debt/i

  @doc """
  Detect tech-debt signals for the current session by looking across recent
  sessions in the same workspace.

  Options:
    * `:lookback_sessions` - how many recent sessions to scan (default 10)
    * `:threshold` - minimum count to emit a signal (default 3)
    * `:project_root` - path to the git checkout used for refactor-commit
      lookup; when nil, refactor detection is skipped
  """
  def detect_for_session(session_id, opts \\ []) do
    lookback = Keyword.get(opts, :lookback_sessions, @default_lookback_sessions)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    project_root = Keyword.get(opts, :project_root)

    session = Mission.get_session!(session_id)
    session_ids = recent_session_ids(session.workspace_id, lookback)
    findings = load_findings(session_ids)

    repeated_patches(findings, threshold, project_root) ++
      unresolved_patterns(findings, threshold)
  end

  defp recent_session_ids(workspace_id, lookback) do
    Session
    |> where([s], s.workspace_id == ^workspace_id)
    |> order_by(desc: :id)
    |> limit(^lookback)
    |> select([s], s.id)
    |> Repo.all()
  end

  defp load_findings([]), do: []

  defp load_findings(session_ids) do
    Finding
    |> where([f], f.session_id in ^session_ids)
    |> Repo.all()
  end

  defp repeated_patches(findings, threshold, project_root) do
    findings
    |> Enum.filter(&path_in_metadata?/1)
    |> Enum.group_by(&path_from_finding/1)
    |> Enum.flat_map(fn {path, items} ->
      if length(items) >= threshold and not refactor_seen?(path, project_root) do
        [build_repeated_patch_signal(path, items)]
      else
        []
      end
    end)
  end

  defp unresolved_patterns(findings, threshold) do
    findings
    |> Enum.reject(&tech_debt_rule?/1)
    |> Enum.group_by(& &1.rule_id)
    |> Enum.flat_map(fn {rule_id, items} ->
      # Optimized: Use MapSet.new/2 instead of Enum.map/2 and Enum.uniq/1 to avoid intermediate list allocations
      distinct_sessions = items |> MapSet.new(& &1.session_id)

      if MapSet.size(distinct_sessions) >= threshold do
        [build_unresolved_pattern_signal(rule_id, items, distinct_sessions)]
      else
        []
      end
    end)
  end

  defp tech_debt_rule?(%{rule_id: rule_id}) when is_binary(rule_id),
    do: String.starts_with?(rule_id, "CK-TECHDEBT-")

  defp tech_debt_rule?(_), do: false

  defp path_in_metadata?(%{metadata: %{} = m}) do
    Map.has_key?(m, "path") or Map.has_key?(m, :path)
  end

  defp path_in_metadata?(_), do: false

  defp path_from_finding(%{metadata: m}) do
    Map.get(m, "path") || Map.get(m, :path)
  end

  defp refactor_seen?(_path, nil), do: false

  defp refactor_seen?(path, project_root) do
    case ControlKeel.Git.cmd(["log", "-n", "20", "--pretty=%s", "--", path],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.any?(&Regex.match?(@refactor_pattern, &1))

      _ ->
        false
    end
  end

  defp build_repeated_patch_signal(path, items) do
    session_ids = items |> Enum.map(& &1.session_id) |> Enum.uniq() |> Enum.sort()

    %{
      rule_id: "CK-TECHDEBT-001",
      signal_type: "repeated_patches",
      path: path,
      count: length(items),
      recent_session_ids: session_ids,
      message:
        "#{length(items)} findings on #{path} across #{length(session_ids)} session(s) " <>
          "without an intervening refactor commit"
    }
  end

  defp build_unresolved_pattern_signal(rule_id, items, distinct_sessions) do
    %{
      rule_id: "CK-TECHDEBT-002",
      signal_type: "unresolved_pattern",
      path: nil,
      count: length(items),
      recent_session_ids: Enum.sort(distinct_sessions),
      message:
        "Rule #{rule_id} fired #{length(items)} times across " <>
          "#{MapSet.size(distinct_sessions)} sessions without resolution"
    }
  end
end
