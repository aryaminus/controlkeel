defmodule ControlKeel.MissionTest do
  use ControlKeel.DataCase

  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.ProofBundle
  alias ControlKeel.Repo
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

  test "create_launch_from_brief/2 preserves the domain pack for every supported domain" do
    aliases = %{
      "software" => "Founder / Product Builder",
      "healthcare" => "Healthcare",
      "education" => "Education",
      "finance" => "Finance / Fintech",
      "hr" => "HR / Recruiting",
      "legal" => "Legal / Compliance",
      "marketing" => "Marketing / Content",
      "sales" => "Sales / CRM",
      "realestate" => "Real Estate",
      "government" => "Government / Public Sector",
      "insurance" => "Insurance / Claims",
      "ecommerce" => "E-commerce / Retail",
      "logistics" => "Logistics / Supply Chain",
      "manufacturing" => "Manufacturing / Quality",
      "nonprofit" => "Nonprofit / Grants"
    }

    Enum.each(ControlKeel.Intent.supported_packs(), fn pack ->
      brief =
        execution_brief_fixture(
          payload: %{
            "project_name" => "#{pack}-launchpad",
            "occupation" => Map.fetch!(aliases, pack),
            "domain_pack" => pack
          },
          compiler: %{
            "occupation" => pack,
            "domain_pack" => pack
          }
        )

      assert {:ok, session} =
               Mission.create_launch_from_brief(
                 %{
                   "agent" => "codex",
                   "project_root" =>
                     "/tmp/controlkeel-#{pack}-#{System.unique_integer([:positive])}"
                 },
                 brief
               )

      assert session.execution_brief["domain_pack"] == pack
      assert session.workspace.industry
    end)
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

  describe "complete_task/1" do
    test "marks task done and persists a proof bundle when no open or blocked findings exist" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      # ensure finding is resolved so it won't block
      _resolved = finding_fixture(%{session: session, status: "approved"})

      assert {:ok, done_task} = Mission.complete_task(task)
      assert done_task.status == "done"
      assert %ProofBundle{} = Mission.latest_proof_bundle_for_task(task.id)
    end

    test "returns error with findings list when open findings exist and marks task blocked" do
      session = session_fixture()
      task = task_fixture(%{session: session})
      _open = finding_fixture(%{session: session, status: "open"})

      assert {:error, :unresolved_findings, blocked} = Mission.complete_task(task)
      assert length(blocked) >= 1
      assert Mission.get_task!(task.id).status == "blocked"
    end

    test "returns error when blocked findings exist" do
      session = session_fixture()
      task = task_fixture(%{session: session})
      _blocked = finding_fixture(%{session: session, status: "blocked"})

      assert {:error, :unresolved_findings, _} = Mission.complete_task(task)
    end

    test "accepts integer task_id" do
      session = session_fixture()
      task = task_fixture(%{session: session})
      _open = finding_fixture(%{session: session, status: "open"})

      assert {:error, :unresolved_findings, _} =
               Mission.complete_task(task.id)
    end

    test "returns :not_found for unknown task_id" do
      assert {:error, :not_found} = Mission.complete_task(99_999_999)
    end
  end

  describe "proof_bundle/1" do
    test "returns and persists a structured bundle for a valid task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, bundle} = Mission.proof_bundle(task.id)
      assert bundle["task_id"] == task.id
      assert bundle["session_id"] == session.id
      assert is_map(bundle["security_findings"])
      assert is_number(bundle["security_findings"]["total"])
      assert is_boolean(bundle["deploy_ready"])
      assert is_list(bundle["compliance_attestations"])
      assert is_binary(bundle["generated_at"])
      assert is_binary(bundle["rollback_instructions"])
      assert Repo.aggregate(ProofBundle, :count, :id) == 1
    end

    test "deploy_ready is false when open findings exist" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})
      _open = finding_fixture(%{session: session, status: "open"})

      assert {:ok, bundle} = Mission.proof_bundle(task.id)
      assert bundle["deploy_ready"] == false
    end

    test "bundle includes test_outcomes, diff_summary, and invocation summary" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert %{"passed" => passed, "failed" => failed, "recorded" => recorded} =
               bundle["test_outcomes"]

      assert is_integer(passed)
      assert is_integer(failed)
      assert is_integer(recorded)

      assert %{
               "agent_runs" => _,
               "findings_total" => _,
               "auto_resolved" => _,
               "manual_review" => _
             } = bundle["diff_summary"]

      assert %{"total" => _, "cost_cents" => _} = bundle["invocation_summary"]
    end

    test "generating proof multiple times versions bundles" do
      task = task_fixture(%{status: "done"})

      assert {:ok, first} = Mission.generate_proof_bundle(task.id)
      assert {:ok, second} = Mission.generate_proof_bundle(task.id)

      assert first.version == 1
      assert second.version == 2
    end

    test "returns :not_found for unknown task_id" do
      assert {:error, :not_found} = Mission.proof_bundle(99_999_999)
    end
  end

  describe "pause_task/2 and resume_task/2" do
    test "captures checkpoints and deterministic resume packet" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      _finding =
        finding_fixture(%{session: session, status: "blocked", metadata: %{"task_id" => task.id}})

      assert {:ok, %{task: paused, checkpoint: checkpoint, resume_packet: packet}} =
               Mission.pause_task(task, "test")

      assert paused.status == "paused"
      assert checkpoint.checkpoint_type == "pause"
      assert packet["task_id"] == task.id
      assert is_list(packet["unresolved_findings"])
      assert is_list(packet["memory_hits"])

      assert {:ok, %{task: resumed, checkpoint: resumed_checkpoint}} =
               Mission.resume_task(paused, "test")

      assert resumed.status == "in_progress"
      assert resumed_checkpoint.checkpoint_type == "resume"
    end
  end

  test "mission lifecycle writes typed memory records" do
    session = session_fixture()
    task = task_fixture(%{session: session})
    finding = finding_fixture(%{session: session})
    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    result = Memory.search("Sample finding", session_id: session.id, top_k: 10)
    record_types = Enum.map(result.entries, & &1.record_type)

    assert "finding" in record_types
    assert Enum.any?(result.entries, &(&1.source_id == Integer.to_string(finding.id)))
  end

  describe "audit_log/1" do
    test "returns a structured audit log for a valid session" do
      session = session_fixture()
      _finding = finding_fixture(%{session: session})

      assert {:ok, log} = Mission.audit_log(session.id)
      assert log.session_id == session.id
      assert is_binary(log.session_title)
      assert is_list(log.events)
      assert is_list(log.tasks)
      assert is_map(log.summary)
      assert Map.has_key?(log.summary, :total_findings)
      assert Map.has_key?(log.summary, :total_invocations)
    end

    test "returns :not_found for unknown session_id" do
      assert {:error, :not_found} = Mission.audit_log(99_999_999)
    end
  end
end
