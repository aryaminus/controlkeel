defmodule ControlKeelWeb.ApiControllerTest do
  use ControlKeelWeb.ConnCase

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.IntentFixtures
  import ControlKeel.MissionFixtures
  import ControlKeel.PolicyTrainingFixtures
  import ControlKeel.PlatformFixtures

  # ─── Sessions ────────────────────────────────────────────────────────────────

  describe "GET /api/v1/sessions" do
    test "returns empty list when no sessions exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions")
      assert %{"sessions" => []} = json_response(conn, 200)
    end

    test "returns list of sessions", %{conn: conn} do
      session = session_fixture()
      conn = get(conn, ~p"/api/v1/sessions")
      body = json_response(conn, 200)
      assert length(body["sessions"]) == 1
      assert hd(body["sessions"])["id"] == session.id
    end
  end

  describe "POST /api/v1/sessions" do
    test "creates a session with valid attributes", %{conn: conn} do
      workspace = workspace_fixture()

      conn =
        post(conn, ~p"/api/v1/sessions", %{
          title: "Test Mission",
          objective: "Build the first workflow",
          risk_tier: "moderate",
          status: "in_progress",
          budget_cents: 3000,
          daily_budget_cents: 1000,
          spent_cents: 0,
          execution_brief: %{"recommended_stack" => "Phoenix"},
          workspace_id: workspace.id
        })

      assert %{"session" => session} = json_response(conn, 201)
      assert session["title"] == "Test Mission"
    end

    test "returns error with missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions", %{})
      assert %{"error" => "invalid session"} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/sessions/:id" do
    test "returns session detail", %{conn: conn} do
      session = session_fixture()
      conn = get(conn, ~p"/api/v1/sessions/#{session.id}")
      assert %{"session" => detail} = json_response(conn, 200)
      assert detail["id"] == session.id
      assert Map.has_key?(detail, "tasks")
      assert Map.has_key?(detail, "findings")
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/99999999")
      assert %{"error" => "session not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/v1/domains" do
    test "returns domain packs and occupation profiles", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/domains")
      body = json_response(conn, 200)

      assert is_list(body["domains"])
      assert is_list(body["occupations"])

      healthcare =
        Enum.find(body["domains"], fn domain ->
          domain["id"] == "healthcare"
        end)

      assert healthcare["label"] == "Healthcare"
      assert "HIPAA" in healthcare["compliance"]
      assert Enum.any?(healthcare["occupations"], &(&1["id"] == "healthcare"))

      founder =
        Enum.find(body["occupations"], fn profile ->
          profile["id"] == "founder"
        end)

      assert founder["domain_pack"] == "software"
      assert founder["domain_pack_label"] == "Software"
    end
  end

  describe "GET and POST /api/v1/context" do
    test "returns assembled context for a session", %{conn: conn} do
      session =
        session_fixture(%{
          execution_brief:
            execution_brief_fixture(
              compiler: %{
                "interview_answers" => %{
                  "constraints" => "Local-first deploy, approval before production"
                }
              }
            )
            |> ControlKeel.Intent.to_brief_map()
        })

      task = task_fixture(%{session: session, status: "in_progress"})

      conn = get(conn, ~p"/api/v1/context?session_id=#{session.id}&task_id=#{task.id}")
      body = json_response(conn, 200)

      assert body["context"]["session_id"] == session.id
      assert body["context"]["current_task"]["id"] == task.id
      assert Map.has_key?(body["context"], "provider_status")
      assert Map.has_key?(body["context"], "bootstrap_status")
      assert body["context"]["boundary_summary"]["risk_tier"] == "critical"

      assert body["context"]["boundary_summary"]["constraints"] == [
               "Local-first deploy",
               "approval before production"
             ]

      conn =
        build_conn() |> post(~p"/api/v1/context", %{session_id: session.id, task_id: task.id})

      post_body = json_response(conn, 200)

      assert post_body["context"]["session_id"] == session.id
      assert post_body["context"]["current_task"]["id"] == task.id
      assert Map.has_key?(post_body["context"], "boundary_summary")
    end

    test "returns validation error when session_id is missing", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/context")
      assert %{"error" => "`session_id` is required"} = json_response(conn, 422)
    end
  end

  describe "review lifecycle API" do
    test "creates, fetches, and responds to reviews", %{conn: conn} do
      session = session_fixture()
      task = task_fixture(%{session: session})

      conn =
        post(conn, ~p"/api/v1/reviews", %{
          task_id: task.id,
          submission_body: "Plan from API"
        })

      assert %{"review" => review} = json_response(conn, 201)
      assert review["status"] == "pending"
      assert review["browser_url"] =~ "/reviews/"

      conn = build_conn() |> get(~p"/api/v1/reviews/#{review["id"]}")
      assert %{"review" => fetched} = json_response(conn, 200)
      assert fetched["id"] == review["id"]

      conn =
        build_conn()
        |> post(~p"/api/v1/reviews/#{review["id"]}/respond", %{
          decision: "approved",
          feedback_notes: "Proceed"
        })

      assert %{"review" => updated} = json_response(conn, 200)
      assert updated["status"] == "approved"
    end
  end

  # ─── Tasks ───────────────────────────────────────────────────────────────────

  describe "POST /api/v1/sessions/:session_id/tasks" do
    test "creates a task in the session", %{conn: conn} do
      session = session_fixture()

      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/tasks", %{
          title: "Build auth flow",
          validation_gate: "Security scan and proof bundle",
          estimated_cost_cents: 50,
          position: 1
        })

      assert %{"task" => task} = json_response(conn, 201)
      assert task["title"] == "Build auth flow"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions/99999999/tasks", %{title: "x"})
      assert %{"error" => "session not found"} = json_response(conn, 404)
    end
  end

  # ─── Validate ────────────────────────────────────────────────────────────────

  describe "POST /api/v1/validate" do
    test "returns allowed for clean content", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/validate", %{
          content: "def hello, do: :world",
          kind: "code"
        })

      body = json_response(conn, 200)
      assert body["allowed"] == true
      assert body["decision"] == "allow"
      assert is_list(body["findings"])
    end

    test "returns blocked for content with hardcoded secret", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/validate", %{
          content: ~s(api_key = "AKIAIOSFODNN7EXAMPLE"),
          kind: "code"
        })

      body = json_response(conn, 200)
      assert body["allowed"] == false
      assert body["decision"] == "block"
      assert length(body["findings"]) > 0
    end

    test "returns findings list with required fields", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/validate", %{
          content: ~s(password = "supersecret123"),
          kind: "code"
        })

      body = json_response(conn, 200)
      assert Map.has_key?(body, "allowed")
      assert Map.has_key?(body, "decision")
      assert Map.has_key?(body, "summary")
      assert Map.has_key?(body, "findings")
      assert Map.has_key?(body, "advisory")
      assert is_map(body["advisory"])

      assert body["advisory"]["status"] in [
               "disabled",
               "skipped_short_content",
               "skipped_no_provider",
               "ran",
               "ran_empty"
             ]
    end
  end

  describe "repo governance API" do
    test "reviews a PR patch and persists findings for a session", %{conn: conn} do
      session = session_fixture()

      patch = """
      diff --git a/lib/auth.ex b/lib/auth.ex
      index 1111111..2222222 100644
      --- a/lib/auth.ex
      +++ b/lib/auth.ex
      @@ -0,0 +1,1 @@
      +api_key = "AKIAIOSFODNN7EXAMPLE"
      """

      conn =
        post(conn, ~p"/api/v1/review/pr", %{
          patch: patch,
          session_id: session.id
        })

      body = json_response(conn, 200)
      assert body["review"]["decision"] == "block"
      assert body["review"]["blocking"] == true
      assert length(body["review"]["persisted_finding_ids"]) > 0
    end

    test "evaluates release readiness from proof and evidence state", %{conn: conn} do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})
      _proof = proof_bundle_fixture(%{task: task})

      conn =
        post(conn, ~p"/api/v1/release/readiness", %{
          session_id: session.id
        })

      body = json_response(conn, 200)
      assert body["release"]["status"] == "needs-review"

      conn =
        build_conn()
        |> post(~p"/api/v1/release/readiness", %{
          session_id: session.id,
          smoke: %{"status" => "success"},
          provenance: %{"verified" => true}
        })

      ready_body = json_response(conn, 200)
      assert ready_body["release"]["status"] == "ready"
    end

    test "installs github governance scaffolding", %{conn: conn} do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-api-governance-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      conn = post(conn, ~p"/api/v1/governance/install/github", %{project_root: tmp_dir})
      body = json_response(conn, 200)

      assert body["install"]["provider"] == "github"
      assert File.exists?(Path.join(tmp_dir, ".github/workflows/controlkeel-pr-governor.yml"))

      assert File.exists?(
               Path.join(tmp_dir, ".github/workflows/controlkeel-release-governor.yml")
             )

      assert File.exists?(Path.join(tmp_dir, ".github/workflows/scorecards.yml"))
    end
  end

  describe "agent execution API" do
    test "lists bidirectional agent execution metadata", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agents")
      body = json_response(conn, 200)

      assert is_list(body["agents"])

      cursor =
        Enum.find(body["agents"], fn agent ->
          agent["id"] == "cursor"
        end)

      assert cursor["execution_support"] == "handoff"
      assert cursor["ck_runs_agent_via"] == "handoff"
      assert "local_mcp" in cursor["agent_uses_ck_via"]
    end

    test "runs a task through the handoff executor", %{conn: conn} do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-agent-api-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()
      task = task_fixture(%{session: session})

      conn =
        post(conn, ~p"/api/v1/tasks/#{task.id}/run", %{
          agent: "cursor",
          mode: "handoff",
          project_root: tmp_dir
        })

      body = json_response(conn, 200)
      assert body["run"]["status"] == "waiting_callback"
      assert body["run"]["oauth_client_id"] =~ "ck-sa-"
      assert is_binary(body["run"]["client_secret"])
    end

    test "runs all ready tasks in a session", %{conn: conn} do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-agent-session-api-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()
      _task = task_fixture(%{session: session})

      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/run", %{
          agent: "cursor",
          mode: "handoff",
          project_root: tmp_dir
        })

      body = json_response(conn, 200)
      assert body["run"]["session_id"] == session.id
      assert body["run"]["task_count"] == 1
      assert hd(body["run"]["results"])["status"] == "waiting_callback"
    end
  end

  # ─── Findings ────────────────────────────────────────────────────────────────

  describe "GET /api/v1/findings" do
    test "returns paginated findings", %{conn: conn} do
      _finding = finding_fixture()
      conn = get(conn, ~p"/api/v1/findings")
      body = json_response(conn, 200)
      assert Map.has_key?(body, "findings")
      assert Map.has_key?(body, "total")
      assert Map.has_key?(body, "page")
      assert length(body["findings"]) >= 1
    end

    test "filters findings by session_id", %{conn: conn} do
      session = session_fixture()
      finding_fixture(%{session: session})
      conn = get(conn, ~p"/api/v1/findings?session_id=#{session.id}")
      body = json_response(conn, 200)
      assert Enum.all?(body["findings"], fn f -> f["id"] != nil end)
    end
  end

  describe "skills API" do
    test "lists skills and targets with compatibility metadata", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/skills")
      body = json_response(conn, 200)

      assert body["total"] > 0
      assert Enum.any?(body["skills"], &(&1["name"] == "controlkeel-governance"))

      skill =
        Enum.find(body["skills"], fn skill ->
          skill["name"] == "controlkeel-governance"
        end)

      assert "codex" in skill["compatibility_targets"]
      assert is_map(skill["install_state"])

      conn = build_conn() |> get(~p"/api/v1/skills/targets")
      response = json_response(conn, 200)
      targets = response["targets"]
      agents = response["agents"]
      registry_status = response["registry_status"]
      install_channels = response["installation_channels"]

      assert Enum.any?(targets, &(&1["id"] == "claude-plugin"))
      assert Enum.any?(targets, &(&1["id"] == "copilot-plugin"))
      assert Enum.any?(targets, &(&1["id"] == "vscode-companion"))
      assert Enum.any?(targets, &(&1["id"] == "cline-native"))
      assert Enum.any?(targets, &(&1["id"] == "roo-native"))
      assert Enum.any?(targets, &(&1["id"] == "goose-native"))
      assert Enum.any?(agents, &(&1["id"] == "claude-code"))
      assert Enum.any?(agents, &(&1["id"] == "cline"))
      assert Enum.any?(agents, &(&1["id"] == "roo-code"))
      assert Enum.any?(agents, &(&1["id"] == "goose"))
      assert Enum.any?(agents, &(&1["id"] == "cursor"))
      assert Enum.any?(agents, &(&1["id"] == "open-swe"))
      assert Enum.any?(agents, &(&1["id"] == "devin"))
      assert Enum.any?(agents, &(&1["id"] == "vllm"))
      assert is_map(registry_status)
      assert Map.has_key?(registry_status, "stale")
      assert Enum.any?(install_channels, &(&1["id"] == "homebrew"))
      assert Enum.any?(install_channels, &(&1["id"] == "npm"))

      claude =
        Enum.find(agents, fn agent ->
          agent["id"] == "claude-code"
        end)

      assert claude["preferred_target"] == "claude-standalone"
      assert claude["support_class"] == "attach_client"
      assert claude["phase_model"] == "host_plan_mode"
      assert claude["browser_embed"] == "external"
      assert claude["runtime_transport"] == "claude_agent_sdk"
      assert claude["runtime_auth_owner"] == "agent"
      assert claude["runtime_review_transport"] == "hook_sdk"
      assert claude["runtime_session_support"]["fork"] == true
      assert "ck_validate" in claude["required_mcp_tools"]
      assert Enum.any?(claude["install_channels"], &(&1["id"] == "homebrew"))

      assert Enum.any?(
               claude["package_outputs"],
               &(&1["artifact"] == "controlkeel-claude-plugin.tar.gz")
             )

      assert Enum.any?(
               claude["direct_install_methods"],
               &(&1["command"] == "claude --plugin-dir ./controlkeel/dist/claude-plugin")
             )

      open_swe =
        Enum.find(agents, fn agent ->
          agent["id"] == "open-swe"
        end)

      assert open_swe["support_class"] == "headless_runtime"
      assert open_swe["runtime_export_command"] == "controlkeel runtime export open-swe"

      devin =
        Enum.find(agents, fn agent ->
          agent["id"] == "devin"
        end)

      assert devin["support_class"] == "headless_runtime"
      assert devin["runtime_export_command"] == "controlkeel runtime export devin"

      opencode =
        Enum.find(agents, fn agent ->
          agent["id"] == "opencode"
        end)

      assert opencode["runtime_transport"] == "opencode_sdk"
      assert opencode["runtime_auth_owner"] == "agent"
      assert opencode["auth_mode"] == "agent_runtime"

      assert Enum.any?(
               opencode["direct_install_methods"],
               &(&1["command"] =~ "@aryaminus/controlkeel-opencode")
             )

      augment =
        Enum.find(agents, fn agent ->
          agent["id"] == "augment"
        end)

      assert augment["preferred_target"] == "augment-native"
      assert augment["phase_model"] == "host_plan_mode"
      assert augment["review_experience"] == "native_review"
      assert augment["runtime_transport"] == "auggie_sdk_acp"
      assert augment["runtime_auth_owner"] == "agent"
      assert augment["runtime_review_transport"] == "plugin_hook_acp"
      assert augment["runtime_session_support"]["resume"] == true
      assert "hooks" in augment["agent_uses_ck_via"]
      assert ".augment/commands/controlkeel-review.md" in augment["artifact_surfaces"]

      assert Enum.any?(
               augment["package_outputs"],
               &(&1["artifact"] == "controlkeel-augment-plugin.tar.gz")
             )

      assert Enum.any?(
               augment["direct_install_methods"],
               &(&1["command"] == "auggie --plugin-dir ./controlkeel/dist/augment-plugin")
             )

      vscode =
        Enum.find(agents, fn agent ->
          agent["id"] == "vscode"
        end)

      assert vscode["phase_model"] == "review_only"
      assert vscode["runtime_transport"] == "vscode_companion"
      assert vscode["runtime_review_transport"] == "vscode_ipc"

      cline =
        Enum.find(agents, fn agent ->
          agent["id"] == "cline"
        end)

      assert cline["preferred_target"] == "cline-native"
      assert cline["skills_mode"] == "native"
      assert cline["auth_owner"] == "controlkeel"
    end

    test "gets skill detail and exports and installs bundles", %{conn: conn} do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-skills-api-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      conn = get(conn, ~p"/api/v1/skills/controlkeel-governance")
      detail = json_response(conn, 200)["skill"]
      assert detail["name"] == "controlkeel-governance"
      assert is_list(detail["resources"])

      conn =
        build_conn()
        |> post(~p"/api/v1/skills/export", %{
          target: "claude-plugin",
          project_root: tmp_dir,
          scope: "export"
        })

      plan = json_response(conn, 200)["plan"]
      assert plan["target"] == "claude-plugin"
      assert File.exists?(Path.join(plan["output_dir"], ".claude-plugin/plugin.json"))

      conn =
        build_conn()
        |> post(~p"/api/v1/skills/install", %{
          target: "open-standard",
          project_root: tmp_dir,
          scope: "project"
        })

      install = json_response(conn, 200)["install"]
      assert install["target"] == "open-standard"
      assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    end
  end

  describe "benchmark API" do
    test "lists suites and recent runs", %{conn: conn} do
      run = benchmark_run_fixture()

      conn = get(conn, ~p"/api/v1/benchmarks")
      body = json_response(conn, 200)

      assert body["summary"]["total_suites"] >= 1
      assert Enum.any?(body["suites"], &(&1["slug"] == "vibe_failures_v1"))
      assert Enum.any?(body["runs"], &(&1["id"] == run.id))
    end

    test "filters suites by domain pack", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/benchmarks?domain_pack=hr")
      body = json_response(conn, 200)

      assert body["selected_domain_pack"] == "hr"
      assert Enum.any?(body["suites"], &(&1["slug"] == "domain_expansion_v1"))
      refute Enum.any?(body["suites"], &(&1["slug"] == "vibe_failures_v1"))
    end

    test "creates and fetches a benchmark run", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/benchmarks/runs", %{
          suite: "domain_expansion_v1",
          subjects: "controlkeel_validate",
          baseline_subject: "controlkeel_validate",
          domain_pack: "sales"
        })

      assert %{"run" => run} = json_response(conn, 201)
      assert run["suite_slug"] == "domain_expansion_v1"
      assert run["subjects"] == ["controlkeel_validate"]
      assert length(run["scenarios"]) == 1
      assert run["domain_packs"] == ["sales"]
      assert hd(run["scenarios"])["scenario"]["metadata"]["domain_pack"] == "sales"

      conn = build_conn() |> get(~p"/api/v1/benchmarks/runs/#{run["id"]}")
      assert %{"run" => fetched} = json_response(conn, 200)
      assert fetched["id"] == run["id"]
      assert length(fetched["scenarios"]) == 1
    end

    test "imports a manual subject result and exports csv", %{conn: conn} do
      tmp_dir = benchmark_tmp_dir()

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      write_benchmark_subjects!(tmp_dir, [
        %{
          "id" => "manual_subject",
          "label" => "Manual Subject",
          "type" => "manual_import"
        }
      ])

      {:ok, run} =
        ControlKeel.Benchmark.run_suite(
          %{
            "suite" => "vibe_failures_v1",
            "subjects" => "manual_subject",
            "baseline_subject" => "manual_subject",
            "scenario_slugs" => "hardcoded_api_key_python_webhook"
          },
          tmp_dir
        )

      conn =
        post(conn, ~p"/api/v1/benchmarks/runs/#{run.id}/import", %{
          subject: "manual_subject",
          scenario_slug: "hardcoded_api_key_python_webhook",
          content: "OPENAI_KEY = \"AKIAIOSFODNN7EXAMPLE\"",
          path: "app/intake_handler.py",
          kind: "code",
          duration_ms: 12
        })

      assert %{"run" => updated_run} = json_response(conn, 200)

      scenario_row =
        Enum.find(updated_run["scenarios"], fn row ->
          row["scenario"]["slug"] == "hardcoded_api_key_python_webhook"
        end)

      [result] = scenario_row["results"]

      assert result["status"] == "completed"
      assert result["decision"] == "block"
      assert result["matched_expected"] == true

      conn = build_conn() |> get(~p"/api/v1/benchmarks/runs/#{run.id}/export?format=csv")
      assert response(conn, 200) =~ "run_id,suite_slug,scenario_slug"
    end
  end

  describe "policy API" do
    test "lists and fetches policy artifacts", %{conn: conn} do
      artifact = policy_artifact_fixture(%{artifact_type: "router", status: "active"})

      conn = get(conn, ~p"/api/v1/policies")
      body = json_response(conn, 200)

      assert Enum.any?(body["policies"], &(&1["id"] == artifact.id))
      assert body["active"]["router"]["id"] == artifact.id

      conn = build_conn() |> get(~p"/api/v1/policies/#{artifact.id}")
      assert %{"policy" => fetched} = json_response(conn, 200)
      assert fetched["id"] == artifact.id
      assert fetched["artifact_type"] == "router"
    end

    test "trains, promotes, and archives a policy artifact", %{conn: conn} do
      benchmark_run_fixture(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook"
      })

      conn = post(conn, ~p"/api/v1/policies/train", %{type: "router"})
      assert %{"policy" => policy} = json_response(conn, 201)
      assert policy["artifact_type"] == "router"

      promotable =
        policy_artifact_fixture(%{
          artifact_type: "budget_hint",
          metrics: %{"gates" => %{"eligible" => true, "reasons" => []}}
        })

      conn = build_conn() |> post(~p"/api/v1/policies/#{promotable.id}/promote", %{})
      assert %{"policy" => promoted} = json_response(conn, 200)
      assert promoted["status"] == "active"

      conn = build_conn() |> post(~p"/api/v1/policies/#{promotable.id}/archive", %{})
      assert %{"policy" => archived} = json_response(conn, 200)
      assert archived["status"] == "archived"
    end
  end

  describe "POST /api/v1/findings/:id/action" do
    test "approves a finding", %{conn: conn} do
      finding = finding_fixture()

      conn =
        post(conn, ~p"/api/v1/findings/#{finding.id}/action", %{
          action: "approve"
        })

      assert %{"finding" => result} = json_response(conn, 200)
      assert result["status"] == "approved"
    end

    test "rejects a finding with a reason", %{conn: conn} do
      finding = finding_fixture()

      conn =
        post(conn, ~p"/api/v1/findings/#{finding.id}/action", %{
          action: "reject",
          reason: "False positive — this is a test token"
        })

      assert %{"finding" => result} = json_response(conn, 200)
      assert result["status"] == "rejected"
    end

    test "escalates a finding", %{conn: conn} do
      finding = finding_fixture()

      conn =
        post(conn, ~p"/api/v1/findings/#{finding.id}/action", %{
          action: "escalate"
        })

      assert %{"finding" => result} = json_response(conn, 200)
      assert result["status"] == "escalated"
    end

    test "returns error for unknown action", %{conn: conn} do
      finding = finding_fixture()

      conn =
        post(conn, ~p"/api/v1/findings/#{finding.id}/action", %{
          action: "delete"
        })

      assert %{"error" => "unknown action"} = json_response(conn, 422)
    end

    test "returns 404 for unknown finding", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/findings/99999999/action", %{
          action: "approve"
        })

      assert %{"error" => "finding not found"} = json_response(conn, 404)
    end
  end

  # ─── Update Task ─────────────────────────────────────────────────────────────

  describe "PATCH /api/v1/tasks/:id" do
    test "updates task status", %{conn: conn} do
      task = task_fixture()

      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{status: "in_progress"})
      assert %{"task" => result} = json_response(conn, 200)
      assert result["status"] == "in_progress"
    end

    test "returns 404 for unknown task", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/tasks/99999999", %{status: "done"})
      assert %{"error" => "task not found"} = json_response(conn, 404)
    end
  end

  # ─── Complete Task ────────────────────────────────────────────────────────────

  describe "POST /api/v1/tasks/:id/complete" do
    test "marks task done when no open findings exist", %{conn: conn} do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      _resolved = finding_fixture(%{session: session, status: "approved"})

      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete")
      assert %{"task" => result} = json_response(conn, 200)
      assert result["status"] == "done"
      assert result["latest_proof"]["task_id"] == task.id
    end

    test "returns 422 when open findings block completion", %{conn: conn} do
      session = session_fixture()
      task = task_fixture(%{session: session})
      _open = finding_fixture(%{session: session, status: "open"})

      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete")
      assert %{"error" => msg} = json_response(conn, 422)
      assert is_binary(msg)
    end

    test "returns 404 for unknown task", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/tasks/99999999/complete")
      assert %{"error" => "task not found"} = json_response(conn, 404)
    end
  end

  # ─── Proof Bundle ─────────────────────────────────────────────────────────────

  describe "GET /api/v1/proof/:task_id" do
    test "returns proof bundle for a task", %{conn: conn} do
      task = task_fixture(%{status: "done"})

      conn = get(conn, ~p"/api/v1/proof/#{task.id}")
      body = json_response(conn, 200)
      proof = body["proof"]
      assert proof["task_id"] == task.id
      assert Map.has_key?(proof, "deploy_ready")
      assert Map.has_key?(proof, "security_findings")
      assert Map.has_key?(proof, "compliance_attestations")
    end

    test "returns 404 for unknown task", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/proof/99999999")
      assert %{"error" => "task not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/v1/proofs and /api/v1/proofs/:id" do
    test "lists persisted proof bundles and fetches one by id", %{conn: conn} do
      proof = proof_bundle_fixture()

      conn = get(conn, ~p"/api/v1/proofs")
      body = json_response(conn, 200)
      assert Enum.any?(body["proofs"], &(&1["id"] == proof.id))

      conn = get(recycle(conn), ~p"/api/v1/proofs/#{proof.id}")
      detail = json_response(conn, 200)["proof"]
      assert detail["id"] == proof.id
      assert Map.has_key?(detail, "bundle")
    end
  end

  describe "POST /api/v1/tasks/:id/pause and /resume" do
    test "pauses and resumes a task with a resume packet", %{conn: conn} do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/pause")
      body = json_response(conn, 200)
      assert body["task"]["status"] == "paused"
      assert Map.has_key?(body["resume_packet"], "memory_hits")
      assert Map.has_key?(body["resume_packet"], "workspace_context")
      assert Map.has_key?(body["resume_packet"], "recent_events")

      conn = post(recycle(conn), ~p"/api/v1/tasks/#{task.id}/resume")
      body = json_response(conn, 200)
      assert body["task"]["status"] == "in_progress"
    end
  end

  describe "GET /api/v1/memory/search and DELETE /api/v1/memory/:id" do
    test "searches and archives memory records", %{conn: conn} do
      session = session_fixture()
      record = memory_record_fixture(%{session: session, title: "Reusable memory note"})

      conn = get(conn, ~p"/api/v1/memory/search?q=Reusable&session_id=#{session.id}")
      body = json_response(conn, 200)
      assert Enum.any?(body["records"], &(&1["id"] == record.id))

      conn = delete(recycle(conn), ~p"/api/v1/memory/#{record.id}")
      assert %{"memory" => %{"id" => id}} = json_response(conn, 200)
      assert id == record.id
    end
  end

  # ─── Audit Log ────────────────────────────────────────────────────────────────

  describe "GET /api/v1/sessions/:id/audit-log" do
    test "returns JSON audit log", %{conn: conn} do
      session = session_fixture()
      _finding = finding_fixture(%{session: session})

      conn = get(conn, ~p"/api/v1/sessions/#{session.id}/audit-log")
      body = json_response(conn, 200)
      log = body["audit_log"]
      assert log["session_id"] == session.id or log["session_id"] == Integer.to_string(session.id)
      assert Map.has_key?(log, "events")
      assert Map.has_key?(log, "summary")
    end

    test "returns CSV audit log when format=csv", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, ~p"/api/v1/sessions/#{session.id}/audit-log?format=csv")
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      csv = response(conn, 200)
      assert String.starts_with?(csv, "session_id,")
    end

    test "returns PDF audit log when format=pdf", %{conn: conn} do
      previous_renderer = Application.get_env(:controlkeel, :pdf_renderer)
      Application.put_env(:controlkeel, :pdf_renderer, ControlKeel.TestSupport.FakePdfRenderer)

      on_exit(fn ->
        if previous_renderer do
          Application.put_env(:controlkeel, :pdf_renderer, previous_renderer)
        else
          Application.delete_env(:controlkeel, :pdf_renderer)
        end
      end)

      session = session_fixture()

      conn = get(conn, ~p"/api/v1/sessions/#{session.id}/audit-log?format=pdf")
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert response(conn, 200) =~ "%PDF-FAKE"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/99999999/audit-log")
      assert %{"error" => "session not found"} = json_response(conn, 404)
    end
  end

  describe "platform API" do
    test "creates service accounts, policy sets, and webhooks for a workspace", %{conn: conn} do
      workspace = workspace_fixture()

      conn =
        post(conn, ~p"/api/v1/workspaces/#{workspace.id}/service-accounts", %{
          name: "CI Worker",
          scopes: ["tasks:claim", "tasks:report"]
        })

      assert %{"service_account" => account, "token" => token} = json_response(conn, 201)
      assert account["workspace_id"] == workspace.id
      assert account["oauth_client_id"] == "ck-sa-#{account["id"]}"
      assert is_binary(token)

      conn = build_conn() |> get(~p"/api/v1/workspaces/#{workspace.id}/service-accounts")
      assert %{"service_accounts" => [listed | _]} = json_response(conn, 200)
      assert listed["oauth_client_id"] == "ck-sa-#{listed["id"]}"

      conn =
        build_conn()
        |> post(~p"/api/v1/workspaces/#{workspace.id}/policy-sets", %{
          name: "Workspace Guard",
          scope: "workspace",
          rules: [
            %{
              id: "workspace.no_exports",
              category: "compliance",
              severity: "high",
              action: "block",
              plain_message: "Exports need approval.",
              matcher: %{type: "literal", literal: "EXPORT_NOW"}
            }
          ]
        })

      assert %{"policy_set" => policy_set} = json_response(conn, 201)

      conn =
        build_conn()
        |> post(~p"/api/v1/workspaces/#{workspace.id}/policy-sets/#{policy_set["id"]}/apply", %{
          precedence: 5
        })

      assert %{"assignment" => %{"policy_set_id" => policy_set_id}} = json_response(conn, 200)
      assert policy_set_id == policy_set["id"]

      conn =
        build_conn()
        |> post(~p"/api/v1/workspaces/#{workspace.id}/webhooks", %{
          name: "CI Notify",
          url: "https://example.com/hooks/controlkeel",
          subscribed_events: ["task.completed", "audit.exported"]
        })

      assert %{"webhook" => webhook} = json_response(conn, 201)
      assert webhook["workspace_id"] == workspace.id

      conn = build_conn() |> get(~p"/api/v1/workspaces/#{workspace.id}/webhooks")
      assert %{"webhooks" => [%{"id" => id} | _]} = json_response(conn, 200)
      assert id == webhook["id"]
    end

    test "service account tokens are workspace-scoped for graph and task execution endpoints", %{
      conn: conn
    } do
      session = session_fixture()

      _arch =
        task_fixture(%{
          session: session,
          status: "done",
          position: 1,
          metadata: %{"track" => "architecture"}
        })

      feature =
        task_fixture(%{
          session: session,
          status: "queued",
          position: 2,
          metadata: %{"track" => "feature"}
        })

      _release =
        task_fixture(%{
          session: session,
          status: "queued",
          position: 3,
          metadata: %{"track" => "release"}
        })

      %{token: token} =
        service_account_fixture(%{
          workspace_id: session.workspace_id,
          scopes: "tasks:read,tasks:execute,tasks:claim,tasks:report"
        })

      authed =
        conn
        |> put_req_header("authorization", "Bearer #{token}")

      conn = get(authed, ~p"/api/v1/sessions/#{session.id}/graph")
      assert %{"graph" => graph} = json_response(conn, 200)
      assert is_list(graph["edges"])

      conn = post(recycle(authed), ~p"/api/v1/sessions/#{session.id}/execute", %{})
      assert %{"graph" => graph} = json_response(conn, 200)
      assert feature.id in graph["ready_task_ids"]

      conn =
        post(recycle(authed), ~p"/api/v1/tasks/#{feature.id}/claim", %{external_ref: "gha-1"})

      assert %{"task_run" => %{"status" => "in_progress"}} = json_response(conn, 200)

      conn =
        post(recycle(authed), ~p"/api/v1/tasks/#{feature.id}/checks", %{
          checks: [%{check_type: "tests", status: "passed", summary: "green"}]
        })

      assert %{"checks" => [%{"check_type" => "tests"}]} = json_response(conn, 200)

      conn =
        post(recycle(authed), ~p"/api/v1/tasks/#{feature.id}/report", %{
          status: "done",
          output: %{artifact: "build.tar.gz"}
        })

      assert %{"task_run" => %{"status" => "done"}} = json_response(conn, 200)

      other_session = session_fixture()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/sessions/#{other_session.id}/graph")

      assert %{"error" => "forbidden"} = json_response(conn, 403)
    end
  end

  describe "provider and bootstrap endpoints" do
    test "GET /api/v1/providers/status reports heuristic fallback by default", %{conn: conn} do
      tmp_dir = provider_tmp_dir("provider-status")
      home_dir = Path.join(tmp_dir, "home")
      File.mkdir_p!(home_dir)
      restore = set_provider_home(home_dir)

      on_exit(fn ->
        restore.()
        File.rm_rf!(tmp_dir)
      end)

      conn = get(conn, ~p"/api/v1/providers/status?project_root=#{tmp_dir}")
      body = json_response(conn, 200)

      assert body["status"]["selected_source"] == "heuristic"
      assert body["status"]["selected_provider"] == "heuristic"
      assert body["status"]["bootstrap"]["mode"] == "none"
    end

    test "POST /api/v1/providers/default and /bootstrap persist provider choice and auto-bootstrap",
         %{conn: conn} do
      tmp_dir = provider_tmp_dir("provider-bootstrap")
      home_dir = Path.join(tmp_dir, "home")
      project_root = Path.join(tmp_dir, "project")

      File.mkdir_p!(home_dir)
      File.mkdir_p!(project_root)

      restore = set_provider_home(home_dir)

      on_exit(fn ->
        restore.()
        File.rm_rf!(tmp_dir)
      end)

      conn =
        post(conn, ~p"/api/v1/providers/default", %{
          source: "openai",
          project_root: project_root
        })

      assert %{"status" => %{"selected_source" => "heuristic"}} = json_response(conn, 200)

      conn =
        post(build_conn(), ~p"/api/v1/bootstrap", %{
          project_root: project_root,
          agent: "codex"
        })

      body = json_response(conn, 200)

      assert body["mode"] == "bootstrapped_project"
      assert body["binding"]["bootstrap"]["mode"] == "project"
      assert body["provider_status"]["bootstrap"]["mode"] == "project"
      assert File.exists?(Path.join(project_root, "controlkeel/project.json"))
    end
  end

  # ─── Route Agent ─────────────────────────────────────────────────────────────

  describe "POST /api/v1/route-agent" do
    test "returns agent recommendation for a task", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/route-agent", %{task: "Build a REST API endpoint"})
      body = json_response(conn, 200)
      rec = body["recommendation"]
      assert Map.has_key?(rec, "agent")
      assert Map.has_key?(rec, "agent_name")
      assert Map.has_key?(rec, "rationale")
      assert is_list(rec["rationale"])
    end

    test "returns error when no agent satisfies constraints", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/route-agent", %{
          task: "PHI data update",
          risk_tier: "critical",
          allowed_agents: ["bolt"]
        })

      body = json_response(conn, 422)
      assert body["error"] == "no_suitable_agent"
      assert is_binary(body["message"])
    end
  end

  # ─── Budget ──────────────────────────────────────────────────────────────────

  describe "GET /api/v1/budget" do
    test "returns global budget summary when no session_id given", %{conn: conn} do
      _session = session_fixture()
      conn = get(conn, ~p"/api/v1/budget")
      body = json_response(conn, 200)
      assert Map.has_key?(body, "total_sessions")
      assert Map.has_key?(body, "total_spent_cents")
      assert Map.has_key?(body, "total_budget_cents")
    end

    test "returns session budget summary when session_id given", %{conn: conn} do
      session = session_fixture()
      conn = get(conn, ~p"/api/v1/budget?session_id=#{session.id}")
      body = json_response(conn, 200)
      assert body["session_id"] == session.id
      assert Map.has_key?(body, "budget_cents")
      assert Map.has_key?(body, "spent_cents")
      assert Map.has_key?(body, "rolling_24h_spend_cents")
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/budget?session_id=99999999")
      assert %{"error" => "session not found"} = json_response(conn, 404)
    end
  end

  defp benchmark_tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-api-benchmark-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp provider_tmp_dir(suffix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-api-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp set_provider_home(home_dir) do
    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)

    fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
