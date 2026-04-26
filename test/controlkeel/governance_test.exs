defmodule ControlKeel.GovernanceTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Governance
  alias ControlKeel.Mission

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-governance-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "review_patch blocks risky hunks and persists findings when session_id is provided" do
    session = session_fixture()

    patch = """
    diff --git a/lib/auth.ex b/lib/auth.ex
    index 1111111..2222222 100644
    --- a/lib/auth.ex
    +++ b/lib/auth.ex
    @@ -0,0 +1,1 @@
    +api_key = "AKIAIOSFODNN7EXAMPLE"
    """

    assert {:ok, review} = Governance.review_patch(patch, session_id: session.id)
    assert review["decision"] == "block"
    assert review["blocking"] == true
    assert review["files_reviewed"] == 1
    assert length(review["persisted_finding_ids"]) > 0

    persisted = Mission.list_session_findings(session.id)
    assert Enum.any?(persisted, &(&1.rule_id == "secret.aws_access_key"))
  end

  test "review_diff reads a git diff between refs", %{tmp_dir: tmp_dir} do
    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.name", "ControlKeel Test"], cd: tmp_dir)
    assert :ok == File.write(Path.join(tmp_dir, "README.md"), "# demo\n")
    assert {"", 0} = System.cmd("git", ["add", "README.md"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)
    assert :ok == File.write(Path.join(tmp_dir, "README.md"), "# demo\n\nstill safe\n")
    assert {_, 0} = System.cmd("git", ["commit", "-am", "update"], cd: tmp_dir)

    assert {:ok, review} = Governance.review_diff("HEAD~1", "HEAD", project_root: tmp_dir)
    assert review["decision"] == "allow"
    assert review["files_reviewed"] == 1
    assert review["chunks_reviewed"] == 1
  end

  test "review_pr_url fetches a GitHub PR patch before review" do
    patch = """
    diff --git a/lib/auth.ex b/lib/auth.ex
    index 1111111..2222222 100644
    --- a/lib/auth.ex
    +++ b/lib/auth.ex
    @@ -0,0 +1,1 @@
    +api_key = "AKIAIOSFODNN7EXAMPLE"
    """

    previous = Application.get_env(:controlkeel, :governance_patch_fetcher)

    Application.put_env(:controlkeel, :governance_patch_fetcher, fn url, _opts ->
      assert url == "https://github.com/acme/demo/pull/123.patch"
      {:ok, patch}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :governance_patch_fetcher, previous)
      else
        Application.delete_env(:controlkeel, :governance_patch_fetcher)
      end
    end)

    assert {:ok, review} =
             Governance.review_pr_url("https://github.com/acme/demo/pull/123")

    assert review["decision"] == "block"
    assert review["pr_url"] == "https://github.com/acme/demo/pull/123"
    assert review["patch_url"] == "https://github.com/acme/demo/pull/123.patch"
  end

  test "release_readiness requires smoke and provenance even with a deploy-ready proof" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done"})

    assert {:ok, plan_review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "research_summary" => "Reviewed the release-readiness and proof flow.",
               "codebase_findings" => ["Governance reads the latest proof bundle."],
               "alignment_context" => [
                 "Release managers require smoke evidence and provenance before calling work ready."
               ],
               "options_considered" => ["Reuse proof bundles", "Add release-only state"],
               "selected_option" => "Reuse proof bundles",
               "rejected_options" => ["Add release-only state"],
               "implementation_steps" => ["Generate proof", "Require smoke and provenance"],
               "validation_plan" => ["mix test", "mix precommit"],
               "submission_body" => "Implementation-ready release readiness plan"
             })

    assert {:ok, _approved} =
             Mission.respond_review(plan_review, %{
               "decision" => "approved",
               "feedback_notes" => "Approved plan"
             })

    _proof = proof_bundle_fixture(%{task: task})

    assert {:ok, readiness} = Governance.release_readiness(session_id: session.id)
    assert readiness["status"] == "needs-review"
    assert Enum.any?(readiness["reasons"], &String.contains?(&1, "Release smoke evidence"))
    assert Enum.any?(readiness["reasons"], &String.contains?(&1, "Artifact provenance"))

    assert {:ok, ready} =
             Governance.release_readiness(%{
               session_id: session.id,
               smoke: %{"status" => "success", "run_id" => "123"},
               provenance: %{"verified" => true, "attestation_id" => "att-1"}
             })

    assert ready["status"] == "ready"
  end

  test "install_github_scaffolding writes workflow files", %{tmp_dir: tmp_dir} do
    assert {:ok, install} = Governance.install_github_scaffolding(tmp_dir)
    assert install["provider"] == "github"

    pr_workflow = Path.join(tmp_dir, ".github/workflows/controlkeel-pr-governor.yml")
    release_workflow = Path.join(tmp_dir, ".github/workflows/controlkeel-release-governor.yml")
    scorecards = Path.join(tmp_dir, ".github/workflows/scorecards.yml")
    readme = Path.join(tmp_dir, ".github/controlkeel/README.md")

    assert File.exists?(pr_workflow)
    assert File.exists?(release_workflow)
    assert File.exists?(scorecards)
    assert File.exists?(readme)

    assert File.read!(pr_workflow) =~ "controlkeel review pr"
    assert File.read!(release_workflow) =~ "controlkeel release-ready"
    assert File.read!(scorecards) =~ "ossf/scorecard-action"
  end

  test "release_readiness blocks unresolved critical vulnerability cases" do
    session =
      session_fixture(%{
        execution_brief: %{"domain_pack" => "security", "occupation" => "security_researcher"},
        metadata: %{
          "mission_template" => "security_defender_v1",
          "cyber_access_mode" => "verified_research"
        }
      })

    task =
      task_fixture(%{
        session: session,
        status: "done",
        metadata: %{"track" => "release", "security_workflow_phase" => "disclosure"}
      })

    _finding =
      finding_fixture(%{
        session: session,
        severity: "critical",
        category: "security",
        rule_id: "security.workflow.scope_authorization",
        status: "open",
        metadata: %{
          "finding_family" => "vulnerability_case",
          "affected_component" => "kernel/subsystem",
          "evidence_type" => "source",
          "exploitability_status" => "reproduced",
          "patch_status" => "drafted",
          "disclosure_status" => "reported",
          "maintainer_scope" => "open_source",
          "cwe_ids" => ["CWE-284"]
        }
      })

    _proof = proof_bundle_fixture(%{task: task})

    assert {:ok, readiness} =
             Governance.release_readiness(%{
               session_id: session.id,
               smoke: %{"status" => "success"},
               provenance: %{"verified" => true}
             })

    assert readiness["status"] == "blocked"
    assert readiness["findings"]["critical_vulnerability_cases"] == 1
  end
end
