defmodule ControlKeel.AnalyticsTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Analytics.Event
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, ProofBundle, Session}
  alias ControlKeel.Repo

  test "record/1 persists analytics events" do
    session = session_fixture()

    assert {:ok, %Event{} = event} =
             Analytics.record(%{
               event: "project_initialized",
               source: "test",
               session_id: session.id,
               workspace_id: session.workspace_id,
               project_root: "/tmp/controlkeel",
               metadata: %{"agent" => "claude"}
             })

    assert event.event == "project_initialized"
    assert event.project_root == "/tmp/controlkeel"
    assert event.metadata["agent"] == "claude"
  end

  test "session_metrics derives counts and falls back to session start time" do
    session = session_fixture()

    session_start = ~U[2026-03-18 10:00:00Z]
    first_finding_at = ~U[2026-03-18 10:12:00Z]

    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [inserted_at: session_start]
    )

    blocked =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "Blocked runtime finding"
      })

    _approved =
      finding_fixture(%{session: session, status: "approved", title: "Approved finding"})

    _rejected =
      finding_fixture(%{session: session, status: "rejected", title: "Rejected finding"})

    Repo.update_all(
      from(f in Finding, where: f.id == ^blocked.id),
      set: [inserted_at: first_finding_at]
    )

    metrics = Analytics.session_metrics(session.id)

    assert metrics.funnel_stage == "first_finding_recorded"
    assert metrics.time_to_first_finding_seconds == 720
    assert metrics.total_findings == 3
    assert metrics.blocked_findings_total == 1
    assert metrics.approved_findings_total == 1
    assert metrics.rejected_findings_total == 1
  end

  test "funnel_summary returns cumulative funnel counts and conversion" do
    session_a = session_fixture(%{title: "Project only"})
    session_b = session_fixture(%{title: "Attached"})
    session_c = session_fixture(%{title: "Finding"})

    assert {:ok, _} =
             Analytics.record(%{
               event: "project_initialized",
               source: "test",
               session_id: session_a.id,
               workspace_id: session_a.workspace_id
             })

    for event <- ~w(project_initialized agent_attached mission_created) do
      assert {:ok, _} =
               Analytics.record(%{
                 event: event,
                 source: "test",
                 session_id: session_b.id,
                 workspace_id: session_b.workspace_id
               })
    end

    for event <- ~w(project_initialized agent_attached mission_created first_finding_recorded) do
      assert {:ok, _} =
               Analytics.record(%{
                 event: event,
                 source: "test",
                 session_id: session_c.id,
                 workspace_id: session_c.workspace_id
               })
    end

    summary = Analytics.funnel_summary(limit: 10)

    assert Enum.map(summary.steps, & &1.count) == [3, 2, 2, 1]
    assert Enum.map(summary.steps, & &1.conversion_percent) == [100.0, 66.7, 100.0, 50.0]
  end

  test "funnel_summary returns proof and outcome metrics backed by persisted mission data" do
    session_a =
      session_fixture(%{
        title: "Claude ship session",
        execution_brief: %{"agent" => "Claude Code"}
      })

    session_b =
      session_fixture(%{
        title: "Codex ship session",
        execution_brief: %{"agent" => "Codex CLI"}
      })

    Repo.update_all(from(s in Session, where: s.id == ^session_a.id),
      set: [inserted_at: ~U[2026-03-18 10:00:00Z]]
    )

    done_ready =
      task_fixture(%{
        session: session_a,
        position: 1,
        status: "done",
        title: "Ready task"
      })

    _done_without_proof =
      task_fixture(%{
        session: session_a,
        position: 2,
        status: "done",
        title: "No proof task"
      })

    queued_resume =
      task_fixture(%{
        session: session_a,
        position: 3,
        status: "queued",
        title: "Queued resume task"
      })

    done_not_ready =
      task_fixture(%{
        session: session_b,
        position: 1,
        status: "done",
        title: "Blocked proof task"
      })

    _queued_codex =
      task_fixture(%{
        session: session_b,
        position: 2,
        status: "queued",
        title: "Queued codex task"
      })

    blocked_finding =
      finding_fixture(%{
        session: session_b,
        severity: "high",
        status: "blocked",
        title: "Blocked high finding"
      })

    _approved_risky =
      finding_fixture(%{
        session: session_a,
        severity: "high",
        status: "approved",
        title: "Approved high finding"
      })

    _escalated_finding =
      finding_fixture(%{
        session: session_b,
        severity: "critical",
        status: "escalated",
        title: "Escalated critical finding"
      })

    assert {:ok, ready_plan_review} =
             Mission.submit_review(%{
               "task_id" => done_ready.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "research_summary" => "Reviewed the analytics funnel and proof generation path.",
               "codebase_findings" => ["Deploy readiness is derived from proof bundles."],
               "alignment_context" => [
                 "PM wants deploy-ready analytics to reflect only reviewed execution-ready work."
               ],
               "options_considered" => [
                 "Use proof bundle state",
                 "Track a separate analytics flag"
               ],
               "selected_option" => "Use proof bundle state",
               "rejected_options" => ["Track a separate analytics flag"],
               "implementation_steps" => ["Generate proof bundle", "Aggregate deploy-ready tasks"],
               "validation_plan" => ["mix test", "mix precommit"],
               "submission_body" => "Implementation-ready analytics plan"
             })

    assert {:ok, _approved_ready_plan} =
             Mission.respond_review(ready_plan_review, %{
               "decision" => "approved",
               "feedback_notes" => "Approved plan"
             })

    {:ok, ready_proof} = Mission.generate_proof_bundle(done_ready.id)

    Repo.update_all(
      from(p in ProofBundle, where: p.id == ^ready_proof.id),
      set: [generated_at: ~U[2026-03-18 10:20:00Z]]
    )

    {:ok, _not_ready_proof} = Mission.generate_proof_bundle(done_not_ready.id)

    assert {:ok, _} =
             Mission.create_invocation(%{
               source: "test",
               tool: "ck_route",
               provider: "anthropic",
               model: "claude-3-7-sonnet",
               estimated_cost_cents: 120,
               decision: "allow",
               metadata: %{},
               session_id: session_a.id,
               task_id: done_ready.id
             })

    assert {:ok, _} =
             Mission.create_task_checkpoint(%{
               session_id: session_a.id,
               task_id: done_ready.id,
               checkpoint_type: "resume",
               summary: "Resumed ready task",
               payload: %{},
               created_by: "test"
             })

    assert {:ok, _} =
             Mission.create_task_checkpoint(%{
               session_id: session_a.id,
               task_id: queued_resume.id,
               checkpoint_type: "resume",
               summary: "Resumed queued task",
               payload: %{},
               created_by: "test"
             })

    summary = Analytics.funnel_summary(limit: 10)

    assert summary.outcome_metrics.proof_backed_task_coverage_percent == 66.7
    assert summary.outcome_metrics.deploy_ready_task_rate_percent == 50.0
    assert summary.outcome_metrics.cost_per_deploy_ready_task_cents == 120.0
    assert summary.outcome_metrics.resume_success_rate_percent == 50.0
    assert summary.outcome_metrics.risky_intervention_rate_percent == 66.7
    assert summary.outcome_metrics.average_time_to_first_deploy_ready_proof_seconds == 1_200.0

    assert Enum.any?(summary.agent_outcomes, fn row ->
             row.agent == "Claude Code" and row.completed_tasks == 2 and
               row.total_tasks == 3 and row.deploy_ready_tasks == 1 and
               row.completion_rate_percent == 66.7
           end)

    assert Enum.any?(summary.agent_outcomes, fn row ->
             row.agent == "Codex CLI" and row.completed_tasks == 1 and
               row.total_tasks == 2 and row.deploy_ready_tasks == 0 and
               row.completion_rate_percent == 50.0
           end)

    assert blocked_finding.status == "blocked"
  end

  test "funnel_summary/1 with :org_id scopes counts to that org" do
    import ControlKeel.AccountsFixtures, only: [org_fixture: 1]

    org = org_fixture(%{name: "Scoped Org"})
    other_org = org_fixture(%{name: "Other Org"})

    ws = workspace_fixture(%{org_id: org.id, name: "Scoped Workspace"})
    other_ws = workspace_fixture(%{org_id: other_org.id, name: "Other Workspace"})

    session_fixture(%{workspace: ws, title: "Scoped A"})
    session_fixture(%{workspace: ws, title: "Scoped B"})
    # A session under the other org and an org-less (solo) workspace session
    # must both stay out of the scoped counts.
    session_fixture(%{workspace: other_ws, title: "Foreign"})
    session_fixture(%{title: "Solo"})

    summary = Analytics.funnel_summary(org_id: org.id)

    assert summary.recent_session_count == 2
    assert summary.outcome_metrics.proof_backed_task_coverage_percent == nil
    assert summary.outcome_metrics.deploy_ready_task_rate_percent == nil
  end

  test "funnel_summary/1 with :org_id on an empty org returns no-data defaults" do
    import ControlKeel.AccountsFixtures, only: [org_fixture: 1]

    org = org_fixture(%{name: "Empty Org"})

    summary = Analytics.funnel_summary(org_id: org.id)

    assert summary.recent_session_count == 0

    assert summary.outcome_metrics.proof_backed_task_coverage_percent == nil
    assert summary.outcome_metrics.deploy_ready_task_rate_percent == nil
    assert summary.average_findings_per_session == nil
    assert summary.steps == [
             %{step: "project_initialized", count: 0, conversion_percent: 100.0},
             %{step: "agent_attached", count: 0, conversion_percent: nil},
             %{step: "mission_created", count: 0, conversion_percent: nil},
             %{step: "first_finding_recorded", count: 0, conversion_percent: nil}
           ]
  end
end
