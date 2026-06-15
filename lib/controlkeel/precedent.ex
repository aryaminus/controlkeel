defmodule ControlKeel.Precedent do
  @moduledoc false

  alias ControlKeel.Memory

  @max_precedent_entries 3

  @doc """
  Look up prior finding dispositions for the given rule_ids, workspace-wide.

  Returns a list of compact precedent entries showing how the same rule was
  resolved in past sessions. Cross-session by design: institutional knowledge
  should survive session boundaries. A workspace_id is required — without it the
  underlying memory search is unscoped and would pull dispositions across every
  workspace, so a nil workspace_id deliberately returns no precedent.
  """
  def for_rule_ids(rule_ids, opts \\ []) when is_list(rule_ids) do
    case opts[:workspace_id] do
      nil ->
        []

      workspace_id ->
        exclude_session_id = opts[:exclude_session_id]
        limit = opts[:limit] || @max_precedent_entries

        rule_ids
        |> Enum.flat_map(fn rule_id ->
          search_precedent(rule_id, workspace_id, exclude_session_id)
        end)
        |> Enum.take(limit)
    end
  end

  def for_rule_id(rule_id, opts \\ []) when is_binary(rule_id) do
    for_rule_ids([rule_id], opts)
  end

  defp search_precedent(rule_id, workspace_id, exclude_session_id) do
    search = Memory.search(rule_id, workspace_id: workspace_id, top_k: 10, include_metadata: true)

    search.entries
    |> Enum.filter(fn entry ->
      meta = entry_metadata(entry)
      tags = entry_tags(entry)

      (rule_id in tags or meta["rule_id"] == rule_id) and
        entry_session_id(entry) != exclude_session_id and
        dispositioned?(entry)
    end)
    |> Enum.map(&precedent_summary/1)
  end

  # Nullable DB columns can surface as a present key with a nil value, so guard
  # with `|| %{}` / `|| []` rather than Map.get/3 defaults (which only apply when
  # the key is absent) to avoid BadMapError on downstream Map.get calls.
  defp entry_metadata(entry), do: Map.get(entry, :metadata) || %{}
  defp entry_tags(entry), do: Map.get(entry, :tags) || []

  defp entry_session_id(entry) do
    Map.get(entry, :session_id) || entry_metadata(entry)["session_id"]
  end

  defp dispositioned?(entry) do
    tags = entry_tags(entry)
    meta = entry_metadata(entry)

    status = meta["status"] || meta["finding_status"]

    status in ["approved", "rejected", "resolved", "dismissed", "escalated"] or
      Enum.any?(tags, &(&1 in ["approved", "rejected", "resolved", "dismissed", "escalated"]))
  end

  defp precedent_summary(entry) do
    meta = entry_metadata(entry)

    %{
      "rule_id" => Map.get(meta, "rule_id") || find_rule_tag(entry),
      "disposition" => Map.get(meta, "status") || Map.get(meta, "finding_status"),
      "session_id" => entry_session_id(entry),
      "title" => Map.get(entry, :title),
      "summary" => Map.get(entry, :summary),
      "recorded_at" =>
        Map.get(meta, "recorded_at") ||
          DateTime.to_iso8601(Map.get(entry, :inserted_at, DateTime.utc_now()))
    }
  end

  defp find_rule_tag(entry) do
    entry
    |> entry_tags()
    |> Enum.find(&String.contains?(&1, "."))
  end

  @doc """
  Build a workspace-wide precedent context for ck_context.

  Unlike retrieve_for_task (which is session-scoped), this searches across all
  sessions in the workspace for recent finding dispositions relevant to the
  current session's domain and active finding rule_ids. Returns no precedent
  when the session has no workspace_id, to avoid an unscoped cross-workspace
  search.
  """
  def workspace_precedent(session, opts \\ []) do
    case session.workspace_id do
      nil ->
        []

      workspace_id ->
        domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])
        active_rule_ids = active_finding_rule_ids(session)

        query_parts =
          [domain_pack | active_rule_ids]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")

        if query_parts == "" do
          []
        else
          search =
            Memory.search(query_parts,
              workspace_id: workspace_id,
              exclude_session_id: session.id,
              top_k: opts[:limit] || @max_precedent_entries,
              include_metadata: true
            )

          search.entries
          |> Enum.filter(&dispositioned?/1)
          |> Enum.map(&precedent_summary/1)
        end
    end
  end

  defp active_finding_rule_ids(session) do
    session.findings
    |> Enum.filter(&(&1.status in ["open", "blocked", "warn"]))
    |> Enum.map(& &1.rule_id)
    |> Enum.uniq()
  end
end
