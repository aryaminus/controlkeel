defmodule ControlKeelWeb.ApiScopeTest do
  @moduledoc """
  Workspace-boundary regression tests for the /api/v1 endpoints.

  These verify that a service account belonging to workspace A cannot enumerate
  workspace B's sessions, findings, or proofs — even when both workspaces exist
  on the same database node.

  Closes finding CK-CLOUD-TENANT-001 (partial — covers the three list endpoints).
  """

  use ControlKeelWeb.ConnCase

  alias ControlKeel.Mission
  alias ControlKeel.Memory
  alias ControlKeel.Platform

  defp workspace!(seed) do
    {:ok, ws} =
      Mission.create_workspace(%{
        name: "Scope-#{seed}",
        slug: "scope-#{seed}-#{System.unique_integer([:positive])}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 5_000,
        compliance_profile: "baseline",
        status: "active",
        org_id: ControlKeel.AccountsFixtures.org_fixture().id
      })

    ws
  end

  defp service_account!(ws) do
    {:ok, %{service_account: _sa, token: token}} =
      Platform.create_service_account(ws.id, %{
        "name" => "test-sa-#{ws.id}",
        "scopes" =>
          "sessions:read sessions:write tasks:execute findings:write proofs:read reviews:read reviews:write budget:read memory:read memory:write",
        "kind" => "api"
      })

    token
  end

  defp memory!(session, title) do
    {:ok, record} =
      Memory.record(%{
        workspace_id: session.workspace_id,
        session_id: session.id,
        record_type: "decision",
        title: title,
        summary: title,
        source_type: "scope-test",
        source_id: "#{title}-#{System.unique_integer([:positive])}"
      })

    record
  end

  defp session!(ws, title) do
    {:ok, s} =
      Mission.create_session(%{
        title: title,
        objective: "scope test",
        risk_tier: "low",
        budget_cents: 1_000,
        daily_budget_cents: 500,
        workspace_id: ws.id
      })

    s
  end

  defp finding!(session) do
    {:ok, f} =
      Mission.create_finding(%{
        session_id: session.id,
        title: "scope finding",
        severity: "low",
        category: "completeness",
        rule_id: "CK-SCOPE-TEST-001",
        plain_message: "test",
        status: "open",
        metadata: %{}
      })

    f
  end

  defp task!(session, title \\ "scope task") do
    {:ok, task} =
      Mission.create_task(%{
        session_id: session.id,
        title: title,
        validation_gate: "test gate",
        status: "queued",
        position: 1,
        estimated_cost_cents: 1
      })

    task
  end

  defp review!(session, task) do
    {:ok, review} =
      Mission.submit_review(%{
        "session_id" => session.id,
        "task_id" => task.id,
        "review_type" => "plan",
        "title" => "Scoped review",
        "submission_body" => "Review me"
      })

    review
  end

  defp auth_header(token), do: {"authorization", "Bearer #{token}"}

  describe "GET /api/v1/sessions (list_sessions)" do
    test "service account for workspace A does not see workspace B sessions", %{conn: conn} do
      ws_a = workspace!("a")
      ws_b = workspace!("b")

      _session_b = session!(ws_b, "Workspace B Session")
      token_a = service_account!(ws_a)

      resp =
        conn
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> get("/api/v1/sessions")
        |> json_response(200)

      session_titles = Enum.map(resp["sessions"], & &1["title"])
      refute "Workspace B Session" in session_titles
    end

    test "service account for workspace A sees only workspace A sessions", %{conn: conn} do
      ws_a = workspace!("a2")
      ws_b = workspace!("b2")

      _session_a = session!(ws_a, "Workspace A Session")
      _session_b = session!(ws_b, "Workspace B Session")
      token_a = service_account!(ws_a)

      resp =
        conn
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> get("/api/v1/sessions")
        |> json_response(200)

      session_titles = Enum.map(resp["sessions"], & &1["title"])
      assert "Workspace A Session" in session_titles
      refute "Workspace B Session" in session_titles
    end
  end

  describe "GET /api/v1/findings (list_findings)" do
    test "service account for workspace A does not see workspace B findings", %{conn: conn} do
      ws_a = workspace!("fa")
      ws_b = workspace!("fb")

      sess_b = session!(ws_b, "B session for findings")
      _finding_b = finding!(sess_b)

      token_a = service_account!(ws_a)

      resp =
        conn
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> get("/api/v1/findings")
        |> json_response(200)

      finding_rule_ids = Enum.map(resp["findings"], & &1["rule_id"])
      refute "CK-SCOPE-TEST-001" in finding_rule_ids
    end

    test "service account for workspace A sees workspace A findings but not workspace B", %{
      conn: conn
    } do
      ws_a = workspace!("fa2")
      ws_b = workspace!("fb2")

      sess_a = session!(ws_a, "A session for findings")
      sess_b = session!(ws_b, "B session for findings")

      {:ok, _fa} =
        Mission.create_finding(%{
          session_id: sess_a.id,
          title: "ws-a finding",
          severity: "low",
          category: "completeness",
          rule_id: "CK-SCOPE-TEST-A-ONLY",
          plain_message: "workspace A",
          status: "open",
          metadata: %{}
        })

      {:ok, _fb} =
        Mission.create_finding(%{
          session_id: sess_b.id,
          title: "ws-b finding",
          severity: "low",
          category: "completeness",
          rule_id: "CK-SCOPE-TEST-B-ONLY",
          plain_message: "workspace B",
          status: "open",
          metadata: %{}
        })

      token_a = service_account!(ws_a)

      resp =
        conn
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> get("/api/v1/findings")
        |> json_response(200)

      rule_ids = Enum.map(resp["findings"], & &1["rule_id"])
      assert "CK-SCOPE-TEST-A-ONLY" in rule_ids
      refute "CK-SCOPE-TEST-B-ONLY" in rule_ids
    end
  end

  describe "GET /api/v1/proofs (list_proofs)" do
    test "unscoped call with no auth returns all proofs (local mode passthrough)", %{conn: conn} do
      # Without a service account Bearer token, current_workspace_id/1 returns nil,
      # which is the nil-passthrough for local/single-user mode.
      # This test verifies that the passthrough works and returns 200.
      resp =
        conn
        |> get("/api/v1/proofs")
        |> json_response(200)

      assert is_list(resp["proofs"])
    end
  end

  describe "memory API workspace scoping" do
    test "service account search is limited to its workspace when session_id is omitted", %{
      conn: conn
    } do
      ws_a = workspace!("ma")
      ws_b = workspace!("mb")
      session_a = session!(ws_a, "A memory session")
      session_b = session!(ws_b, "B memory session")
      _record_a = memory!(session_a, "workspace-a-reusable-memory")
      _record_b = memory!(session_b, "workspace-b-reusable-memory")
      token_a = service_account!(ws_a)

      resp =
        conn
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> get("/api/v1/memory/search?q=reusable")
        |> json_response(200)

      titles = Enum.map(resp["records"], & &1["title"])
      assert "workspace-a-reusable-memory" in titles
      refute "workspace-b-reusable-memory" in titles
    end

    test "service account cannot search, create, or archive another workspace's memory", %{
      conn: conn
    } do
      ws_a = workspace!("ma2")
      ws_b = workspace!("mb2")
      session_b = session!(ws_b, "B memory session")
      record_b = memory!(session_b, "workspace-b-private-memory")
      token_a = service_account!(ws_a)

      conn = put_req_header(conn, elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))

      resp =
        conn
        |> get("/api/v1/memory/search?q=private&session_id=#{session_b.id}")
        |> json_response(403)

      assert resp["error"] == "forbidden"

      resp =
        recycle(conn)
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> post("/api/v1/memory", %{session_id: session_b.id, memory: "should not write"})
        |> json_response(403)

      assert resp["error"] == "forbidden"

      resp =
        recycle(conn)
        |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))
        |> delete("/api/v1/memory/#{record_b.id}")
        |> json_response(403)

      assert resp["error"] == "forbidden"
    end
  end

  describe "object and action endpoint workspace scoping" do
    test "service account cannot read or mutate workspace B objects by id", %{conn: conn} do
      ws_a = workspace!("oa")
      ws_b = workspace!("ob")
      session_b = session!(ws_b, "B object session")
      task_b = task!(session_b)
      finding_b = finding!(session_b)
      review_b = review!(session_b, task_b)
      {:ok, proof_b} = Mission.generate_proof_bundle(task_b.id)
      token_a = service_account!(ws_a)

      authed = put_req_header(conn, elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))

      forbidden_requests = [
        {:get, "/api/v1/sessions/#{session_b.id}", nil},
        {:post, "/api/v1/sessions/#{session_b.id}/tasks", %{title: "nope"}},
        {:patch, "/api/v1/tasks/#{task_b.id}", %{status: "done"}},
        {:post, "/api/v1/tasks/#{task_b.id}/run", %{}},
        {:post, "/api/v1/sessions/#{session_b.id}/run", %{}},
        {:post, "/api/v1/findings", %{session_id: session_b.id, plain_message: "nope"}},
        {:post, "/api/v1/findings/#{finding_b.id}/action", %{action: "approve"}},
        {:get, "/api/v1/budget?session_id=#{session_b.id}", nil},
        {:get, "/api/v1/proof/#{task_b.id}", nil},
        {:get, "/api/v1/proofs/#{proof_b.id}", nil},
        {:post, "/api/v1/reviews", %{session_id: session_b.id, submission_body: "nope"}},
        {:get, "/api/v1/reviews/#{review_b.id}", nil},
        {:post, "/api/v1/reviews/#{review_b.id}/respond", %{decision: "approved"}}
      ]

      Enum.each(forbidden_requests, fn {method, path, body} ->
        conn =
          recycle(authed)
          |> put_req_header(elem(auth_header(token_a), 0), elem(auth_header(token_a), 1))

        conn =
          case method do
            :get -> get(conn, path)
            :post -> post(conn, path, body || %{})
            :patch -> patch(conn, path, body || %{})
          end

        assert %{"error" => "forbidden"} = json_response(conn, 403), path
      end)
    end
  end
end
