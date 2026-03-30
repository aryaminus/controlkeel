defmodule ControlKeel.Learning.CrossProject do
  @moduledoc false

  alias ControlKeel.Memory

  def aggregate_findings(session_id, opts \\ []) do
    domain_pack = Keyword.get(opts, :domain_pack)

    case Memory.search("finding", session_id: session_id, top_k: 200) do
      %{entries: entries} ->
        findings = Enum.map(entries, &to_finding_map/1)

        patterns =
          findings
          |> Enum.group_by(&pattern_key/1)
          |> Enum.map(fn {key, group} ->
            %{
              key: key,
              count: length(group),
              severity: max_severity(group),
              examples: Enum.take(group, 3)
            }
          end)
          |> Enum.sort_by(& &1.count, :desc)

        {:ok,
         %{
           session_id: session_id,
           domain_pack: domain_pack,
           total_findings: length(findings),
           unique_patterns: length(patterns),
           patterns: patterns
         }}

      _ ->
        {:ok,
         %{
           session_id: session_id,
           domain_pack: domain_pack,
           total_findings: 0,
           unique_patterns: 0,
           patterns: []
         }}
    end
  end

  def store_patterns(session_id, patterns, opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    domain_pack = Keyword.get(opts, :domain_pack)

    results =
      Enum.map(patterns, fn pattern ->
        attrs = %{
          workspace_id: workspace_id,
          session_id: session_id,
          record_type: "checkpoint",
          title: "Cross-project pattern: #{pattern.key}",
          summary: "Pattern #{pattern.key} appeared #{pattern.count} times",
          body: pattern_key_to_text(pattern),
          tags:
            ["cross_project", "vulnerability_pattern", pattern.severity, domain_pack || "general"]
            |> Enum.reject(&is_nil/1),
          source_type: "cross_project_aggregation",
          source_id: "pattern:#{pattern.key}",
          metadata: %{
            key: pattern.key,
            count: pattern.count,
            severity: pattern.severity,
            domain_pack: domain_pack
          }
        }

        Memory.record(attrs)
      end)

    {:ok, results}
  end

  def search_similar(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    case Memory.search(query_text, top_k: limit) do
      %{entries: entries} ->
        filtered =
          entries
          |> Enum.filter(fn e ->
            tags = Map.get(e, :tags, [])
            "cross_project" in tags or "vulnerability_pattern" in tags
          end)

        {:ok, filtered}

      _ ->
        {:ok, []}
    end
  end

  def get_frequency_report(opts \\ []) do
    min_count = Keyword.get(opts, :min_count, 2)

    case Memory.search("cross_project vulnerability pattern", top_k: 100) do
      %{entries: entries} ->
        frequent =
          entries
          |> Enum.filter(fn e ->
            meta = Map.get(e, :metadata, %{})
            (Map.get(meta, "count", 0) || 0) >= min_count
          end)
          |> Enum.sort_by(
            fn e ->
              Map.get(e, :metadata, %{}) |> Map.get("count", 0) || 0
            end,
            :desc
          )

        {:ok, frequent}

      _ ->
        {:ok, []}
    end
  end

  defp to_finding_map(entry) do
    meta = Map.get(entry, :metadata, %{})

    %{
      id: Map.get(entry, :id),
      category: Map.get(meta, "category", "unknown"),
      rule_id: Map.get(meta, "rule_id", Map.get(meta, "rule", "unknown")),
      file: Map.get(meta, "file", ""),
      severity: Map.get(meta, "severity", Map.get(meta, "decision", "warn"))
    }
  end

  defp pattern_key(finding) do
    file_ext = finding.file |> Path.extname() |> String.downcase()
    "#{finding.category}:#{finding.rule_id}:#{file_ext}"
  end

  defp max_severity(findings) do
    severity_order = %{"block" => 4, "escalate_to_human" => 3, "warn" => 2, "allow" => 1}

    findings
    |> Enum.map(fn f ->
      Map.get(severity_order, f.severity, 0)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp pattern_key_to_text(pattern) do
    "Vulnerability pattern #{pattern.key} appeared #{pattern.count} times with severity #{pattern.severity}"
  end
end
