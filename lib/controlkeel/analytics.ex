defmodule ControlKeel.Analytics do
  @moduledoc "Local analytics persistence and derived ship metrics."

  import Ecto.Query, warn: false

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Mission.{Finding, Invocation, ProofBundle, Session, Task, TaskCheckpoint}
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
    sessions = recent_sessions(limit)
    session_sets = session_event_sets(Enum.map(sessions, & &1.id))
    recent_sessions = ship_session_rows(sessions)
    {outcome_metrics, agent_outcomes} = outcome_metrics(sessions)

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
      recent_session_count: length(recent_sessions),
      outcome_metrics: outcome_metrics,
      agent_outcomes: agent_outcomes
    }
  end

  def recent_ship_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, @recent_session_limit)

    limit
    |> recent_sessions()
    |> ship_session_rows()
  end

  defp recent_sessions(limit) do
    Session
    |> order_by(desc: :inserted_at)
    |> preload(:workspace)
    |> limit(^limit)
    |> Repo.all()
  end

  defp ship_session_rows(sessions) do
    Enum.map(sessions, fn session ->
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

  defp session_event_sets(session_ids) when session_ids == [] or session_ids == nil, do: %{}

  defp session_event_sets(session_ids) do
    Event
    |> where([event], not is_nil(event.session_id) and event.session_id in ^session_ids)
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

  defp outcome_metrics([]) do
    {default_outcome_metrics(), []}
  end

  defp outcome_metrics(sessions) do
    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, fn session -> {session.id, session} end)
    tasks = list_tasks_for_sessions(session_ids)
    task_ids = Enum.map(tasks, & &1.id)
    completed_tasks = Enum.filter(tasks, &(&1.status in ["done", "verified"]))
    latest_proofs_by_task = latest_proofs_by_task(task_ids)

    proof_backed_completed_tasks =
      Enum.count(completed_tasks, &Map.has_key?(latest_proofs_by_task, &1.id))

    deploy_ready_task_ids =
      latest_proofs_by_task
      |> Enum.filter(fn {_task_id, proof} -> proof.deploy_ready end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    deploy_ready_completed_tasks =
      Enum.count(completed_tasks, &MapSet.member?(deploy_ready_task_ids, &1.id))

    deploy_ready_cost_cents =
      deploy_ready_task_ids
      |> MapSet.to_list()
      |> list_invocations_for_tasks()
      |> Enum.sum_by(&(&1.estimated_cost_cents || 0))

    resumed_task_ids =
      task_ids
      |> list_resume_checkpoints()
      |> Enum.map(& &1.task_id)
      |> MapSet.new()

    risky_findings = list_risky_findings(session_ids)

    metrics = %{
      proof_backed_task_coverage_percent:
        percent(proof_backed_completed_tasks, length(completed_tasks)),
      deploy_ready_task_rate_percent:
        percent(deploy_ready_completed_tasks, proof_backed_completed_tasks),
      cost_per_deploy_ready_task_cents:
        average_cents(deploy_ready_cost_cents, deploy_ready_completed_tasks),
      resume_success_rate_percent:
        percent(
          Enum.count(completed_tasks, &MapSet.member?(resumed_task_ids, &1.id)),
          MapSet.size(resumed_task_ids)
        ),
      risky_intervention_rate_percent:
        percent(
          Enum.count(risky_findings, &(&1.status in ["blocked", "escalated"])),
          length(risky_findings)
        ),
      average_time_to_first_deploy_ready_proof_seconds:
        average(first_deploy_ready_proof_latencies(sessions_by_id, session_ids))
    }

    {metrics, build_agent_outcomes(tasks, sessions_by_id, deploy_ready_task_ids)}
  end

  defp list_tasks_for_sessions([]), do: []

  defp list_tasks_for_sessions(session_ids) do
    Task
    |> where([task], task.session_id in ^session_ids)
    |> Repo.all()
  end

  defp list_invocations_for_tasks([]), do: []

  defp list_invocations_for_tasks(task_ids) do
    Invocation
    |> where([invocation], invocation.task_id in ^task_ids)
    |> Repo.all()
  end

  defp list_resume_checkpoints([]), do: []

  defp list_resume_checkpoints(task_ids) do
    TaskCheckpoint
    |> where(
      [checkpoint],
      checkpoint.task_id in ^task_ids and checkpoint.checkpoint_type == "resume"
    )
    |> Repo.all()
  end

  defp list_risky_findings([]), do: []

  defp list_risky_findings(session_ids) do
    Finding
    |> where(
      [finding],
      finding.session_id in ^session_ids and finding.severity in ["high", "critical"]
    )
    |> Repo.all()
  end

  defp latest_proofs_by_task([]), do: %{}

  defp latest_proofs_by_task(task_ids) do
    ProofBundle
    |> where([proof], proof.task_id in ^task_ids)
    |> Repo.all()
    |> Enum.reduce(%{}, fn proof, acc ->
      Map.update(acc, proof.task_id, proof, fn existing ->
        if newer_proof?(proof, existing), do: proof, else: existing
      end)
    end)
  end

  defp newer_proof?(candidate, current) do
    compare_proof_sort_key(candidate, current) == :gt
  end

  defp compare_proof_sort_key(left, right) do
    left_key = {left.version || 0, left.generated_at || left.inserted_at, left.id || 0}
    right_key = {right.version || 0, right.generated_at || right.inserted_at, right.id || 0}

    cond do
      left_key > right_key -> :gt
      left_key < right_key -> :lt
      true -> :eq
    end
  end

  defp first_deploy_ready_proof_latencies(sessions_by_id, session_ids) do
    ProofBundle
    |> where([proof], proof.session_id in ^session_ids and proof.deploy_ready == true)
    |> Repo.all()
    |> Enum.reduce(%{}, fn proof, acc ->
      Map.update(acc, proof.session_id, proof.generated_at, fn current ->
        case DateTime.compare(proof.generated_at, current) do
          :lt -> proof.generated_at
          _ -> current
        end
      end)
    end)
    |> Enum.map(fn {session_id, generated_at} ->
      sessions_by_id
      |> Map.fetch!(session_id)
      |> Map.get(:inserted_at)
      |> elapsed_seconds(generated_at)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_agent_outcomes(tasks, sessions_by_id, deploy_ready_task_ids) do
    tasks
    |> Enum.group_by(fn task ->
      sessions_by_id
      |> Map.get(task.session_id)
      |> session_agent()
    end)
    |> Enum.map(fn {agent, agent_tasks} ->
      total = length(agent_tasks)
      completed = Enum.count(agent_tasks, &(&1.status in ["done", "verified"]))
      verified = Enum.count(agent_tasks, &(&1.status == "verified"))
      deploy_ready = Enum.count(agent_tasks, &MapSet.member?(deploy_ready_task_ids, &1.id))

      %{
        agent: agent,
        total_tasks: total,
        completed_tasks: completed,
        verified_tasks: verified,
        deploy_ready_tasks: deploy_ready,
        completion_rate_percent: percent(completed, total)
      }
    end)
    |> Enum.sort_by(fn row ->
      {-(row.completion_rate_percent || 0.0), -row.completed_tasks, row.agent}
    end)
  end

  defp session_agent(nil), do: "Unknown agent"

  defp session_agent(session) do
    get_in(session.execution_brief || %{}, ["agent"]) ||
      if(session.workspace, do: session.workspace.agent, else: nil) ||
      "Unknown agent"
  end

  defp default_outcome_metrics do
    %{
      proof_backed_task_coverage_percent: nil,
      deploy_ready_task_rate_percent: nil,
      cost_per_deploy_ready_task_cents: nil,
      resume_success_rate_percent: nil,
      risky_intervention_rate_percent: nil,
      average_time_to_first_deploy_ready_proof_seconds: nil
    }
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

  defp percent(_numerator, 0), do: nil
  defp percent(_numerator, nil), do: nil

  defp percent(numerator, denominator) do
    Float.round(numerator / denominator * 100, 1)
  end

  defp average_cents(_total_cents, 0), do: nil
  defp average_cents(_total_cents, nil), do: nil
  defp average_cents(total_cents, count), do: Float.round(total_cents / count, 1)

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
