defmodule ControlKeel.Analytics do
  @moduledoc "Local analytics persistence and derived ship metrics."

  import Ecto.Query, warn: false

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Mission.{Finding, Session}
  alias ControlKeel.Repo

  @recent_session_limit 10
  @aggregate_session_limit 20
  @funnel_steps ~w(project_initialized agent_attached mission_created first_finding_recorded)

  def funnel_steps, do: @funnel_steps

  def stage_label("project_initialized"), do: "Project initialized"
  def stage_label("agent_attached"), do: "Agent attached"
  def stage_label("mission_created"), do: "Mission created"
  def stage_label("first_finding_recorded"), do: "First finding recorded"
  def stage_label(_stage), do: "Unknown"

  def record(attrs) when is_map(attrs) do
    attrs = normalize_record_attrs(attrs)

    case duplicate_first_finding_event(attrs) do
      %Event{} = event ->
        {:ok, event}

      nil ->
        %Event{}
        |> Event.changeset(attrs)
        |> Repo.insert()
    end
  end

  def session_metrics(session_id) when is_integer(session_id) do
    case Repo.get(Session, session_id) do
      nil ->
        nil

      %Session{} = session ->
        events = list_session_events(session_id)
        counts = finding_counts(session_id)
        stage = funnel_stage(events, counts.total_findings)
        started_at = session_started_at(session, events)
        first_finding_at = first_finding_at(session_id, events)

        %{
          session_id: session.id,
          funnel_stage: stage,
          time_to_first_finding_seconds: elapsed_seconds(started_at, first_finding_at),
          total_findings: counts.total_findings,
          blocked_findings_total: counts.blocked_findings_total,
          approved_findings_total: counts.approved_findings_total,
          rejected_findings_total: counts.rejected_findings_total
        }
    end
  end

  def funnel_summary(opts \\ []) do
    limit = Keyword.get(opts, :limit, @aggregate_session_limit)
    session_sets = session_event_sets()
    recent_sessions = recent_ship_sessions(limit: limit)

    latencies =
      recent_sessions |> Enum.map(& &1.time_to_first_finding_seconds) |> Enum.reject(&is_nil/1)

    findings = Enum.map(recent_sessions, & &1.total_findings)

    steps =
      Enum.map(@funnel_steps, fn step ->
        %{step: step, count: count_sessions_at_step(session_sets, step)}
      end)
      |> attach_conversion_rates()

    %{
      steps: steps,
      average_time_to_first_finding_seconds: average(latencies),
      median_time_to_first_finding_seconds: median(latencies),
      average_findings_per_session: average(findings),
      recent_session_count: length(recent_sessions)
    }
  end

  def recent_ship_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, @recent_session_limit)

    Session
    |> order_by(desc: :inserted_at)
    |> preload(:workspace)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn session ->
      metrics = session_metrics(session.id) || default_metrics(session.id)

      %{
        session_id: session.id,
        title: session.title,
        workspace_name: session.workspace && session.workspace.name,
        risk_tier: session.risk_tier,
        inserted_at: session.inserted_at,
        funnel_stage: metrics.funnel_stage,
        time_to_first_finding_seconds: metrics.time_to_first_finding_seconds,
        total_findings: metrics.total_findings,
        blocked_findings_total: metrics.blocked_findings_total
      }
    end)
  end

  defp normalize_record_attrs(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    %{
      event: attrs["event"],
      source: attrs["source"] || "app",
      session_id: normalize_integer(attrs["session_id"]),
      workspace_id: normalize_integer(attrs["workspace_id"]),
      project_root: blank_to_nil(attrs["project_root"]),
      metadata: normalize_map(attrs["metadata"]),
      happened_at: normalize_datetime(attrs["happened_at"]) || now()
    }
  end

  defp duplicate_first_finding_event(%{event: "first_finding_recorded", session_id: session_id})
       when is_integer(session_id) do
    Repo.get_by(Event, event: "first_finding_recorded", session_id: session_id)
  end

  defp duplicate_first_finding_event(_attrs), do: nil

  defp list_session_events(session_id) do
    Event
    |> where([event], event.session_id == ^session_id)
    |> order_by([event], asc: event.happened_at)
    |> Repo.all()
  end

  defp finding_counts(session_id) do
    findings =
      Finding
      |> where([finding], finding.session_id == ^session_id)
      |> select([finding], finding.status)
      |> Repo.all()

    %{
      total_findings: length(findings),
      blocked_findings_total: Enum.count(findings, &(&1 == "blocked")),
      approved_findings_total: Enum.count(findings, &(&1 == "approved")),
      rejected_findings_total: Enum.count(findings, &(&1 == "rejected"))
    }
  end

  defp session_started_at(session, events) do
    earliest_event_time(events, ["project_initialized", "agent_attached", "mission_created"]) ||
      session.inserted_at
  end

  defp first_finding_at(session_id, events) do
    earliest_event_time(events, ["first_finding_recorded"]) ||
      earliest_finding_inserted_at(session_id)
  end

  defp earliest_event_time(events, names) do
    names = MapSet.new(names)

    case events
         |> Enum.filter(&MapSet.member?(names, &1.event))
         |> Enum.map(& &1.happened_at) do
      [] ->
        nil

      [first | rest] ->
        Enum.reduce(rest, first, fn current, acc ->
          case DateTime.compare(current, acc) do
            :lt -> current
            _ -> acc
          end
        end)
    end
  end

  defp earliest_finding_inserted_at(session_id) do
    Finding
    |> where([finding], finding.session_id == ^session_id)
    |> order_by([finding], asc: finding.inserted_at)
    |> limit(1)
    |> select([finding], finding.inserted_at)
    |> Repo.one()
  end

  defp funnel_stage(events, total_findings) do
    event_names = events |> Enum.map(& &1.event) |> MapSet.new()

    cond do
      cumulative_stage?(event_names, "first_finding_recorded") or total_findings > 0 ->
        "first_finding_recorded"

      cumulative_stage?(event_names, "mission_created") ->
        "mission_created"

      cumulative_stage?(event_names, "agent_attached") ->
        "agent_attached"

      MapSet.member?(event_names, "project_initialized") ->
        "project_initialized"

      MapSet.member?(event_names, "mission_created") ->
        "mission_created"

      true ->
        "unknown"
    end
  end

  defp session_event_sets do
    Event
    |> where([event], not is_nil(event.session_id))
    |> select([event], {event.session_id, event.event})
    |> Repo.all()
    |> Enum.group_by(fn {session_id, _event} -> session_id end, fn {_session_id, event} ->
      event
    end)
    |> Enum.into(%{}, fn {session_id, events} -> {session_id, MapSet.new(events)} end)
  end

  defp count_sessions_at_step(session_sets, step) do
    Enum.count(session_sets, fn {_session_id, events} ->
      cumulative_stage?(events, step)
    end)
  end

  defp attach_conversion_rates(steps) do
    Enum.with_index(steps)
    |> Enum.map(fn
      {step, 0} ->
        Map.put(step, :conversion_percent, 100.0)

      {%{count: count} = step, index} ->
        previous = Enum.at(steps, index - 1).count

        conversion =
          if previous > 0 do
            Float.round(count / previous * 100, 1)
          else
            nil
          end

        Map.put(step, :conversion_percent, conversion)
    end)
  end

  defp cumulative_stage?(events, "project_initialized") do
    MapSet.member?(events, "project_initialized")
  end

  defp cumulative_stage?(events, "agent_attached") do
    cumulative_stage?(events, "project_initialized") and MapSet.member?(events, "agent_attached")
  end

  defp cumulative_stage?(events, "mission_created") do
    cumulative_stage?(events, "agent_attached") and MapSet.member?(events, "mission_created")
  end

  defp cumulative_stage?(events, "first_finding_recorded") do
    cumulative_stage?(events, "mission_created") and
      MapSet.member?(events, "first_finding_recorded")
  end

  defp elapsed_seconds(nil, _finished_at), do: nil
  defp elapsed_seconds(_started_at, nil), do: nil

  defp elapsed_seconds(started_at, finished_at) do
    diff = DateTime.diff(finished_at, started_at, :second)
    max(diff, 0)
  end

  defp average([]), do: nil

  defp average(values) do
    values
    |> Enum.sum()
    |> Kernel./(length(values))
    |> Float.round(1)
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    if rem(count, 2) == 1 do
      Enum.at(sorted, div(count, 2))
    else
      midpoint = div(count, 2)
      Float.round((Enum.at(sorted, midpoint - 1) + Enum.at(sorted, midpoint)) / 2, 1)
    end
  end

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_map(%{} = value), do: stringify_keys(value)
  defp normalize_map(_value), do: %{}

  defp normalize_datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)
  defp normalize_datetime(_value), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp default_metrics(session_id) do
    %{
      session_id: session_id,
      funnel_stage: "unknown",
      time_to_first_finding_seconds: nil,
      total_findings: 0,
      blocked_findings_total: 0,
      approved_findings_total: 0,
      rejected_findings_total: 0
    }
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
