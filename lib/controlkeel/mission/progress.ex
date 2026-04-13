defmodule ControlKeel.Mission.Progress do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Repo
  import Ecto.Query

  def compute(session_id) do
    session = Mission.get_session(session_id)

    if is_nil(session) do
      {:error, :session_not_found}
    else
      tasks = load_tasks(session_id)
      findings = load_findings(session_id)

      task_progress = compute_task_progress(tasks)
      finding_progress = compute_finding_progress(findings)
      budget_progress = compute_budget_progress(session)

      overall = compute_overall(task_progress, finding_progress)

      {:ok,
       %{
         session_id: session_id,
         overall_percent: overall,
         tasks: task_progress,
         findings: finding_progress,
         budget: budget_progress,
         remaining_items: remaining_items(task_progress, finding_progress),
         estimated_effort: estimate_effort(task_progress, finding_progress)
       }}
    end
  end

  defp load_tasks(session_id) do
    from(t in "tasks",
      where: t.session_id == ^session_id,
      select: %{
        id: t.id,
        title: t.title,
        status: t.status,
        position: t.position
      },
      order_by: [asc: :position]
    )
    |> Repo.all()
  end

  defp load_findings(session_id) do
    from(f in "findings",
      where: f.session_id == ^session_id,
      select: %{
        id: f.id,
        severity: f.severity,
        category: f.category,
        status: f.status
      }
    )
    |> Repo.all()
  end

  defp compute_task_progress(tasks) do
    total = length(tasks)

    done = Enum.count(tasks, fn t -> t.status in ["done", "verified"] end)
    verified = Enum.count(tasks, fn t -> t.status == "verified" end)
    in_progress = Enum.count(tasks, fn t -> t.status == "in_progress" end)
    blocked = Enum.count(tasks, fn t -> t.status == "blocked" end)
    paused = Enum.count(tasks, fn t -> t.status == "paused" end)
    queued = Enum.count(tasks, fn t -> t.status == "queued" end)

    percent =
      if total > 0 do
        Float.round((done + in_progress * 0.5) / total * 100, 1)
      else
        0.0
      end

    %{
      total: total,
      done: done,
      verified: verified,
      in_progress: in_progress,
      blocked: blocked,
      paused: paused,
      queued: queued,
      percent: percent,
      current_task: Enum.find(tasks, fn t -> t.status == "in_progress" end)
    }
  end

  defp compute_finding_progress(findings) do
    total = length(findings)

    resolved =
      Enum.count(findings, fn f -> f.status in ["approved", "rejected", "resolved"] end)

    open = Enum.count(findings, fn f -> f.status == "open" end)
    blocked = Enum.count(findings, fn f -> f.status == "blocked" end)
    escalated = Enum.count(findings, fn f -> f.status == "escalated" end)

    critical_open =
      Enum.count(findings, fn f ->
        f.severity == "critical" and f.status in ["open", "blocked", "escalated"]
      end)

    high_open =
      Enum.count(findings, fn f ->
        f.severity == "high" and f.status in ["open", "blocked", "escalated"]
      end)

    percent =
      if total > 0 do
        Float.round(resolved / total * 100, 1)
      else
        100.0
      end

    %{
      total: total,
      resolved: resolved,
      open: open,
      blocked: blocked,
      escalated: escalated,
      critical_open: critical_open,
      high_open: high_open,
      percent: percent,
      deployment_blockers: critical_open + blocked
    }
  end

  defp compute_budget_progress(session) do
    budget = session.budget_cents || 0
    spent = session.spent_cents || 0

    percent =
      if budget > 0 do
        Float.round(spent / budget * 100, 1)
      else
        0.0
      end

    remaining = max(budget - spent, 0)

    %{
      budget_cents: budget,
      spent_cents: spent,
      remaining_cents: remaining,
      percent: min(percent, 100.0),
      status:
        cond do
          percent >= 100 -> :exhausted
          percent >= 80 -> :warning
          percent >= 50 -> :moderate
          true -> :healthy
        end
    }
  end

  defp compute_overall(task_progress, finding_progress) do
    task_weight = 0.6
    finding_weight = 0.4

    task_pct = task_progress.percent
    finding_pct = finding_progress.percent

    Float.round(task_weight * task_pct + finding_weight * finding_pct, 1)
  end

  defp remaining_items(task_progress, finding_progress) do
    items = []

    items =
      if finding_progress.deployment_blockers > 0 do
        [
          %{
            type: :blocker,
            message:
              "#{finding_progress.deployment_blockers} critical finding(s) must be resolved before deploying"
          }
          | items
        ]
      else
        items
      end

    items =
      if task_progress.blocked > 0 do
        [
          %{
            type: :warning,
            message: "#{task_progress.blocked} task(s) are blocked by unresolved findings"
          }
          | items
        ]
      else
        items
      end

    items =
      if task_progress.queued > 0 do
        [%{type: :info, message: "#{task_progress.queued} task(s) waiting to be started"} | items]
      else
        items
      end

    items =
      if finding_progress.critical_open > 0 do
        [
          %{
            type: :blocker,
            message:
              "#{finding_progress.critical_open} critical security finding(s) need attention"
          }
          | items
        ]
      else
        items
      end

    Enum.reverse(items)
  end

  defp estimate_effort(task_progress, finding_progress) do
    remaining_tasks = task_progress.total - task_progress.done

    task_hours = remaining_tasks * 2

    finding_hours =
      finding_progress.critical_open * 1 + finding_progress.high_open * 0.5 +
        finding_progress.open * 0.25

    total_hours = task_hours + finding_hours

    %{
      estimated_hours: Float.round(total_hours, 1),
      estimated_days: Float.round(total_hours / 8, 1),
      remaining_tasks: remaining_tasks,
      unresolved_findings:
        finding_progress.open + finding_progress.blocked + finding_progress.escalated
    }
  end
end
