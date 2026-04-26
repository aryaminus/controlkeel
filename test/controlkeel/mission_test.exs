defmodule ControlKeel.MissionTest do
  use ControlKeel.DataCase

  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{ProofBundle, Review}
  alias ControlKeel.Platform
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
      "nonprofit" => "Nonprofit / Grants",
      "security" => "Security / Defensive AppSec"
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

  test "create_launch_from_brief/2 builds the security mission template and cyber access mode" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "Kernel triage loop",
          "occupation" => "Security Researcher",
          "domain_pack" => "security",
          "risk_tier" => "critical",
          "compliance" => [
            "Coordinated disclosure",
            "Authorized target scope",
            "Patch validation evidence"
          ],
          "recommended_stack" => "Repo-local triage + isolated runtime exports",
          "data_summary" => "Kernel source, repro artifacts, and disclosure drafts",
          "key_features" => [
            "Discovery",
            "Triage",
            "Reproduction",
            "Patch validation",
            "Disclosure packet"
          ]
        },
        compiler: %{
          "occupation" => "security_researcher",
          "domain_pack" => "security"
        }
      )

    assert {:ok, session} =
             Mission.create_launch_from_brief(
               %{"agent" => "codex", "project_root" => "/tmp/controlkeel-security"},
               brief
             )

    assert session.workspace.industry == "security"
    assert session.execution_brief["domain_pack"] == "security"
    assert session.metadata["mission_template"] == "security_defender_v1"
    assert session.metadata["cyber_access_mode"] == "verified_research"

    assert Enum.map(session.tasks, & &1.metadata["security_workflow_phase"]) == [
             "discovery",
             "triage",
             "reproduction",
             "patch",
             "validation",
             "disclosure"
           ]

    assert Enum.any?(session.findings, fn finding ->
             finding.rule_id == "security.workflow.scope_authorization" and
               finding.metadata["finding_family"] == "vulnerability_case"
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

  test "browse_findings/1 filters vulnerability lifecycle metadata and summarizes filtered cases" do
    session = session_fixture(%{title: "Security triage"})

    matched =
      finding_fixture(%{
        session: session,
        title: "Patch pending SQL injection",
        category: "security",
        severity: "high",
        status: "open",
        metadata: %{
          "finding_family" => "vulnerability_case",
          "affected_component" => "accounts",
          "evidence_type" => "source",
          "exploitability_status" => "reproduced",
          "patch_status" => "drafted",
          "disclosure_status" => "triaged",
          "maintainer_scope" => "first_party",
          "cwe_ids" => ["CWE-89"]
        }
      })

    _non_match =
      finding_fixture(%{
        session: session,
        title: "Validated XSS fix",
        category: "security",
        severity: "medium",
        status: "open",
        metadata: %{
          "finding_family" => "vulnerability_case",
          "affected_component" => "admin",
          "evidence_type" => "diff",
          "exploitability_status" => "validated",
          "patch_status" => "validated",
          "disclosure_status" => "patched",
          "maintainer_scope" => "open_source",
          "cwe_ids" => ["CWE-79"]
        }
      })

    browser =
      Mission.browse_findings(%{
        "session_id" => Integer.to_string(session.id),
        "finding_family" => "vulnerability_case",
        "patch_status" => "drafted",
        "disclosure_status" => "triaged",
        "maintainer_scope" => "first_party"
      })

    assert Enum.map(browser.entries, & &1.id) == [matched.id]
    assert browser.security_summary["case_count"] == 1
    assert browser.security_summary["unresolved"] == 1
    assert browser.security_summary["patch_status"] == %{"drafted" => 1}
    assert browser.security_summary["disclosure_status"] == %{"triaged" => 1}
    assert browser.security_summary["maintainer_scope"] == %{"first_party" => 1}
    assert browser.filters.finding_family == "vulnerability_case"
  end

  test "task and finding fixtures build through the real associations" do
    task = task_fixture()
    finding = finding_fixture()

    assert task.session_id
    assert finding.session_id
  end

  test "submit_review/1 supersedes prior plan reviews and unlocks execution on approval" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    assert {:ok, first_review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "submission_body" => "Plan v1",
               "submitted_by" => "codex",
               "plan_phase" => "implementation_plan",
               "research_summary" => "Mapped the first implementation pass.",
               "codebase_findings" => ["Task execution already uses review_gate metadata."],
               "alignment_context" => [
                 "PM confirmed execution can stay within the existing review flow."
               ],
               "options_considered" => ["Extend reviews", "Add planner service"],
               "selected_option" => "Extend reviews",
               "rejected_options" => ["Add planner service"],
               "implementation_steps" => ["Normalize plan metadata", "Gate execution on it"],
               "validation_plan" => ["mix test"]
             })

    assert first_review.status == "pending"
    assert Mission.execution_ready?(Mission.get_task!(task.id)) == false

    assert {:ok, second_review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "submission_body" => "Plan v2",
               "submitted_by" => "codex",
               "plan_phase" => "implementation_plan",
               "research_summary" => "Refined the execution-ready plan after review.",
               "codebase_findings" => ["Proof bundle already loads plan reviews."],
               "alignment_context" => [
                 "PM confirmed execution can stay within the existing review flow."
               ],
               "options_considered" => ["Extend reviews", "Add planner service"],
               "selected_option" => "Extend reviews",
               "rejected_options" => ["Add planner service"],
               "implementation_steps" => ["Normalize plan metadata", "Gate execution on it"],
               "validation_plan" => ["mix test"]
             })

    assert second_review.previous_review_id == first_review.id
    assert Mission.get_review!(first_review.id).status == "superseded"
    assert Mission.review_gate_status(Mission.get_task!(task.id))["phase"] == "review"

    assert {:ok, approved_review} =
             Mission.respond_review(second_review, %{
               "decision" => "approved",
               "feedback_notes" => "Looks good"
             })

    assert approved_review.status == "approved"

    gate = Mission.review_gate_status(Mission.get_task!(task.id))
    assert gate["phase"] == "execution"
    assert gate["execution_ready"] == true

    review_memory = Memory.search("Plan v2", session_id: session.id, top_k: 10)
    assert Enum.any?(review_memory.entries, &(&1.record_type == "review"))
  end

  test "approved non-execution-ready plan phases keep the task in planning" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "research_packet",
               "research_summary" => "Mapped the parser and router entrypoints.",
               "codebase_findings" => ["Router currently owns dispatch and auth checks."],
               "submission_body" => "Research packet for recursive planning"
             })

    assert {:ok, _approved} =
             Mission.respond_review(review, %{
               "decision" => "approved",
               "feedback_notes" => "Research looks correct"
             })

    gate = Mission.review_gate_status(Mission.get_task!(task.id))
    assert gate["phase"] == "planning"
    assert gate["execution_ready"] == false
    assert gate["latest_plan_phase"] == "research_packet"
    assert gate["planning_depth"] == 1
    assert is_list(gate["grill_questions"])
    assert is_list(gate["decision_prompts"])
    assert Enum.any?(gate["grill_questions"], &String.contains?(&1, "files, modules, or flows"))
  end

  test "review gate includes decision hygiene prompts for large risky plans" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    assert {:ok, _review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Large implementation plan",
               "research_summary" => "Mapped the relevant modules.",
               "options_considered" => ["Patch in place", "Extract helper"],
               "selected_option" => "Patch in place",
               "alignment_context" => [],
               "consulted_roles" => [],
               "implementation_steps" => ["Patch", "Test"],
               "scope_estimate" => %{
                 "files_touched_estimate" => 7,
                 "diff_size_estimate" => 400,
                 "architectural_scope" => true
               }
             })

    prompts = Mission.review_gate_status(Mission.get_task!(task.id))["decision_prompts"]

    assert Enum.any?(prompts, &String.starts_with?(&1, "Inversion:"))
    assert Enum.any?(prompts, &String.starts_with?(&1, "Evidence check:"))
    assert Enum.any?(prompts, &String.starts_with?(&1, "Alignment check:"))
  end

  test "session-scoped plan reviews without task_id key supersede previous pending review" do
    session = session_fixture()

    assert {:ok, first_review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "review_type" => "plan",
               "submission_body" => "Session-level plan v1"
             })

    assert first_review.task_id == nil
    assert first_review.status == "pending"

    assert {:ok, second_review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "review_type" => "plan",
               "submission_body" => "Session-level plan v2"
             })

    assert second_review.task_id == nil
    assert second_review.previous_review_id == first_review.id
    assert Mission.get_review!(first_review.id).status == "superseded"
  end

  test "approved implementation plans unlock execution only when the refinement packet is strong enough" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "research_summary" => "Reviewed mission, MCP tools, and proof generation seams.",
               "codebase_findings" => ["Plan reviews already gate execution in Mission."],
               "alignment_context" => [
                 "PM wants this to remain inside the existing review flow rather than a new surface."
               ],
               "consulted_roles" => ["PM", "Security"],
               "options_considered" => [
                 "New planner subsystem",
                 "Extend existing review metadata"
               ],
               "selected_option" => "Extend existing review metadata",
               "rejected_options" => ["New planner subsystem"],
               "implementation_steps" => [
                 "Add plan refinement metadata to plan reviews",
                 "Gate execution on approved implementation-ready plans"
               ],
               "validation_plan" => [
                 "mix test test/controlkeel/mission_test.exs",
                 "mix precommit"
               ],
               "scope_estimate" => %{
                 "files_touched_estimate" => 6,
                 "diff_size_estimate" => 180,
                 "architectural_scope" => true
               },
               "submission_body" => "Implementation-ready recursive plan"
             })

    assert {:ok, _approved} =
             Mission.respond_review(review, %{
               "decision" => "approved",
               "feedback_notes" => "Execution-ready"
             })

    gate = Mission.review_gate_status(Mission.get_task!(task.id))
    assert gate["phase"] == "execution"
    assert gate["execution_ready"] == true
    assert gate["latest_plan_phase"] == "implementation_plan"
    assert gate["plan_quality_status"] in ["moderate", "strong"]
    assert gate["plan_quality_score"] >= 70
    assert is_list(gate["grill_questions"])
  end

  test "reviews are included in the audit log and proof bundle summary" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "submission_body" => "Plan with review trail"
             })

    assert {:ok, %Review{} = _approved} =
             Mission.respond_review(review, %{
               "decision" => "approved",
               "feedback_notes" => "Proceed"
             })

    assert {:ok, proof} = Mission.generate_proof_bundle(task.id)
    assert {:ok, audit_log} = Mission.audit_log(session.id)

    assert Enum.any?(audit_log.events, &(&1.type == "review_submitted"))
    assert Enum.any?(audit_log.events, &(&1.type == "review_responded"))
    assert proof.bundle["review_summary"]["approved"] == 1
    assert proof.bundle["review_summary"]["latest_review_status"] == "approved"
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

    test "marks task verified when completion has sufficient governed evidence" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      assert {:ok, _run} = Platform.claim_task(task.id)

      assert {:ok, _checks} =
               Platform.record_task_checks(task.id, nil, [
                 %{
                   check_type: "tests",
                   status: "passed",
                   summary: "All green",
                   payload: %{"source" => "fixture"}
                 }
               ])

      assert {:ok, verified_task} = Mission.complete_task(task)
      assert verified_task.status == "verified"

      assert Mission.proof_summary_for_task(task.id)["verification_status"] in [
               "moderate",
               "strong"
             ]
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

    test "deploy_ready is false for unresolved non-critical vulnerability cases" do
      session =
        session_fixture(%{
          execution_brief: %{
            "domain_pack" => "security",
            "occupation" => "Open Source Maintainer"
          },
          metadata: %{}
        })

      task =
        task_fixture(%{
          session: session,
          status: "done",
          metadata: %{"track" => "release", "security_workflow_phase" => "disclosure"}
        })

      _open =
        finding_fixture(%{
          session: session,
          severity: "high",
          category: "security",
          status: "open",
          metadata: %{
            "finding_family" => "vulnerability_case",
            "affected_component" => "ffmpeg/parser",
            "evidence_type" => "source",
            "exploitability_status" => "validated",
            "patch_status" => "drafted",
            "disclosure_status" => "triaged",
            "maintainer_scope" => "open_source",
            "cwe_ids" => ["CWE-787"]
          }
        })

      assert {:ok, bundle} = Mission.proof_bundle(task.id)
      assert bundle["deploy_ready"] == false
      assert bundle["security_workflow"]["vulnerability_summary"]["unresolved"] == 1
    end

    test "security workflow falls back from label occupation names when metadata is absent" do
      session =
        session_fixture(%{
          execution_brief: %{"domain_pack" => "security", "occupation" => "Security Researcher"},
          metadata: %{}
        })

      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, bundle} = Mission.proof_bundle(task.id)
      assert bundle["security_workflow"]["cyber_access_mode"] == "verified_research"
    end

    test "deploy_ready is false when there is no approved execution-ready plan" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert bundle["deploy_ready"] == false
      assert bundle["planning_continuity"]["status"] == "missing"

      assert Enum.any?(
               bundle["planning_continuity"]["drift_signals"],
               &(&1["code"] == "no_approved_plan")
             )
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
               "manual_review" => _,
               "suspicious_test_changes" => suspicious_test_changes
             } = bundle["diff_summary"]

      assert is_integer(suspicious_test_changes)
      assert %{"total" => _, "cost_cents" => _} = bundle["invocation_summary"]
      assert %{"status" => _, "score" => _, "signals" => _} = bundle["verification_assessment"]
    end

    test "bundle and summaries include task-check evidence and runtime integrity signals" do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:ok, _run} = Platform.claim_task(task.id)

      assert {:ok, _checks} =
               Platform.record_task_checks(task.id, nil, [
                 %{
                   check_type: "validation",
                   status: "passed",
                   summary: "Validation passed",
                   payload: %{"source" => "fixture"}
                 },
                 %{
                   check_type: "verification",
                   status: "warn",
                   summary: "Verification was partial",
                   payload: %{"source" => "fixture"}
                 }
               ])

      assert {:ok, _updated} =
               Mission.attach_task_runtime_context(task.id, %{
                 "partial_reads" => [%{"path" => "lib/big_file.ex", "truncated_at_line" => 2000}],
                 "compaction_events" => [%{"reason" => "token_budget"}]
               })

      assert {:ok, done_task} = Mission.update_task(Mission.get_task!(task.id), %{status: "done"})
      assert {:ok, bundle} = Mission.proof_bundle(done_task.id)

      assert bundle["task_checks"]["passed"] == 1
      assert bundle["task_checks"]["warn"] == 1
      assert bundle["task_checks"]["failed"] == 0
      assert "validation" in bundle["task_checks"]["evidence_sources"]

      assert bundle["runtime_context_integrity"]["status"] == "degraded"
      assert bundle["runtime_context_integrity"]["partial_read_count"] == 1
      assert bundle["runtime_context_integrity"]["compaction_count"] == 1
      assert bundle["runtime_context_integrity"]["latest_partial_read_path"] == "lib/big_file.ex"
      assert bundle["runtime_context_integrity"]["latest_compaction_reason"] == "token_budget"

      assert Mission.proof_summary_for_task(done_task.id)["task_checks"]["passed"] == 1

      assert Mission.proof_summary_for_task(done_task.id)["context_integrity"]["status"] ==
               "degraded"

      assurance = Mission.task_assurance_summary(done_task.id)
      assert assurance["check_summary"]["passed"] == 1
      assert assurance["context_integrity"]["status"] == "degraded"
      assert "task_checks" in assurance["verification"]["evidence_sources"]
    end

    test "external regression failures are reflected in proof bundles and disable deploy_ready" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, _result} =
               Mission.record_regression_result(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "engine" => "passmark",
                 "flow_name" => "checkout happy path",
                 "outcome" => "failed",
                 "summary" => "Checkout button no longer completes purchase",
                 "evidence" => %{"video_url" => "https://example.test/run.mp4"}
               })

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert bundle["deploy_ready"] == false
      assert bundle["test_outcomes"]["failed"] == 1
      assert bundle["test_outcomes"]["external_recorded"] == 1
      assert bundle["test_outcomes"]["blocking_failures"] == 1
      assert bundle["test_outcomes"]["engines"]["passmark"] == 1

      assert [
               %{
                 "flow_name" => "checkout happy path",
                 "engine" => "passmark",
                 "outcome" => "failed"
               }
               | _
             ] = bundle["test_outcomes"]["latest_failures"]
    end

    test "verification assessment becomes strong with mixed evidence" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, _} =
               Mission.create_invocation(%{
                 source: "test",
                 tool: "mix_test",
                 provider: nil,
                 model: nil,
                 estimated_cost_cents: 0,
                 decision: "allow",
                 metadata: %{"outcome" => "passed"},
                 session_id: session.id,
                 task_id: task.id
               })

      assert {:ok, _} =
               Mission.record_regression_result(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "engine" => "passmark",
                 "flow_name" => "checkout happy path",
                 "outcome" => "passed",
                 "summary" => "Checkout flow completed successfully"
               })

      assert {:ok, review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "diff",
                 "title" => "Diff review",
                 "submission_body" => "diff --git a/lib/demo.ex b/lib/demo.ex\n+ok = true\n",
                 "submitted_by" => "codex"
               })

      assert {:ok, _approved} =
               Mission.respond_review(review, %{
                 "decision" => "approved",
                 "feedback_notes" => "Verification evidence looks good"
               })

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert bundle["verification_assessment"]["status"] == "strong"
      assert bundle["verification_assessment"]["score"] >= 70

      assert "external_regression" in bundle["verification_assessment"]["evidence"][
               "evidence_sources"
             ]

      assert "human_review" in bundle["verification_assessment"]["evidence"]["evidence_sources"]

      assert "internal_checks" in bundle["verification_assessment"]["evidence"][
               "evidence_sources"
             ]
    end

    test "suspicious test diff signals weaken verification and disable deploy_ready" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "diff",
                 "title" => "Test weakening diff",
                 "submission_body" => """
                 diff --git a/test/demo_test.exs b/test/demo_test.exs
                 --- a/test/demo_test.exs
                 +++ b/test/demo_test.exs
                 -    assert result == :ok
                 +    @tag :skip
                 +    assert true
                 """,
                 "submitted_by" => "codex"
               })

      assert review.review_type == "diff"

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert bundle["deploy_ready"] == false
      assert bundle["diff_summary"]["suspicious_test_changes"] >= 2
      assert bundle["decomposition"]["session"]["strategy"] == "bounded_recursive_delivery_v1"
      assert bundle["decomposition"]["task"]["node_type"] in ["synthesize", "implement"]

      assert Enum.any?(
               bundle["verification_assessment"]["suspicious_test_changes"],
               &(&1["code"] == "test_skip_added")
             )

      assert Enum.any?(
               bundle["verification_assessment"]["suspicious_test_changes"],
               &(&1["code"] == "assertion_removed")
             )

      assert bundle["verification_assessment"]["verification_ready"] == false
    end

    test "planning continuity is aligned when execution reviews stay linked to an approved implementation plan" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:ok, plan_review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Reviewed the mission control and MCP review flow.",
                 "codebase_findings" => ["Mission already stores review metadata."],
                 "alignment_context" => [
                   "PM wants execution review to stay linked to an approved plan."
                 ],
                 "options_considered" => ["Extend reviews", "Add new tables"],
                 "selected_option" => "Extend reviews",
                 "rejected_options" => ["Add new tables"],
                 "implementation_steps" => ["Store plan metadata", "Check it in proof bundles"],
                 "validation_plan" => ["mix test", "mix precommit"],
                 "submission_body" => "Implementation-ready plan"
               })

      assert {:ok, _approved} =
               Mission.respond_review(plan_review, %{
                 "decision" => "approved",
                 "feedback_notes" => "Approved plan"
               })

      assert {:ok, _diff_review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "diff",
                 "previous_review_id" => plan_review.id,
                 "submission_body" =>
                   "diff --git a/lib/controlkeel/mission.ex b/lib/controlkeel/mission.ex\n+planning = true\n",
                 "submitted_by" => "codex"
               })

      assert {:ok, bundle} = Mission.proof_bundle(task.id)

      assert bundle["planning_continuity"]["status"] == "aligned"
      assert bundle["planning_continuity"]["approved_plan_phase"] == "implementation_plan"
      assert bundle["planning_continuity"]["execution_review_linked"] == true
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
      assert is_map(packet["workspace_context"])
      assert is_binary(packet["workspace_cache_key"])
      assert is_list(packet["recent_events"])
      assert is_map(packet["transcript_summary"])
      assert packet["decomposition"]["session"]["strategy"] == "bounded_recursive_delivery_v1"
      assert is_map(packet["decomposition"]["task"])

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

  test "transcript summary and recent events reflect session lifecycle" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "in_progress"})

    assert {:ok, _paused} = Mission.pause_task(task, "test")

    recent_events = Mission.list_session_events(session.id)
    summary = Mission.transcript_summary(session.id)

    assert Enum.any?(recent_events, &(&1["event_type"] == "task.paused"))
    assert Enum.any?(recent_events, &(&1["event_type"] == "checkpoint.pause"))
    assert summary["total_events"] >= 3
    assert Enum.any?(summary["families"], &(&1["family"] == "task"))
    assert Enum.any?(summary["families"], &(&1["family"] == "checkpoint"))
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

  describe "decision_hygiene_findings/2" do
    test "produces sunk_cost_signal when plan refinement depth >= 3" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "queued"})

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Done",
                 "codebase_findings" => ["Checked"],
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "rejected_options" => ["B"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "validation_plan" => ["mix test"],
                 "scope_estimate" => %{"files_touched_estimate" => 2, "diff_size_estimate" => 100},
                 "submission_body" => "Plan v1"
               })

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Updated",
                 "codebase_findings" => ["More"],
                 "options_considered" => ["A", "C"],
                 "selected_option" => "A",
                 "rejected_options" => ["C"],
                 "implementation_steps" => ["Step 1", "Step 2", "Step 3"],
                 "validation_plan" => ["mix test"],
                 "scope_estimate" => %{"files_touched_estimate" => 2, "diff_size_estimate" => 100},
                 "submission_body" => "Plan v2"
               })

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Final",
                 "codebase_findings" => ["Done"],
                 "options_considered" => ["A", "D"],
                 "selected_option" => "A",
                 "rejected_options" => ["D"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "validation_plan" => ["mix test"],
                 "scope_estimate" => %{"files_touched_estimate" => 2, "diff_size_estimate" => 100},
                 "submission_body" => "Plan v3"
               })

      task = Mission.get_task!(task.id)
      findings = Mission.decision_hygiene_findings(task)

      assert Enum.any?(findings, &(&1["rule_id"] == "planning.sunk_cost_signal"))
      assert Enum.any?(findings, &(&1["plain_message"] =~ "refined 3 times"))
    end

    test "produces scope_without_evidence for high-scope plans missing validation" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "queued"})

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Done",
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "scope_estimate" => %{
                   "files_touched_estimate" => 8,
                   "diff_size_estimate" => 500,
                   "architectural_scope" => true
                 },
                 "submission_body" => "Big plan without validation"
               })

      task = Mission.get_task!(task.id)
      findings = Mission.decision_hygiene_findings(task)

      assert Enum.any?(findings, &(&1["rule_id"] == "planning.scope_without_evidence"))

      scope_finding = Enum.find(findings, &(&1["rule_id"] == "planning.scope_without_evidence"))
      assert scope_finding["severity"] == "high"
      assert scope_finding["plain_message"] =~ "validation"
    end

    test "produces weak_verification_confidence for execution-ready plan without validation" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "queued"})

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Done",
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "rejected_options" => ["B"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "scope_estimate" => %{"files_touched_estimate" => 2, "diff_size_estimate" => 100},
                 "submission_body" => "Plan v1"
               })

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "code_backed_plan",
                 "research_summary" => "Done",
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "rejected_options" => ["B"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "code_snippets" => ["def foo do\n  :ok\nend"],
                 "scope_estimate" => %{"files_touched_estimate" => 2, "diff_size_estimate" => 100},
                 "submission_body" => "Plan v2 still no validation"
               })

      task = Mission.get_task!(task.id)
      findings = Mission.decision_hygiene_findings(task)

      assert Enum.any?(findings, &(&1["rule_id"] == "review.weak_verification_confidence"))

      weak_finding =
        Enum.find(findings, &(&1["rule_id"] == "review.weak_verification_confidence"))

      assert weak_finding["plain_message"] =~ "verification"
    end

    test "review_gate_status exposes decision hygiene diagnostic findings" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "queued"})

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "implementation_plan",
                 "research_summary" => "Done",
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "rejected_options" => ["B"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "scope_estimate" => %{
                   "files_touched_estimate" => 8,
                   "diff_size_estimate" => 500,
                   "architectural_scope" => true
                 },
                 "submission_body" => "Initial large plan without validation"
               })

      assert {:ok, _review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "review_type" => "plan",
                 "plan_phase" => "code_backed_plan",
                 "research_summary" => "Done",
                 "options_considered" => ["A", "B"],
                 "selected_option" => "A",
                 "rejected_options" => ["B"],
                 "implementation_steps" => ["Step 1", "Step 2"],
                 "code_snippets" => ["def foo do\n  :ok\nend"],
                 "scope_estimate" => %{
                   "files_touched_estimate" => 8,
                   "diff_size_estimate" => 500,
                   "architectural_scope" => true
                 },
                 "submission_body" => "Large plan without validation"
               })

      task = Mission.get_task!(task.id)
      gate = Mission.review_gate_status(task)
      rule_ids = Enum.map(gate["diagnostic_findings"], & &1["rule_id"])

      assert "planning.scope_without_evidence" in rule_ids
      assert "review.weak_verification_confidence" in rule_ids
    end
  end
end
