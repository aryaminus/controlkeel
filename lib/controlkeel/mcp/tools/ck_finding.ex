defmodule ControlKeel.MCP.Tools.CkFinding do
  @moduledoc false

  alias ControlKeel.Mission

  @allowed_decisions ~w(allow warn block escalate_to_human)

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, _session} <- fetch_session(session_id),
         {:ok, _task_id} <- validate_task(task_id, session_id),
         {:ok, attrs} <- normalize(arguments, session_id, task_id),
         {:ok, resolved_ids} <- resolve_matching_findings(attrs),
         {:ok, finding} <- Mission.create_finding(attrs) do
      {:ok,
       %{
         "finding_id" => finding.id,
         "status" => finding.status,
         "requires_human" => finding.status in ["blocked", "escalated"],
         "resolved_finding_ids" => resolved_ids,
         "resolved_findings_count" => length(resolved_ids),
         "summary" =>
           "Recorded #{finding.severity} #{finding.category} finding for #{finding.title}."
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments, session_id, task_id) do
    with {:ok, category} <- required_binary(arguments, "category"),
         {:ok, severity} <- required_binary(arguments, "severity"),
         {:ok, rule_id} <- required_binary(arguments, "rule_id"),
         {:ok, plain_message} <- required_binary(arguments, "plain_message"),
         {:ok, decision} <- optional_decision(arguments) do
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

      {:ok,
       %{
         title: title,
         severity: severity,
         category: category,
         rule_id: rule_id,
         plain_message: plain_message,
         status: status_for_decision(decision),
         auto_resolved: decision == "allow",
         metadata: metadata,
         session_id: session_id
       }}
    end
  end

  defp resolve_matching_findings(%{session_id: session_id, status: "approved"} = attrs) do
    query =
      Mission.list_findings()
      |> Enum.filter(fn finding ->
        finding.session_id == session_id and
          finding.rule_id == attrs.rule_id and
          finding.category == attrs.category and
          finding.status in ["open", "blocked", "escalated"]
      end)

    resolved_ids =
      Enum.reduce(query, [], fn finding, acc ->
        case Mission.approve_finding(finding) do
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

  defp status_for_decision("block"), do: "blocked"
  defp status_for_decision("escalate_to_human"), do: "escalated"
  defp status_for_decision("allow"), do: "approved"
  defp status_for_decision(_decision), do: "open"
end
