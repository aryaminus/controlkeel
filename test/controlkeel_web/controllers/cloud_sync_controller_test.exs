defmodule ControlKeelWeb.CloudSyncControllerTest do
  use ControlKeelWeb.ConnCase

  alias ControlKeel.Cloud.{AuthToken, Sync, Workspace.KeyRegistry}
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.SessionDigest
  alias ControlKeel.Repo

  import ControlKeel.MissionFixtures

  defp enroll_workspace!(workspace) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    public_key_b64 = Base.encode64(public_key)
    private_key_b64 = Base.encode64(private_key)
    workspace_id = "ws_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {:ok, fingerprint} = KeyRegistry.fingerprint_for(public_key_b64)

    {:ok, _key} =
      KeyRegistry.enroll(%{
        workspace_id: workspace_id,
        public_key: public_key_b64,
        algorithm: "ed25519",
        fingerprint: fingerprint,
        name: "test workspace",
        mission_workspace_id: workspace.id
      })

    {:ok, token} = AuthToken.sign(%{workspace_id: workspace_id, private_key: private_key_b64})
    %{workspace_id: workspace_id, token: token}
  end

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "POST /cloud/v1/sync/push" do
    test "upserts scoped records idempotently and rejects workspace mismatch", %{conn: conn} do
      workspace = workspace_fixture()
      session = session_fixture(%{workspace: workspace})
      enrollment = enroll_workspace!(workspace)
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      envelope = %{
        "kind" => "finding",
        "external_id" => "f_cloud_scope_1",
        "sync_protocol_version" => Sync.protocol_version(),
        "payload" => %{
          "external_id" => "f_cloud_scope_1",
          "session_id" => session.id,
          "title" => "Cloud scoped finding",
          "severity" => "high",
          "category" => "security",
          "rule_id" => "cloud.scope",
          "plain_message" => "cloud finding",
          "status" => "open",
          "auto_resolved" => false,
          "metadata" => %{},
          "inserted_at" => now,
          "updated_at" => now
        }
      }

      resp =
        conn
        |> authed(enrollment.token)
        |> post("/cloud/v1/sync/push", %{
          "workspace_id" => enrollment.workspace_id,
          "records" => [envelope]
        })
        |> json_response(200)

      assert resp["accepted"] == 1
      assert resp["inserted"] == 1

      resp =
        build_conn()
        |> authed(enrollment.token)
        |> post("/cloud/v1/sync/push", %{
          "workspace_id" => enrollment.workspace_id,
          "records" => [envelope]
        })
        |> json_response(200)

      assert resp["accepted"] == 1
      assert resp["no_change"] == 1

      resp =
        build_conn()
        |> authed(enrollment.token)
        |> post("/cloud/v1/sync/push", %{"workspace_id" => "ws_wrong", "records" => [envelope]})
        |> json_response(403)

      assert resp["error"] == "workspace_id mismatch"
    end
  end

  describe "POST /cloud/v1/sync/pull" do
    test "returns redacted scoped findings reviews digests and memory records", %{conn: conn} do
      workspace = workspace_fixture()
      other_workspace = workspace_fixture()
      session = session_fixture(%{workspace: workspace})
      other_session = session_fixture(%{workspace: other_workspace})
      task = task_fixture(%{session: session})
      enrollment = enroll_workspace!(workspace)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      finding =
        finding_fixture(%{session: session, plain_message: "Authorization: Bearer secret-token"})

      {:ok, review} =
        Mission.submit_review(%{
          "session_id" => session.id,
          "task_id" => task.id,
          "review_type" => "plan",
          "title" => "Cloud sync review",
          "submission_body" => "token=secret-token"
        })

      {:ok, digest} =
        %SessionDigest{}
        |> SessionDigest.changeset(%{
          session_id: session.id,
          digest_type: "session",
          period_start: now,
          period_end: now,
          generated_at: now,
          highlights: %{"note" => "Authorization: Bearer secret-token"},
          synced_at: now
        })
        |> Repo.insert()

      {:ok, memory} =
        Memory.record(%{
          workspace_id: workspace.id,
          session_id: session.id,
          record_type: "decision",
          title: "Cloud sync memory",
          summary: "memory",
          body: "Authorization: Bearer secret-token",
          source_type: "test",
          source_id: "cloud-sync-memory",
          synced_at: now
        })

      _other_memory =
        Memory.record(%{
          workspace_id: other_workspace.id,
          session_id: other_session.id,
          record_type: "decision",
          title: "Other workspace memory",
          summary: "other",
          source_type: "test",
          source_id: "cloud-sync-other-memory",
          synced_at: now
        })

      Enum.each([finding, review], fn record ->
        record
        |> Ecto.Changeset.change(%{synced_at: now})
        |> Repo.update!()
      end)

      resp =
        conn
        |> authed(enrollment.token)
        |> post("/cloud/v1/sync/pull", %{
          "workspace_id" => enrollment.workspace_id,
          "since" => DateTime.add(now, -60, :second) |> DateTime.to_iso8601()
        })
        |> json_response(200)

      kinds = Enum.map(resp["records"], & &1["kind"])
      assert "finding" in kinds
      assert "review" in kinds
      assert "session_digest" in kinds
      assert "memory_record" in kinds

      external_ids = Enum.map(resp["records"], & &1["external_id"])
      assert finding.external_id in external_ids
      assert review.external_id in external_ids
      assert digest.external_id in external_ids
      assert memory.external_id in external_ids
      refute Enum.any?(resp["records"], &(&1["payload"]["title"] == "Other workspace memory"))

      encoded = Jason.encode!(resp)
      refute encoded =~ "secret-token"
      refute encoded =~ "Bearer secret"
    end

    test "returns all 9 append-only kinds including invocations, proof_bundles, session_events, task_checkpoints, and rollback_snapshots",
         %{
           conn: conn
         } do
      workspace = workspace_fixture()
      session = session_fixture(%{workspace: workspace})
      task = task_fixture(%{session: session})
      enrollment = enroll_workspace!(workspace)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, invocation} =
        Mission.create_invocation(%{
          source: "test",
          tool: "ck_route",
          provider: "anthropic",
          model: "claude-sonnet",
          estimated_cost_cents: 50,
          decision: "allow",
          metadata: %{},
          session_id: session.id,
          task_id: task.id
        })

      {:ok, proof} = Mission.generate_proof_bundle(task.id)

      {:ok, event} =
        %ControlKeel.Mission.SessionEvent{}
        |> ControlKeel.Mission.SessionEvent.changeset(%{
          event_type: "tool_call",
          actor: "agent",
          summary: "called ck_route",
          body: "",
          payload: %{},
          metadata: %{},
          session_id: session.id,
          task_id: task.id
        })
        |> Repo.insert()

      {:ok, checkpoint} =
        Mission.create_task_checkpoint(%{
          session_id: session.id,
          task_id: task.id,
          checkpoint_type: "resume",
          summary: "checkpoint",
          payload: %{},
          created_by: "test"
        })

      {:ok, snapshot} =
        %ControlKeel.Mission.RollbackSnapshot{}
        |> ControlKeel.Mission.RollbackSnapshot.changeset(%{
          session_id: session.id,
          task_id: task.id,
          commit_sha_before: "abc123",
          commit_sha_after: "def456",
          status: "available",
          rollback_method: "git_revert",
          metadata: %{}
        })
        |> Repo.insert()

      # Stamp synced_at so the pull query (synced_at > since) returns them.
      Enum.each([invocation, proof, event, checkpoint, snapshot], fn record ->
        record
        |> Ecto.Changeset.change(%{synced_at: now})
        |> Repo.update!()
      end)

      resp =
        conn
        |> authed(enrollment.token)
        |> post("/cloud/v1/sync/pull", %{
          "workspace_id" => enrollment.workspace_id,
          "since" => DateTime.add(now, -60, :second) |> DateTime.to_iso8601()
        })
        |> json_response(200)

      kinds = Enum.map(resp["records"], & &1["kind"])

      for kind <-
            ~w(invocation proof_bundle session_event task_checkpoint rollback_snapshot) do
        assert kind in kinds, "expected #{kind} in pull response kinds: #{inspect(kinds)}"
      end

      external_ids = Enum.map(resp["records"], & &1["external_id"])
      assert invocation.external_id in external_ids
      assert proof.external_id in external_ids
      assert event.external_id in external_ids
      assert checkpoint.external_id in external_ids
      assert snapshot.external_id in external_ids
    end
  end
end
