defmodule ControlKeel.MCP.Tools.CkFinding do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Precedent

  @allowed_decisions ~w(allow warn block escalate_to_human)
  @disposition_modes ~w(resolve dismiss escalate)

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, _session} <- fetch_session(session_id),
         {:ok, mode} <- normalize_mode(arguments) do
      case mode do
        "create" -> do_create(arguments, session_id)
        disposition -> do_dispose(disposition, arguments, session_id)
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize_mode(arguments) do
    case Map.get(arguments, "mode", "create") do
      "create" ->
        {:ok, "create"}

      mode when mode in @disposition_modes ->
        {:ok, mode}

      _ ->
        {:error,
         {:invalid_arguments, "`mode` must be one of: create, resolve, dismiss, escalate"}}
    end
  end

  # ---- create (default mode) ----

  defp do_create(arguments, session_id) do
    with {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, _task_id} <- validate_task(task_id, session_id),
         {:ok, attrs} <- normalize(arguments, session_id, task_id),
         {:ok, resolved_ids} <- resolve_matching_findings(attrs),
         {:ok, finding} <- Mission.create_finding(attrs) do
      {:ok,
       %{
         "mode" => "create",
         "finding_id" => finding.id,
         "status" => finding.status,
         "requires_human" => finding.status in ["blocked", "escalated"],
         "precedent" => finding_precedent(session_id, finding.rule_id),
         "resolved_finding_ids" => resolved_ids,
         "resolved_findings_count" => length(resolved_ids),
         "extends_finding_id" => finding.extends_finding_id,
         "contradicts_finding_id" => finding.contradicts_finding_id,
         "summary" =>
           "Recorded #{finding.severity} #{finding.category} finding for #{finding.title}."
       }}
    end
  end

  defp finding_precedent(session_id, rule_id) do
    with %{workspace_id: workspace_id} <- Mission.get_session(session_id) do
      Precedent.for_rule_id(rule_id, workspace_id: workspace_id, exclude_session_id: session_id)
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  # ---- disposition modes (resolve | dismiss | escalate) ----

  defp do_dispose(mode, arguments, session_id) do
    reason = optional_binary(arguments, "reason")

    case optional_integer(arguments, "finding_id") do
      {:ok, nil} -> dispose_bulk(mode, arguments, session_id, reason)
      {:ok, finding_id} -> dispose_single(mode, finding_id, session_id, reason)
      error -> error
    end
  end

  defp dispose_single(mode, finding_id, session_id, reason) do
    case Mission.get_finding(finding_id) do
      nil ->
        {:error, {:invalid_arguments, "`finding_id` #{finding_id} was not found"}}

      %{session_id: ^session_id} = finding ->
        case Mission.dispose_finding(mode, finding, disposition_opts(reason)) do
          {:ok, updated} ->
            {:ok,
             %{
               "mode" => mode,
               "finding_id" => updated.id,
               "status" => updated.status,
               "disposed_finding_ids" => [updated.id],
               "disposed_count" => 1,
               "summary" =>
                 "#{disposition_verb(mode)} finding #{updated.id} (now #{updated.status})."
             }}

          {:error, err} ->
            {:error, {:invalid_arguments, "Could not #{mode} finding: #{inspect(err)}"}}
        end

      _other ->
        {:error,
         {:invalid_arguments, "`finding_id` #{finding_id} does not belong to this session"}}
    end
  end

  defp dispose_bulk(mode, arguments, session_id, reason) do
    filter =
      %{reason: reason}
      |> put_filter(:rule_id, optional_binary(arguments, "rule_id"))
      |> put_filter(:category, optional_binary(arguments, "category"))
      |> put_filter(:statuses, bulk_statuses(arguments))

    if filter_present?(filter) do
      {:ok, %{count: count, ids: ids}} =
        Mission.dispose_session_findings(
          session_id,
          Map.put(filter, :disposition_opts, disposition_opts(reason)),
          mode
        )

      {:ok,
       %{
         "mode" => mode,
         "disposed_finding_ids" => ids,
         "disposed_count" => count,
         "summary" => "#{disposition_verb(mode)} #{count} finding(s) by filter."
       }}
    else
      {:error,
       {:invalid_arguments,
        "Bulk disposition requires `finding_id`, or at least one of `rule_id` / `category` / `status`."}}
    end
  end

  defp bulk_statuses(arguments) do
    case optional_binary(arguments, "status") do
      nil -> nil
      status -> [status]
    end
  end

  defp put_filter(map, _key, nil), do: map
  defp put_filter(map, key, value), do: Map.put(map, key, value)

  defp filter_present?(filter) do
    Enum.any?([:rule_id, :category, :statuses], &Map.has_key?(filter, &1))
  end

  defp disposition_verb("resolve"), do: "Resolved"
  defp disposition_verb("dismiss"), do: "Dismissed"
  defp disposition_verb("escalate"), do: "Escalated"

  defp disposition_opts(reason) do
    [reason: reason, actor_source: "mcp", actor_identifier: "ck_finding"]
  end

  # ---- create-path helpers ----

  defp normalize(arguments, session_id, task_id) do
    with {:ok, category} <- required_binary(arguments, "category"),
         {:ok, severity} <- required_binary(arguments, "severity"),
         {:ok, rule_id} <- required_binary(arguments, "rule_id"),
         {:ok, plain_message} <- required_binary(arguments, "plain_message"),
         {:ok, decision} <- optional_decision(arguments),
         {:ok, extends_finding_id} <- optional_integer(arguments, "extends_finding_id"),
         {:ok, contradicts_finding_id} <- optional_integer(arguments, "contradicts_finding_id") do
      title =
        case Map.get(arguments, "title") do
          value when is_binary(value) and value != "" -> value
          _ -> humanize_rule(rule_id)
        end

      metadata =
        Map.get(arguments, "metadata", %{})
        |> ensure_map()
        |> Map.put_new("source", "mcp")
        |> maybe_put("task_id", task_id)

      attrs =
        %{
          title: title,
          severity: severity,
          category: category,
          rule_id: rule_id,
          plain_message: plain_message,
          status: Mission.status_for_decision(decision),
          auto_resolved: decision == "allow",
          metadata: metadata,
          session_id: session_id
        }
        |> maybe_put(:extends_finding_id, extends_finding_id)
        |> maybe_put(:contradicts_finding_id, contradicts_finding_id)

      {:ok, attrs}
    end
  end

  defp resolve_matching_findings(%{session_id: session_id, status: "approved"} = attrs) do
    # Use scoped query instead of loading all findings into memory
    findings = Mission.list_findings_for_session(session_id)

    query =
      Enum.filter(findings, fn finding ->
        finding.rule_id == attrs.rule_id and
          finding.category == attrs.category and
          finding.status in ["open", "blocked"]
      end)

    resolved_ids =
      Enum.reduce(query, [], fn finding, acc ->
        case Mission.approve_finding(finding,
               actor_source: "mcp",
               actor_identifier: "ck_finding:auto_resolve"
             ) do
          {:ok, updated} -> [updated.id | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, resolved_ids}
  end

  defp resolve_matching_findings(_attrs), do: {:ok, []}

  defp fetch_session(session_id) do
    case Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp validate_task(nil, _session_id), do: {:ok, nil}

  defp validate_task(task_id, session_id) do
    case Mission.get_task!(task_id) do
      %{session_id: ^session_id} -> {:ok, task_id}
      _task -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  rescue
    Ecto.NoResultsError -> {:error, {:invalid_arguments, "`task_id` was not found"}}
  end

  defp required_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  defp optional_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp required_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> {:error, {:invalid_arguments, "`#{key}` is required"}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` is required"}}
    end
  end

  defp optional_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp optional_decision(arguments) do
    case Map.get(arguments, "decision", "warn") do
      decision when decision in @allowed_decisions ->
        {:ok, decision}

      _ ->
        {:error,
         {:invalid_arguments, "`decision` must be allow, warn, block, or escalate_to_human"}}
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp humanize_rule(rule_id) do
    rule_id
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
