defmodule ControlKeel.AutonomyLoopTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
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

  test "session improvement loop surfaces the serial bottleneck before more delegation" do
    session = session_fixture(%{risk_tier: "critical"})
    _task = task_fixture(%{session: session, status: "in_progress"})
    _finding = finding_fixture(%{session: session, status: "blocked"})

    loop =
      session.id
      |> Mission.get_session_with_details!()
      |> AutonomyLoop.session_improvement_loop()

    assert get_in(loop, ["bottleneck_summary", "primary"]) == "unresolved_findings"
    assert get_in(loop, ["bottleneck_summary", "signals", "blocked_findings"]) == 1
    assert loop["recommended_next_step"] =~ "Resolve or disposition unresolved findings"

    findings = AutonomyLoop.bottleneck_findings(loop["bottleneck_summary"])

    assert Enum.any?(
             findings,
             &(&1["rule_id"] == "delivery.serial_bottleneck.unresolved_findings")
           )
  end

  test "session improvement loop surfaces ownership concentration" do
    session = session_fixture()

    Enum.each(1..3, fn index ->
      task_fixture(%{
        session: session,
        position: index,
        metadata: %{"owner" => "codex"}
      })
    end)

    loop =
      session.id
      |> Mission.get_session_with_details!()
      |> AutonomyLoop.session_improvement_loop()

    assert get_in(loop, ["ownership_summary", "risk"]) == "concentrated"
    assert get_in(loop, ["ownership_summary", "signals", "task_owner", "top"]) == "codex"

    findings = AutonomyLoop.ownership_findings(loop["ownership_summary"])
    assert Enum.any?(findings, &(&1["rule_id"] == "teams.ownership_concentration"))
    assert Enum.any?(findings, &(&1["rule_id"] == "teams.bus_factor.low"))
  end

  test "ownership findings include bus_factor.low for extreme concentration" do
    session = session_fixture()

    Enum.each(1..5, fn index ->
      task_fixture(%{
        session: session,
        position: index,
        metadata: %{"owner" => "codex"}
      })
    end)

    loop =
      session.id
      |> Mission.get_session_with_details!()
      |> AutonomyLoop.session_improvement_loop()

    findings = AutonomyLoop.ownership_findings(loop["ownership_summary"])

    assert Enum.any?(findings, &(&1["rule_id"] == "teams.ownership_concentration"))
    assert Enum.any?(findings, &(&1["rule_id"] == "teams.bus_factor.low"))

    bus_factor_finding = Enum.find(findings, &(&1["rule_id"] == "teams.bus_factor.low"))
    assert bus_factor_finding["severity"] == "high"
    assert bus_factor_finding["plain_message"] =~ "90%"
  end

  test "ownership findings include approval_concentration for review concentration" do
    summary = %{
      "risk" => "concentrated",
      "risks" => ["review_submitter:same-reviewer"],
      "recommendation" => "Diversify reviewers.",
      "signals" => %{
        "task_owner" => %{"total" => 4, "top" => "agent-a", "top_count" => 2, "top_share" => 0.5},
        "review_submitter" => %{
          "total" => 4,
          "top" => "same-reviewer",
          "top_count" => 4,
          "top_share" => 1.0
        },
        "finding_category" => %{
          "total" => 2,
          "top" => "security",
          "top_count" => 1,
          "top_share" => 0.5
        }
      }
    }

    findings = AutonomyLoop.ownership_findings(summary)

    assert Enum.any?(findings, &(&1["rule_id"] == "teams.ownership_concentration"))
    assert Enum.any?(findings, &(&1["rule_id"] == "teams.approval_concentration"))

    approval_finding = Enum.find(findings, &(&1["rule_id"] == "teams.approval_concentration"))
    assert approval_finding["severity"] == "medium"
    assert approval_finding["plain_message"] =~ "85%"
  end

  test "bottleneck findings include coordination_overhead when blocked findings accumulate" do
    session = session_fixture(%{risk_tier: "critical"})

    Enum.each(1..5, fn index ->
      finding_fixture(%{
        session: session,
        status: if(index <= 2, do: "blocked", else: "open"),
        rule_id: "test.finding.#{index}"
      })
    end)

    loop =
      session.id
      |> Mission.get_session_with_details!()
      |> AutonomyLoop.session_improvement_loop()

    findings = AutonomyLoop.bottleneck_findings(loop["bottleneck_summary"])

    assert Enum.any?(findings, &(&1["rule_id"] == "delegation.coordination_overhead"))

    coord_finding = Enum.find(findings, &(&1["rule_id"] == "delegation.coordination_overhead"))
    assert coord_finding["plain_message"] =~ "blocked findings"
  end
end
