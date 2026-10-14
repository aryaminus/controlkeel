defmodule ControlKeel.Cloud.CloudAgentE2ETest do
  @moduledoc """
  End-to-end integration tests for the cloud-agent callback flow.

  Covers Scenarios 6 (Cloud agents + cloud CK) and 7 (Cloud agents + self-hosted CK)
  from DEPLOYMENT_SCENARIOS_STATUS.md. Tests the full lifecycle:

    pending → in_progress → completed (or failed/cancelled)

  Also validates finding ingestion via callback, terminal-state enforcement,
  and missing-Bearer rejection. Uses real DB fixtures via ConnCase — no mocking.
  """

  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Cloud.{RunPackage, RuntimeContext}
  alias ControlKeel.Mission
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  # ── Fixtures ─────────────────────────────────────────────────────────

  # Cloud execution fails closed for org-less workspaces (#269), so these
  # packages must run against a real tenant with a real authorized user.
  defp workspace!(seed) do
    {ws, user, _org} =
      MissionFixtures.org_bound_workspace_fixture(%{
        name: "E2E-#{seed}",
        slug: "e2e-#{seed}-#{System.unique_integer([:positive])}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    {ws, user}
  end

  defp session!(ws) do
    {:ok, s} =
      Mission.create_session(%{
        title: "E2E session",
        objective: "cloud agent test",
        risk_tier: "low",
        budget_cents: 5_000,
        daily_budget_cents: 5_000,
        workspace_id: ws.id
      })

    s
  end

  defp task!(session) do
    {:ok, t} =
      Mission.create_task(%{
        session_id: session.id,
        title: "E2E task",
        description: "cloud agent e2e task",
        position: 1,
        validation_gate: "manual"
      })

    t
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  # ── Tests ─────────────────────────────────────────────────────────────

  test "full pending → in_progress → completed callback cycle", %{conn: conn} do
    {ws, user} = workspace!("full")
    session = session!(ws)
    task = task!(session)

    {:ok, package, raw_token} =
      RuntimeContext.create_package(%{
        session_id: session.id,
        task_id: task.id,
        workspace_id: ws.id,
        user_id: user.id,
        runtime_target: "devin"
      })

    assert package.status == "pending"

    # 1. Transition to in_progress
    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{status: "in_progress"})

    assert json_response(resp, 200)["status"] == "in_progress"

    # 2. Complete with a finding
    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{
        status: "completed",
        result_summary: "All done",
        findings: [
          %{
            title: "Cloud agent finding",
            severity: "low",
            category: "code_quality",
            rule_id: "E2E-CLOUD-001",
            plain_message: "Identified via cloud agent callback"
          }
        ]
      })

    body = json_response(resp, 200)
    assert body["status"] == "completed"
    assert is_list(body["findings_created"])
    assert length(body["findings_created"]) == 1

    # The finding should be retrievable on the session
    finding_id = hd(body["findings_created"])
    assert Repo.get(ControlKeel.Mission.Finding, finding_id) != nil
  end

  test "terminal package rejects further callbacks with 403", %{conn: conn} do
    {ws, user} = workspace!("terminal")
    session = session!(ws)
    task = task!(session)

    {:ok, _package, raw_token} =
      RuntimeContext.create_package(%{
        session_id: session.id,
        task_id: task.id,
        workspace_id: ws.id,
        user_id: user.id,
        runtime_target: "devin"
      })

    # Complete it
    conn
    |> bearer(raw_token)
    |> post("/cloud/v1/runtime/callbacks", %{status: "completed"})
    |> json_response(200)

    # Second call must be rejected
    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{status: "completed"})

    assert json_response(resp, 403)["error"] == "package_is_terminal"
  end

  test "failed transition recorded correctly", %{conn: conn} do
    {ws, user} = workspace!("failed")
    session = session!(ws)
    task = task!(session)

    {:ok, _package, raw_token} =
      RuntimeContext.create_package(%{
        session_id: session.id,
        task_id: task.id,
        workspace_id: ws.id,
        user_id: user.id,
        runtime_target: "open-swe"
      })

    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{
        status: "failed",
        error_summary: "Execution environment unavailable"
      })

    body = json_response(resp, 200)
    assert body["status"] == "failed"
    assert body["error_summary"] == "Execution environment unavailable"
  end

  test "missing Bearer token returns 401", %{conn: conn} do
    resp = post(conn, "/cloud/v1/runtime/callbacks", %{status: "in_progress"})
    assert json_response(resp, 401)["error"] =~ ~r/missing|bearer/i
  end

  test "invalid callback token returns 403", %{conn: conn} do
    resp =
      conn
      |> bearer("totally_invalid_token")
      |> post("/cloud/v1/runtime/callbacks", %{status: "in_progress"})

    assert json_response(resp, 403)["error"] == "invalid_token"
  end

  test "invalid status value returns 400", %{conn: conn} do
    {ws, user} = workspace!("badstatus")
    session = session!(ws)
    task = task!(session)

    {:ok, _package, raw_token} =
      RuntimeContext.create_package(%{
        session_id: session.id,
        task_id: task.id,
        workspace_id: ws.id,
        user_id: user.id,
        runtime_target: "executor"
      })

    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{status: "purple"})

    assert json_response(resp, 400)["error"] == "invalid_status"
  end

  test "callback with proof_refs stores them on the package", %{conn: conn} do
    {ws, user} = workspace!("proof")
    session = session!(ws)
    task = task!(session)

    {:ok, package, raw_token} =
      RuntimeContext.create_package(%{
        session_id: session.id,
        task_id: task.id,
        workspace_id: ws.id,
        user_id: user.id,
        runtime_target: "cursor-cloud-agents"
      })

    proof_refs = ["sha256:abc123", "sha256:def456"]

    resp =
      conn
      |> bearer(raw_token)
      |> post("/cloud/v1/runtime/callbacks", %{
        status: "completed",
        proof_refs: proof_refs
      })

    # proof_refs are stored and returned comma-joined (encode_list/1 in RuntimeContext)
    returned = json_response(resp, 200)["proof_refs"]
    assert String.split(returned, ",") == proof_refs

    refreshed = Repo.get!(RunPackage, package.id)
    # DB stores the comma-joined string
    assert refreshed.proof_refs == Enum.join(proof_refs, ",")
  end
end
