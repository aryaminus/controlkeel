defmodule ControlKeel.AnalyticsTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Analytics.Event
  alias ControlKeel.Mission.{Finding, Session}
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
end
