defmodule ControlKeel.MissionTest do
  use ControlKeel.DataCase

  alias ControlKeel.Mission
  import ControlKeel.MissionFixtures
  import ControlKeel.IntentFixtures

  test "create_launch/1 creates a workspace, session, tasks, and findings" do
    params = %{
      "project_name" => "Clinic Intake",
      "industry" => "health",
      "agent" => "claude",
      "idea" => "Build a patient intake workflow for a small clinic",
      "users" => "front desk staff",
      "data" => "patient names, contact details, insurance notes",
      "features" => "intake form, admin review, export",
      "budget" => "$40/month"
    }

    assert {:ok, session} = Mission.create_launch(params)
    assert session.workspace.name == "Clinic Intake"
    assert session.risk_tier == "critical"
    assert length(session.tasks) >= 3
    assert length(session.findings) >= 2
    assert Enum.any?(session.findings, &(&1.rule_id == "privacy.phi.review"))
  end

  test "create_launch_from_brief/2 accepts a validated execution brief" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "School launchpad",
          "occupation" => "Education",
          "domain_pack" => "education",
          "risk_tier" => "moderate",
          "compliance" => ["FERPA", "COPPA", "WCAG 2.1 AA"],
          "recommended_stack" => "Phoenix + LiveView + accessibility checks",
          "data_summary" => "Student rosters and curriculum notes"
        },
        compiler: %{
          "provider" => "openai",
          "model" => "gpt-5.4",
          "occupation" => "education",
          "domain_pack" => "education"
        }
      )

    assert {:ok, session} =
             Mission.create_launch_from_brief(
               %{"agent" => "codex", "project_root" => "/tmp/controlkeel-school"},
               brief
             )

    assert session.workspace.name == "School launchpad"
    assert session.workspace.industry == "education"
    assert session.risk_tier == "moderate"
    assert session.execution_brief["compiler"]["provider"] == "openai"
    assert session.execution_brief["domain_pack"] == "education"
    assert length(session.tasks) >= 3
  end

  test "basic CRUD keeps session association valid" do
    workspace = workspace_fixture()

    assert {:ok, session} =
             Mission.create_session(%{
               title: "First session",
               objective: "Build a narrow first release",
               risk_tier: "moderate",
               status: "planned",
               budget_cents: 3_000,
               daily_budget_cents: 3_000,
               spent_cents: 0,
               execution_brief: %{"agent" => "Claude Code"},
               workspace_id: workspace.id
             })

    assert session.workspace_id == workspace.id
    assert {:ok, updated} = Mission.update_session(session, %{status: "in_progress"})
    assert updated.status == "in_progress"
    assert {:ok, %_{}} = Mission.delete_session(updated)
  end

  test "approve_finding/1 and reject_finding/2 update status and metadata" do
    finding = finding_fixture()

    assert {:ok, approved} = Mission.approve_finding(finding)
    assert approved.status == "approved"
    assert approved.metadata["approved_at"]

    assert {:ok, rejected} = Mission.reject_finding(approved, "False positive")
    assert rejected.status == "rejected"
    assert rejected.metadata["rejected_at"]
    assert rejected.metadata["rejection_reason"] == "False positive"
  end

  test "browse_findings/1 applies filters and paginates deterministically" do
    session_a = session_fixture(%{title: "Alpha mission"})
    session_b = session_fixture(%{title: "Bravo mission"})

    target =
      finding_fixture(%{
        session: session_a,
        title: "Alpha SQL finding",
        rule_id: "security.sql_injection",
        category: "security",
        severity: "high",
        status: "open",
        plain_message: "Alpha query issue"
      })

    _other =
      finding_fixture(%{
        session: session_b,
        title: "Bravo XSS finding",
        rule_id: "security.xss_unsafe_html",
        category: "security",
        severity: "medium",
        status: "rejected",
        plain_message: "Bravo browser issue"
      })

    Enum.each(1..21, fn index ->
      finding_fixture(%{
        session: session_a,
        title: "Paged finding #{index}",
        rule_id: "security.sample.#{index}",
        severity: "low",
        category: "ops",
        status: "open"
      })
    end)

    filtered =
      Mission.browse_findings(%{
        "q" => "Alpha",
        "severity" => "high",
        "status" => "open",
        "category" => "security",
        "session_id" => Integer.to_string(session_a.id)
      })

    assert Enum.map(filtered.entries, & &1.id) == [target.id]
    assert hd(filtered.entries).session.title == "Alpha mission"
    assert hd(filtered.entries).session.workspace

    first_page = Mission.browse_findings(%{"page" => "1"})
    second_page = Mission.browse_findings(%{"page" => "2"})

    assert first_page.total_pages == 2
    assert length(first_page.entries) == 20
    assert length(second_page.entries) == 3
  end

  test "task and finding fixtures build through the real associations" do
    task = task_fixture()
    finding = finding_fixture()

    assert task.session_id
    assert finding.session_id
  end
end
