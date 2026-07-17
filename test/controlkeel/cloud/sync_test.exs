defmodule ControlKeel.Cloud.SyncTest do
  use ControlKeel.DataCase

  alias ControlKeel.Cloud.Sync
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Invocation, RollbackSnapshot, SessionEvent, TaskCheckpoint}

  defp workspace!(seed) do
    {:ok, ws} =
      Mission.create_workspace(%{
        name: "Sync-#{seed}",
        slug: "sync-#{seed}-#{System.unique_integer([:positive])}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    ws
  end

  defp session!(ws, title) do
    {:ok, s} =
      Mission.create_session(%{
        title: title,
        objective: "sync test",
        risk_tier: "low",
        budget_cents: 10_000,
        daily_budget_cents: 5_000,
        workspace_id: ws.id
      })

    s
  end

  defp finding!(session, rule_id, path \\ "lib/foo.ex") do
    {:ok, f} =
      Mission.create_finding(%{
        session_id: session.id,
        title: "test finding",
        severity: "medium",
        category: "code_quality",
        rule_id: rule_id,
        plain_message: "test",
        status: "open",
        metadata: %{"path" => path}
      })

    f
  end

  defp task!(session, title \\ "sync task") do
    {:ok, t} =
      Mission.create_task(%{
        session_id: session.id,
        title: title,
        status: "queued",
        position: 1,
        estimated_cost_cents: 10,
        metadata: %{},
        validation_gate: "approved"
      })

    t
  end

  defp invocation!(session, task) do
    {:ok, inv} =
      Mission.create_invocation(%{
        source: "test",
        tool: "ck_route",
        provider: "anthropic",
        model: "claude-sonnet",
        estimated_cost_cents: 50,
        decision: "allow",
        metadata: %{"trace" => "x"},
        session_id: session.id,
        task_id: task.id
      })

    inv
  end

  defp session_event!(session, task) do
    {:ok, ev} =
      %SessionEvent{}
      |> SessionEvent.changeset(%{
        event_type: "tool_call",
        actor: "agent",
        summary: "called ck_route",
        body: "tool output",
        payload: %{"tool" => "ck_route"},
        metadata: %{},
        session_id: session.id,
        task_id: task.id
      })
      |> Repo.insert()

    ev
  end

  defp task_checkpoint!(session, task) do
    {:ok, cp} =
      Mission.create_task_checkpoint(%{
        session_id: session.id,
        task_id: task.id,
        checkpoint_type: "resume",
        summary: "checkpoint",
        payload: %{"step" => 1},
        created_by: "test"
      })

    cp
  end

  defp rollback_snapshot!(session, task) do
    {:ok, snap} =
      %RollbackSnapshot{}
      |> RollbackSnapshot.changeset(%{
        session_id: session.id,
        task_id: task.id,
        commit_sha_before: "abc123",
        commit_sha_after: "def456",
        status: "available",
        rollback_method: "git_revert",
        metadata: %{}
      })
      |> Repo.insert()

    snap
  end

  defp proof_bundle!(_session, task) do
    {:ok, proof} = Mission.generate_proof_bundle(task.id)
    proof
  end

  describe "collect_unsynced/2" do
    test "returns unsynced findings for a workspace" do
      ws = workspace!("collect")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-001")

      result = Sync.collect_unsynced(ws.id)
      assert result.total >= 1

      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "finding" end)
      assert kind == "finding"
      assert record.id == f.id
      assert record.external_id != nil
      assert String.starts_with?(record.external_id, "f_")
    end

    test "excludes already-synced records" do
      ws = workspace!("synced")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-002")

      # Mark as synced
      f.__struct__.changeset(f, %{synced_at: DateTime.utc_now()})
      |> Repo.update!()

      result = Sync.collect_unsynced(ws.id)
      finding_records = Enum.filter(result.records, fn {k, _} -> k == "finding" end)
      assert Enum.find(finding_records, fn {_, r} -> r.id == f.id end) == nil
    end

    test "returns empty for workspace with no sessions" do
      ws = workspace!("empty")
      result = Sync.collect_unsynced(ws.id)
      assert result.total == 0
    end
  end

  describe "serialize_record/1" do
    test "produces a valid sync envelope" do
      ws = workspace!("serialize")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-003")

      envelope = Sync.serialize_record({"finding", f})

      assert envelope["external_id"] == f.external_id
      assert envelope["kind"] == "finding"
      assert is_map(envelope["payload"])
      assert envelope["idempotency_key"] != nil
    end
  end

  describe "upsert_batch/1" do
    test "inserts new records from cloud" do
      ws = workspace!("upsert")
      s = session!(ws, "S1")

      envelope = %{
        "external_id" => "f_TESTINSERT#{:rand.uniform(99_999)}",
        "kind" => "finding",
        "payload" => %{
          "title" => "from cloud",
          "severity" => "high",
          "category" => "security",
          "rule_id" => "CK-CLOUD-001",
          "plain_message" => "cloud finding",
          "status" => "open",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.inserted == 1
      assert result.skipped == 0

      # Second upsert with no updated_at: append-only "not newer" → no_change
      assert {:ok, result2} = Sync.upsert_batch([envelope])
      assert result2.no_change == 1
    end

    test "applies cloud-side update when payload's updated_at is newer (closes CK-CLOUD-SYNC-003)" do
      ws = workspace!("update")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-UPDATE")

      # Push once so the record has a known updated_at, then simulate cloud
      # mutating status with a strictly newer updated_at.
      newer = DateTime.add(f.updated_at, 60, :second) |> DateTime.to_iso8601()

      envelope = %{
        "external_id" => f.external_id,
        "kind" => "finding",
        "payload" => %{
          "title" => f.title,
          "severity" => f.severity,
          "category" => f.category,
          "rule_id" => f.rule_id,
          "plain_message" => f.plain_message,
          "status" => "blocked",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id,
          "updated_at" => newer
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.updated == 1

      refreshed = Repo.get!(ControlKeel.Mission.Finding, f.id)
      assert refreshed.status == "blocked"
    end

    test "imports a remote session into the target local workspace" do
      target_ws = workspace!("target-import")

      envelope = %{
        "external_id" => "ses_legacy_#{System.unique_integer([:positive])}",
        "kind" => "session",
        "payload" => %{
          "workspace_id" => 999_999,
          "title" => "imported session",
          "objective" => "remote migration",
          "risk_tier" => "low",
          "status" => "active",
          "budget_cents" => 1000,
          "daily_budget_cents" => 1000,
          "spent_cents" => 0,
          "execution_brief" => "",
          "metadata" => %{},
          "lock_version" => 2
        }
      }

      assert {:ok, %{inserted: 1}} =
               Sync.upsert_batch([envelope], target_workspace_id: target_ws.id)

      imported = Repo.get_by!(ControlKeel.Mission.Session, external_id: envelope["external_id"])
      assert imported.workspace_id == target_ws.id
      assert imported.title == "imported session"
    end

    test "resolves session_external_id refs instead of trusting remote numeric session_id" do
      ws = workspace!("portable-ref")
      session = session!(ws, "local target session")

      envelope = %{
        "external_id" => "f_REMOTE_REF_#{System.unique_integer([:positive])}",
        "kind" => "finding",
        "refs" => %{"session_external_id" => session.external_id},
        "payload" => %{
          "session_id" => 999_999,
          "title" => "portable finding",
          "severity" => "medium",
          "category" => "migration",
          "rule_id" => "CK-MIGRATE-REF",
          "plain_message" => "attached by external ref",
          "status" => "open",
          "auto_resolved" => false,
          "metadata" => %{}
        }
      }

      assert {:ok, %{inserted: 1}} = Sync.upsert_batch([envelope])

      imported = Repo.get_by!(ControlKeel.Mission.Finding, external_id: envelope["external_id"])
      assert imported.session_id == session.id
    end

    test "serialized child records include portable session refs" do
      ws = workspace!("serialize-ref")
      session = session!(ws, "session ref")
      finding = finding!(session, "CK-SYNC-REF")

      envelope = Sync.serialize_record({"finding", finding})

      assert envelope["refs"] == %{"session_external_id" => session.external_id}
    end

    test "rejects unknown kind" do
      envelope = %{
        "external_id" => "unknown_123",
        "kind" => "nonexistent",
        "payload" => %{}
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.skipped == 1
    end

    test "rejects batch exceeding max_batch_bytes" do
      big = String.duplicate("x", 64)

      envelopes =
        for i <- 1..50 do
          %{
            "external_id" => "f_BIG#{i}",
            "kind" => "finding",
            "payload" => %{"blob" => String.duplicate(big, 256)}
          }
        end

      assert {:error, {:batch_too_large, %{bytes: _, max: _}}} =
               Sync.upsert_batch(envelopes, max_batch_bytes: 1024)
    end
  end

  describe "mark_synced/1" do
    test "sets synced_at on records" do
      ws = workspace!("mark")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-004")

      assert f.synced_at == nil

      Sync.mark_synced([{"finding", f}])

      refreshed = Repo.get!(ControlKeel.Mission.Finding, f.id)
      assert refreshed.synced_at != nil
    end
  end

  # ── Newly-wired append-only schemas ──────────────────────────────────

  describe "append-only schema registry" do
    test "invocations, proof_bundles, session_events, task_checkpoints, and rollback_snapshots are syncable" do
      kinds =
        Sync.syncable_schemas()
        |> Enum.map(fn {k, _} -> k end)

      for k <- [
            "invocation",
            "proof_bundle",
            "session_event",
            "task_checkpoint",
            "rollback_snapshot"
          ] do
        assert k in kinds
      end
    end

    test "all five behave as append-only (lock_version in payload is ignored)" do
      ws = workspace!("append-only")
      s = session!(ws, "S1")
      t = task!(s)
      inv = invocation!(s, t)

      # An editable record with a higher lock_version would be accepted as an
      # update.  An append-only record without a newer updated_at is no_change
      # regardless of lock_version.
      envelope =
        Sync.serialize_record({"invocation", inv})
        |> Map.update!("payload", &Map.put(&1, "lock_version", 999))

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.updated == 0
    end
  end

  describe "collect_unsynced/2 — newly-wired schemas" do
    test "collects unsynced invocations" do
      ws = workspace!("inv-collect")
      s = session!(ws, "S1")
      t = task!(s)
      inv = invocation!(s, t)

      result = Sync.collect_unsynced(ws.id)
      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "invocation" end)
      assert kind == "invocation"
      assert record.id == inv.id
      assert String.starts_with?(record.external_id, "inv_")
    end

    test "collects unsynced session_events" do
      ws = workspace!("se-collect")
      s = session!(ws, "S1")
      t = task!(s)
      ev = session_event!(s, t)

      result = Sync.collect_unsynced(ws.id)

      {kind, record} =
        Enum.find(result.records, fn {k, r} -> k == "session_event" and r.id == ev.id end)

      assert kind == "session_event"
      assert record.id == ev.id
      assert String.starts_with?(record.external_id, "se_")
    end

    test "collects unsynced task_checkpoints" do
      ws = workspace!("tc-collect")
      s = session!(ws, "S1")
      t = task!(s)
      cp = task_checkpoint!(s, t)

      result = Sync.collect_unsynced(ws.id)
      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "task_checkpoint" end)
      assert kind == "task_checkpoint"
      assert record.id == cp.id
      assert String.starts_with?(record.external_id, "tc_")
    end

    test "collects unsynced rollback_snapshots" do
      ws = workspace!("rs-collect")
      s = session!(ws, "S1")
      t = task!(s)
      snap = rollback_snapshot!(s, t)

      result = Sync.collect_unsynced(ws.id)
      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "rollback_snapshot" end)
      assert kind == "rollback_snapshot"
      assert record.id == snap.id
      assert String.starts_with?(record.external_id, "rs_")
    end

    test "collects unsynced proof_bundles" do
      ws = workspace!("pb-collect")
      s = session!(ws, "S1")
      t = task!(s, "proof task")
      {:ok, proof} = Mission.generate_proof_bundle(t.id)

      result = Sync.collect_unsynced(ws.id)
      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "proof_bundle" end)
      assert kind == "proof_bundle"
      assert record.id == proof.id
      assert String.starts_with?(record.external_id, "pb_")
    end
  end

  describe "serialize_record/1 — newly-wired schemas" do
    test "serializes an invocation with redacted metadata" do
      ws = workspace!("inv-ser")
      s = session!(ws, "S1")
      t = task!(s)

      {:ok, inv} =
        Mission.create_invocation(%{
          source: "test",
          tool: "ck_route",
          provider: "anthropic",
          model: "claude-sonnet",
          estimated_cost_cents: 50,
          decision: "allow",
          metadata: %{"api_key" => "sk-ant-test-key-1234567890abcdef"},
          session_id: s.id,
          task_id: t.id
        })

      envelope = Sync.serialize_record({"invocation", inv})

      assert envelope["kind"] == "invocation"
      assert envelope["external_id"] == inv.external_id
      # The redactor scrubs sk-ant-* patterns in {:redact, :metadata} fields.
      assert envelope["payload"]["metadata"]["api_key"] == "[REDACTED:sk-ant]"
      assert envelope["refs"]["session_external_id"] == s.external_id
    end

    test "serializes a session_event with redacted body" do
      ws = workspace!("se-ser")
      s = session!(ws, "S1")
      t = task!(s)

      {:ok, ev} =
        %SessionEvent{}
        |> SessionEvent.changeset(%{
          event_type: "tool_call",
          actor: "agent",
          summary: "called ck_route",
          body: "Authorization: Bearer sk-ant-leaked-key-1234567890",
          payload: %{"tool" => "ck_route"},
          metadata: %{},
          session_id: s.id,
          task_id: t.id
        })
        |> Repo.insert()

      envelope = Sync.serialize_record({"session_event", ev})

      assert envelope["kind"] == "session_event"
      # The redactor scrubs Authorization/Bearer patterns in {:redact, :body}.
      assert String.contains?(envelope["payload"]["body"], "[REDACTED]")
      refute String.contains?(envelope["payload"]["body"], "sk-ant-leaked-key")
    end
  end

  describe "upsert_batch/1 — newly-wired schemas" do
    test "inserts a new invocation from cloud" do
      ws = workspace!("inv-upsert")
      s = session!(ws, "S1")
      t = task!(s)

      envelope = %{
        "external_id" => "inv_CLOUD_#{System.unique_integer([:positive])}",
        "kind" => "invocation",
        "payload" => %{
          "source" => "cloud",
          "tool" => "ck_validate",
          "provider" => "openai",
          "model" => "gpt-4",
          "estimated_cost_cents" => 30,
          "decision" => "allow",
          "metadata" => %{},
          "session_id" => s.id,
          "task_id" => t.id
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.inserted == 1

      imported = Repo.get_by!(Invocation, external_id: envelope["external_id"])
      assert imported.tool == "ck_validate"
    end

    test "inserts a new session_event from cloud via session_external_id ref" do
      ws = workspace!("se-upsert")
      s = session!(ws, "S1")

      envelope = %{
        "external_id" => "se_CLOUD_#{System.unique_integer([:positive])}",
        "kind" => "session_event",
        "refs" => %{"session_external_id" => s.external_id},
        "payload" => %{
          "event_type" => "decision",
          "actor" => "cloud",
          "summary" => "cloud decision",
          "body" => "",
          "payload" => %{},
          "metadata" => %{},
          "session_id" => 999_999
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.inserted == 1

      imported = Repo.get_by!(SessionEvent, external_id: envelope["external_id"])
      assert imported.session_id == s.id
    end

    test "inserts a new task_checkpoint from cloud" do
      ws = workspace!("tc-upsert")
      s = session!(ws, "S1")
      t = task!(s)

      envelope = %{
        "external_id" => "tc_CLOUD_#{System.unique_integer([:positive])}",
        "kind" => "task_checkpoint",
        "payload" => %{
          "session_id" => s.id,
          "task_id" => t.id,
          "checkpoint_type" => "resume",
          "summary" => "cloud checkpoint",
          "payload" => %{},
          "created_by" => "cloud"
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.inserted == 1

      imported = Repo.get_by!(TaskCheckpoint, external_id: envelope["external_id"])
      assert imported.summary == "cloud checkpoint"
    end

    test "inserts a new rollback_snapshot from cloud" do
      ws = workspace!("rs-upsert")
      s = session!(ws, "S1")
      t = task!(s)

      envelope = %{
        "external_id" => "rs_CLOUD_#{System.unique_integer([:positive])}",
        "kind" => "rollback_snapshot",
        "payload" => %{
          "session_id" => s.id,
          "task_id" => t.id,
          "commit_sha_before" => "aaa",
          "commit_sha_after" => "bbb",
          "status" => "available",
          "rollback_method" => "git_revert",
          "metadata" => %{}
        }
      }

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.inserted == 1

      imported = Repo.get_by!(RollbackSnapshot, external_id: envelope["external_id"])
      assert imported.commit_sha_before == "aaa"
    end

    test "idempotent: re-upserting the same invocation is no_change" do
      ws = workspace!("inv-idem")
      s = session!(ws, "S1")
      t = task!(s)
      inv = invocation!(s, t)

      envelope = Sync.serialize_record({"invocation", inv})

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.inserted == 0
    end

    test "idempotent: re-upserting the same proof_bundle is no_change" do
      ws = workspace!("pb-idem")
      s = session!(ws, "S1")
      t = task!(s, "proof task")
      proof = proof_bundle!(s, t)

      envelope = Sync.serialize_record({"proof_bundle", proof})

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.inserted == 0
    end

    test "idempotent: re-upserting the same session_event is no_change" do
      ws = workspace!("se-idem")
      s = session!(ws, "S1")
      t = task!(s)
      ev = session_event!(s, t)

      envelope = Sync.serialize_record({"session_event", ev})

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.inserted == 0
    end

    test "idempotent: re-upserting the same task_checkpoint is no_change" do
      # TaskCheckpoint uses timestamps(updated_at: false) — the update_append_only
      # path must not crash on the missing :updated_at struct field.
      ws = workspace!("tc-idem")
      s = session!(ws, "S1")
      t = task!(s)
      cp = task_checkpoint!(s, t)

      envelope = Sync.serialize_record({"task_checkpoint", cp})

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.inserted == 0
    end

    test "idempotent: re-upserting the same rollback_snapshot is no_change" do
      ws = workspace!("rs-idem")
      s = session!(ws, "S1")
      t = task!(s)
      snap = rollback_snapshot!(s, t)

      envelope = Sync.serialize_record({"rollback_snapshot", snap})

      assert {:ok, result} = Sync.upsert_batch([envelope])
      assert result.no_change == 1
      assert result.inserted == 0
    end
  end

  describe "mark_synced/1 — newly-wired schemas" do
    test "sets synced_at on invocations and session_events" do
      ws = workspace!("mark-new")
      s = session!(ws, "S1")
      t = task!(s)
      inv = invocation!(s, t)
      ev = session_event!(s, t)

      assert inv.synced_at == nil
      assert ev.synced_at == nil

      Sync.mark_synced([{"invocation", inv}, {"session_event", ev}])

      assert Repo.get!(Invocation, inv.id).synced_at != nil
      assert Repo.get!(SessionEvent, ev.id).synced_at != nil
    end
  end

  # ── Legacy backfill compatibility ────────────────────────────────────
  #
  # Simulates an upgrade from an older schema version: rows exist in the
  # five new syncable tables with external_id stamped by the migration's
  # backfill (``<prefix>legacy_<id>``) rather than by the changeset's
  # maybe_generate_external_id.  These rows must still be collectable and
  # serializable so historical data is not lost when an existing user
  # upgrades and runs their first cloud sync.

  describe "legacy backfill rows (pre-upgrade compatibility)" do
    test "rows with legacy-prefixed external_id are collected and serialized" do
      ws = workspace!("legacy")
      s = session!(ws, "S1")
      t = task!(s)

      # Insert rows directly, bypassing the changeset's external_id
      # generation, then stamp a legacy external_id the way the migration
      # backfill does.  synced_at stays nil so collect_unsynced picks them up.
      {:ok, inv} =
        %Invocation{}
        |> Invocation.changeset(%{
          source: "legacy",
          tool: "ck_route",
          provider: "anthropic",
          model: "claude-sonnet",
          estimated_cost_cents: 10,
          decision: "allow",
          metadata: %{},
          session_id: s.id,
          task_id: t.id
        })
        |> Repo.insert()

      inv = Repo.update!(Ecto.Changeset.change(inv, external_id: "inv_legacy_#{inv.id}"))

      {:ok, ev} =
        %SessionEvent{}
        |> SessionEvent.changeset(%{
          event_type: "tool_call",
          actor: "agent",
          summary: "legacy event",
          body: "",
          payload: %{},
          metadata: %{},
          session_id: s.id,
          task_id: t.id
        })
        |> Repo.insert()

      ev = Repo.update!(Ecto.Changeset.change(ev, external_id: "se_legacy_#{ev.id}"))

      {:ok, cp} =
        %TaskCheckpoint{}
        |> TaskCheckpoint.changeset(%{
          session_id: s.id,
          task_id: t.id,
          checkpoint_type: "resume",
          summary: "legacy checkpoint",
          payload: %{},
          created_by: "system"
        })
        |> Repo.insert()

      cp = Repo.update!(Ecto.Changeset.change(cp, external_id: "tc_legacy_#{cp.id}"))

      {:ok, snap} =
        %RollbackSnapshot{}
        |> RollbackSnapshot.changeset(%{
          session_id: s.id,
          task_id: t.id,
          commit_sha_before: "aaa",
          commit_sha_after: "bbb",
          status: "available",
          rollback_method: "git_revert",
          metadata: %{}
        })
        |> Repo.insert()

      snap = Repo.update!(Ecto.Changeset.change(snap, external_id: "rs_legacy_#{snap.id}"))

      result = Sync.collect_unsynced(ws.id)

      # All four legacy rows are collected.
      collected_ids = Enum.map(result.records, fn {_, r} -> r.id end)
      assert inv.id in collected_ids
      assert ev.id in collected_ids
      assert cp.id in collected_ids
      assert snap.id in collected_ids

      # Each serializes to an envelope with a non-nil external_id — the
      # cloud-side upsert would otherwise skip them (missing_external_id).
      for {kind, record} <- result.records,
          kind in ["invocation", "session_event", "task_checkpoint", "rollback_snapshot"] do
        envelope = Sync.serialize_record({kind, record})
        assert envelope["external_id"] != nil, "#{kind} external_id must not be nil"
        assert String.starts_with?(envelope["external_id"], String.at(kind, 0))
      end
    end
  end
end
