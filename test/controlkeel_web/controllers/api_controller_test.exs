defmodule ControlKeelWeb.ApiControllerTest do
  use ControlKeelWeb.ConnCase

  import ControlKeel.MissionFixtures

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

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/99999999/audit-log")
      assert %{"error" => "session not found"} = json_response(conn, 404)
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
end
