defmodule ControlKeel.Mission.ProgressTest do
  use ControlKeel.DataCase

  alias ControlKeel.Mission.Progress
  import ControlKeel.MissionFixtures

  test "compute returns error for missing session" do
    assert {:error, :session_not_found} = Progress.compute(999_999_999)
  end

  test "compute returns progress for session with tasks and findings" do
    session =
      session_fixture(%{
        budget_cents: 5_000,
        spent_cents: 1_500,
        daily_budget_cents: 2_000
      })

    task_fixture(%{session: session, status: "done", title: "Setup project"})
    task_fixture(%{session: session, status: "in_progress", title: "Build feature"})
    task_fixture(%{session: session, status: "queued", title: "Deploy"})

    finding_fixture(%{
      session: session,
      status: "approved",
      category: "security",
      severity: "high"
    })

    finding_fixture(%{
      session: session,
      status: "open",
      category: "security",
      severity: "critical"
    })

    assert {:ok, progress} = Progress.compute(session.id)

    assert progress.session_id == session.id
    assert is_float(progress.overall_percent)

    assert progress.tasks.total == 3
    assert progress.tasks.done == 1
    assert progress.tasks.in_progress == 1
    assert progress.tasks.queued == 1
    assert progress.tasks.percent > 0

    assert progress.findings.total == 2
    assert progress.findings.resolved == 1
    assert progress.findings.open == 1
    assert progress.findings.critical_open == 1
    assert progress.findings.deployment_blockers >= 1

    assert progress.budget.budget_cents == 5_000
    assert progress.budget.spent_cents == 1_500
    assert progress.budget.remaining_cents == 3_500
    assert progress.budget.status == :healthy

    assert is_list(progress.remaining_items)
    assert is_map(progress.estimated_effort)
    assert progress.estimated_effort.remaining_tasks == 2
  end

  test "compute with all tasks done gives 100% task progress" do
    session = session_fixture()

    task_fixture(%{session: session, status: "done"})
    task_fixture(%{session: session, status: "done"})

    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.tasks.percent == 100.0
  end

  test "compute with no tasks gives 0% task progress" do
    session = session_fixture()
    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.tasks.percent == 0.0
  end

  test "compute with no findings gives 100% finding progress" do
    session = session_fixture()
    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.findings.percent == 100.0
  end

  test "budget status is warning at 80%+" do
    session = session_fixture(%{budget_cents: 1_000, spent_cents: 850})

    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.budget.status == :warning
  end

  test "budget status is exhausted at 100%" do
    session = session_fixture(%{budget_cents: 1_000, spent_cents: 1_000})

    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.budget.status == :exhausted
  end

  test "remaining_items includes blockers for critical findings" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      status: "open",
      severity: "critical",
      category: "security"
    })

    finding_fixture(%{
      session: session,
      status: "blocked",
      severity: "high",
      category: "security"
    })

    {:ok, progress} = Progress.compute(session.id)

    blocker_items = Enum.filter(progress.remaining_items, &(&1.type == :blocker))
    assert length(blocker_items) >= 1
  end

  test "compute with zero budget" do
    session = session_fixture(%{budget_cents: 0, spent_cents: 0})

    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.budget.budget_cents == 0
    assert progress.budget.spent_cents == 0
    assert progress.budget.remaining_cents == 0
    assert progress.budget.percent == 0.0
    assert progress.budget.status == :healthy
  end

  test "compute with overspent budget clamps to 100%" do
    session = session_fixture(%{budget_cents: 1_000, spent_cents: 2_000})

    assert {:ok, progress} = Progress.compute(session.id)
    assert progress.budget.budget_cents == 1_000
    assert progress.budget.spent_cents == 2_000
    assert progress.budget.remaining_cents == 0
    assert progress.budget.percent == 100.0
    assert progress.budget.status == :exhausted
  end

  test "estimated_effort scales with remaining work" do
    session = session_fixture()

    for _ <- 1..5 do
      task_fixture(%{session: session, status: "queued"})
    end

    {:ok, progress} = Progress.compute(session.id)
    assert progress.estimated_effort.remaining_tasks == 5
    assert progress.estimated_effort.estimated_hours > 0
  end
end
