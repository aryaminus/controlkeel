defmodule ControlKeel.AutonomyLoopTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.AutonomyLoop

  test "derives explicit KPI-oriented long-running autonomy profiles" do
    session =
      session_fixture(%{
        objective: "Reduce critical backlog",
        metadata: %{
          "autonomy_mode" => "long_running_autonomy",
          "outcome_target" => "Cut critical vulnerabilities by 50%",
          "outcome_metric" => "critical findings resolved",
          "outcome_window" => "30 days"
        }
      })

    autonomy = AutonomyLoop.session_autonomy_profile(session)
    outcome = AutonomyLoop.session_outcome_profile(session)

    assert autonomy["mode"] == "long_running_autonomy"
    assert autonomy["long_running"] == true
    assert outcome["goal_type"] == "kpi"
    assert outcome["target"] == "Cut critical vulnerabilities by 50%"
    assert outcome["metric"] == "critical findings resolved"
    assert outcome["window"] == "30 days"
  end

  test "uses supervised execute for high-risk approval-heavy sessions" do
    session =
      session_fixture(%{
        risk_tier: "critical",
        execution_brief: %{
          "constraints" => ["Approval before production"],
          "domain_pack" => "software"
        }
      })

    autonomy = AutonomyLoop.session_autonomy_profile(session)

    assert autonomy["mode"] == "supervised_execute"
    assert autonomy["human_role"] == "approval_required"
  end

  test "summarizes workspace improvement mix across sessions" do
    explicit =
      session_fixture(%{
        metadata: %{
          "autonomy_mode" => "long_running_autonomy",
          "outcome_target" => "Reduce vuln backlog"
        }
      })

    implicit = session_fixture(%{status: "planned"})

    summary = AutonomyLoop.workspace_improvement_summary([explicit, implicit])

    assert summary["recent_session_count"] == 2
    assert summary["autonomy_mix"]["long_running_autonomy"] == 1
    assert summary["goal_type_mix"]["kpi"] == 1
    assert summary["explicit_outcome_sessions"] == 1
  end
end
