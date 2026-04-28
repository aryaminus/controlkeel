defmodule ControlKeel.MCP.Tools.CkGoal do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Memory
  alias ControlKeel.Memory.Record
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  @goal_statuses ~w(active paused completed superseded)
  @goal_horizons ~w(task session workspace)
  @max_limit 25

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- required_integer(arguments, "session_id"),
         {:ok, session} <- fetch_session(session_id),
         {:ok, mode} <- required_mode(arguments) do
      run_mode(mode, arguments, session)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  def statuses, do: @goal_statuses
  def horizons, do: @goal_horizons

  defp run_mode("record", arguments, session) do
    with {:ok, task_id} <- optional_integer(arguments, "task_id"),
         :ok <- validate_task(task_id, session.id),
         {:ok, goal} <- required_binary(arguments, "goal"),
         {:ok, status} <- optional_status(arguments, "status", "active"),
         {:ok, horizon} <- optional_horizon(arguments, task_id),
         {:ok, record} <- create_goal(arguments, session, task_id, goal, status, horizon) do
      {:ok,
       %{
         "recorded" => true,
         "goal_id" => record.id,
         "title" => record.title,
         "status" => status,
         "horizon" => horizon,
         "session_id" => record.session_id,
         "task_id" => record.task_id
       }}
    end
  end

  defp run_mode("list", arguments, session) do
    with {:ok, task_id} <- optional_integer(arguments, "task_id"),
         :ok <- validate_task(task_id, session.id),
         {:ok, status_filter} <- optional_status_filter(arguments),
         {:ok, limit} <- optional_limit(arguments) do
      goals =
        session_goal_query(session.id, task_id, limit)
        |> Repo.all()
        |> Enum.filter(&match_status?(&1, status_filter))

      {:ok,
       %{
         "session_id" => session.id,
         "task_id" => task_id,
         "status" => status_filter,
         "count" => length(goals),
         "goals" => Enum.map(goals, &goal_summary/1)
       }}
    end
  end

  defp run_mode("update_status", arguments, session) do
    with {:ok, goal_id} <- required_integer(arguments, "goal_id"),
         {:ok, status} <- optional_status(arguments, "status", nil),
         {:ok, goal_record} <- fetch_goal(goal_id, session.id),
         {:ok, updated} <-
           update_goal_status(goal_record, status, Map.get(arguments, "progress_note")) do
      {:ok,
       %{
         "updated" => true,
         "goal_id" => updated.id,
         "status" => goal_status(updated),
         "progress_note" => get_in(updated.metadata || %{}, ["progress_note"])
       }}
    end
  end

  defp fetch_session(session_id) do
    case Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp fetch_goal(goal_id, session_id) do
    case Memory.get_record(goal_id) do
      %Record{session_id: ^session_id, record_type: "goal"} = record ->
        {:ok, record}

      %Record{session_id: ^session_id} ->
        {:error, {:invalid_arguments, "`goal_id` must refer to a goal record"}}

      nil ->
        {:error, {:invalid_arguments, "`goal_id` was not found"}}

      _other ->
        {:error, {:invalid_arguments, "`goal_id` must belong to the current session"}}
    end
  end

  defp create_goal(arguments, session, task_id, goal, status, horizon) do
    metadata =
      Map.get(arguments, "metadata", %{})
      |> ensure_map()
      |> Map.put_new("source", "mcp")
      |> Map.put("goal_status", status)
      |> Map.put("goal_horizon", horizon)
      |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

    Memory.record(%{
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: task_id,
      record_type: "goal",
      title: title_for(arguments, goal),
      summary: summary_for(arguments, goal, status),
      body: body_for(arguments, goal),
      tags: goal_tags(Map.get(arguments, "tags"), status, horizon),
      source_type: Map.get(arguments, "source_type", "generated"),
      source_id: Map.get(arguments, "source_id"),
      metadata: metadata
    })
  end

  defp update_goal_status(record, status, progress_note) do
    metadata =
      (record.metadata || %{})
      |> Map.put("goal_status", status)
      |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
      |> maybe_put_progress(progress_note)

    attrs = %{
      title: record.title,
      summary: update_summary(record.summary, progress_note, status),
      body: record.body,
      tags: retag_goal(record.tags || [], status),
      source_type: record.source_type,
      source_id: record.source_id,
      metadata: metadata
    }

    record
    |> Record.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_put_progress(metadata, note) when is_binary(note) do
    case String.trim(note) do
      "" -> metadata
      trimmed -> Map.put(metadata, "progress_note", trimmed)
    end
  end

  defp maybe_put_progress(metadata, _note), do: metadata

  defp update_summary(summary, note, status) when is_binary(note) do
    case String.trim(note) do
      "" -> summary || "Goal is now #{status}"
      trimmed -> trimmed
    end
  end

  defp update_summary(summary, _note, _status), do: summary

  defp session_goal_query(session_id, task_id, limit) do
    Record
    |> where(
      [r],
      r.session_id == ^session_id and r.record_type == "goal" and is_nil(r.archived_at)
    )
    |> maybe_filter_task(task_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
  end

  defp maybe_filter_task(query, nil), do: query
  defp maybe_filter_task(query, task_id), do: where(query, [r], r.task_id == ^task_id)

  defp match_status?(_record, "all"), do: true
  defp match_status?(record, status), do: goal_status(record) == status

  defp goal_summary(record) do
    metadata = record.metadata || %{}

    %{
      "id" => record.id,
      "title" => record.title,
      "summary" => record.summary,
      "status" => goal_status(record),
      "horizon" => metadata["goal_horizon"] || infer_horizon(record),
      "progress_note" => metadata["progress_note"],
      "tags" => record.tags,
      "task_id" => record.task_id,
      "inserted_at" => record.inserted_at,
      "updated_at" => metadata["updated_at"]
    }
  end

  defp goal_status(record) do
    get_in(record.metadata || %{}, ["goal_status"]) || "active"
  end

  defp infer_horizon(%Record{task_id: nil}), do: "session"
  defp infer_horizon(_record), do: "task"

  defp title_for(arguments, goal) do
    case Map.get(arguments, "title") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> goal |> String.trim() |> String.slice(0, 80)
    end
  end

  defp summary_for(arguments, goal, status) do
    case Map.get(arguments, "summary") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> "[#{status}] " <> (goal |> String.trim() |> String.slice(0, 140))
    end
  end

  defp body_for(arguments, goal) do
    case Map.get(arguments, "body") do
      value when is_binary(value) and value != "" -> value
      _ -> goal
    end
  end

  defp goal_tags(tags, status, horizon) do
    tags
    |> normalize_tags()
    |> Kernel.++(["goal", status, horizon])
    |> Enum.uniq()
  end

  defp retag_goal(tags, status) do
    tags
    |> normalize_tags()
    |> Enum.reject(&(&1 in @goal_statuses))
    |> Kernel.++([status])
    |> Enum.uniq()
  end

  defp normalize_tags(tags) when is_list(tags), do: Enum.map(tags, &to_string/1)

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(_tags), do: []

  defp required_mode(arguments) do
    case Map.get(arguments, "mode") do
      mode when mode in ["record", "list", "update_status"] -> {:ok, mode}
      _ -> {:error, {:invalid_arguments, "`mode` must be one of: record, list, update_status"}}
    end
  end

  defp optional_status(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value when value in @goal_statuses ->
        {:ok, value}

      nil ->
        {:error, {:invalid_arguments, "`#{key}` is required"}}

      _ ->
        {:error,
         {:invalid_arguments, "`#{key}` must be one of: #{Enum.join(@goal_statuses, ", ")}"}}
    end
  end

  defp optional_status_filter(arguments) do
    case Map.get(arguments, "status", "active") do
      "all" ->
        {:ok, "all"}

      value when value in @goal_statuses ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`status` must be one of: all, #{Enum.join(@goal_statuses, ", ")}"}}
    end
  end

  defp optional_horizon(arguments, task_id) do
    default = if task_id, do: "task", else: "session"

    case Map.get(arguments, "horizon", default) do
      value when value in @goal_horizons ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`horizon` must be one of: #{Enum.join(@goal_horizons, ", ")}"}}
    end
  end

  defp optional_limit(arguments) do
    case Map.get(arguments, "limit", 10) do
      value when is_integer(value) and value > 0 and value <= @max_limit -> {:ok, value}
      value when is_binary(value) -> parse_limit(value)
      _ -> {:error, {:invalid_arguments, "`limit` must be between 1 and #{@max_limit}"}}
    end
  end

  defp parse_limit(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 and parsed <= @max_limit -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`limit` must be between 1 and #{@max_limit}"}}
    end
  end

  defp validate_task(nil, _session_id), do: :ok

  defp validate_task(task_id, session_id) do
    case Mission.get_task(task_id) do
      %{session_id: ^session_id} -> :ok
      nil -> {:error, {:invalid_arguments, "`task_id` was not found"}}
      _other -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
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

  defp normalize_integer(_value, key),
    do: {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}

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

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}
end
