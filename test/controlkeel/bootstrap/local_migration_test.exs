defmodule ControlKeel.Bootstrap.LocalMigrationTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Analytics.Event, as: AnalyticsEvent
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Bootstrap.LocalMigration
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Repo

  setup do
    reset_migration_state!()
    :ok
  end

  describe "run/0 in local mode" do
    test "consolidates orphan workspaces into the default org/workspace, keeping leftovers" do
      ws_a = workspace_fixture(%{name: "Project A", slug: "project-a"})
      ws_b = workspace_fixture(%{name: "Project B", slug: "project-b"})
      session_a = session_fixture(%{workspace: ws_a})
      session_b = session_fixture(%{workspace: ws_b})

      assert is_integer(ws_a.org_id)
      assert is_integer(ws_b.org_id)
      sessions_before = Repo.aggregate(Session, :count)

      assert {:ok, summary} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      default_ws = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

      assert default_org
      assert default_ws
      assert default_ws.org_id == default_org.id

      # both sessions end up under the default workspace
      assert Repo.get(Session, session_a.id).workspace_id == default_ws.id
      assert Repo.get(Session, session_b.id).workspace_id == default_ws.id

      # the oldest workspace (ws_a) was repurposed into the default
      assert Repo.get(Workspace, ws_a.id).slug == "default-workspace"

      # the leftover workspace and its org are kept — NOT deleted
      assert Repo.get(Workspace, ws_b.id)
      assert Repo.aggregate(Workspace, :count) == 2
      assert Repo.aggregate(Org, :count) == 2

      # zero sessions lost
      assert Repo.aggregate(Session, :count) == sessions_before
      assert summary.sessions_moved == 1
      assert summary.orphan_workspaces == 1
      assert summary.orphan_orgs == 1
      assert Map.get(summary, :removed_workspaces, 0) == 0
      assert Map.get(summary, :removed_orgs, 0) == 0
    end

    test "with multiple orgs, the oldest becomes defaults and the rest are kept as orphans" do
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org(%{name: "Org B", slug: "org-b"})
      {:ok, org_c} = Accounts.create_org(%{name: "Org C", slug: "org-c"})

      assert {:ok, summary} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

      # org_a is oldest; it becomes the default and keeps its row identity
      assert default_org.id == org_a.id
      assert Repo.get(Accounts.Org, org_a.id).slug == LocalDefaults.default_org_slug()

      # the other orgs RETAIN their rows as orphans (not deleted)
      assert Repo.get(Accounts.Org, org_b.id)
      assert Repo.get(Accounts.Org, org_c.id)
      assert Repo.aggregate(Org, :count) == 3
      assert summary.orphan_orgs == 2
      assert Map.get(summary, :removed_orgs, 0) == 0
    end

    test "repoints session-scoped memory and analytics onto the default workspace" do
      workspace = workspace_fixture(%{name: "Legacy", slug: "legacy-ws"})
      session = session_fixture(%{workspace: workspace})

      {:ok, memory} = insert_memory_record(session, workspace)
      {:ok, event} = insert_analytics_event(session, workspace)

      assert {:ok, _} = LocalMigration.run()

      default_ws = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

      assert Repo.get(MemoryRecord, memory.id).workspace_id == default_ws.id
      assert Repo.get(AnalyticsEvent, event.id).workspace_id == default_ws.id
    end

    test "claims an existing default-workspace slug for the default org" do
      {:ok, other_org} =
        Accounts.create_org(%{name: "Other", slug: "other-org"})

      {:ok, existing_default} =
        Mission.create_workspace(%{
          name: "Default Workspace",
          slug: LocalDefaults.default_workspace_slug(),
          industry: "general",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: other_org.id
        })

      session = session_fixture(%{workspace: existing_default})

      assert {:ok, _} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

      # the pre-existing default-workspace was claimed for the default org
      assert Repo.get(Workspace, existing_default.id).org_id == default_org.id
      # the other org was renamed into the default
      assert Repo.get(Accounts.Org, other_org.id).slug == LocalDefaults.default_org_slug()
      # the session survived and stays under the (now default) workspace
      assert Repo.get(Session, session.id).workspace_id == existing_default.id
    end

    test "is idempotent: a second run is a no-op once the DB matches the architecture" do
      workspace = workspace_fixture(%{name: "Solo", slug: "solo-ws"})
      session_fixture(%{workspace: workspace})

      assert {:ok, %{} = first} = LocalMigration.run()
      assert first.sessions_moved == 0

      # After consolidation the DB has a single default org/workspace, so the
      # data-shape gate short-circuits the second run.
      assert {:ok, :already_reconciled} = LocalMigration.run()
    end

    test "is a no-op when the database already matches the default architecture" do
      {:ok, {_org, _workspace}} = ControlKeel.Bootstrap.LocalDefaults.ensure()

      sessions_before = Repo.aggregate(Session, :count)
      orgs_before = Repo.aggregate(Org, :count)
      workspaces_before = Repo.aggregate(Workspace, :count)

      assert {:ok, :already_reconciled} = LocalMigration.run()

      # nothing created, moved, or deleted
      assert Repo.aggregate(Session, :count) == sessions_before
      assert Repo.aggregate(Org, :count) == orgs_before
      assert Repo.aggregate(Workspace, :count) == workspaces_before
    end

    test "provisions the defaults when they are missing" do
      assert {:ok, summary} = LocalMigration.run()

      assert Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      assert Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())
      assert summary.sessions_moved == 0
      assert summary.orphan_workspaces == 0
      assert summary.orphan_orgs == 0
    end
  end

  describe "orphan cleanup policy" do
    test "cleanup: :keep leaves multiple orphan workspaces/orgs untouched" do
      ws_a = workspace_fixture(%{name: "Project A", slug: "project-a"})
      ws_b = workspace_fixture(%{name: "Project B", slug: "project-b"})
      session_fixture(%{workspace: ws_a})
      session_fixture(%{workspace: ws_b})

      assert {:ok, summary} = LocalMigration.run(cleanup: :keep)

      assert summary.orphan_workspaces == 1
      assert summary.orphan_orgs == 1
      assert Map.get(summary, :removed_workspaces, 0) == 0
      assert Repo.aggregate(Workspace, :count) == 2
    end

    test "cleanup: :delete removes all orphan workspaces and orgs after evacuation" do
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org(%{name: "Org B", slug: "org-b"})

      ws_a = workspace_fixture(%{name: "WS A", slug: "ws-a", org_id: org_a.id})
      ws_b = workspace_fixture(%{name: "WS B", slug: "ws-b", org_id: org_b.id})
      session_a = session_fixture(%{workspace: ws_a})
      session_b = session_fixture(%{workspace: ws_b})

      sessions_before = Repo.aggregate(Session, :count)
      assert is_nil(Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug()))

      assert {:ok, summary} = LocalMigration.run(cleanup: :delete)

      default_ws = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

      # sessions evacuated into the default workspace, none lost
      assert Repo.aggregate(Session, :count) == sessions_before
      assert Repo.get(Session, session_a.id).workspace_id == default_ws.id
      assert Repo.get(Session, session_b.id).workspace_id == default_ws.id

      # only the default workspace and default org remain
      assert Repo.aggregate(Workspace, :count) == 1
      assert Repo.aggregate(Org, :count) == 1
      assert summary.orphan_workspaces == 0
      assert summary.orphan_orgs == 0
      assert summary.removed_workspaces == 1
      assert summary.removed_orgs == 1
    end

    test "cleanup: :ask prompts outside the write transaction and honors a :delete answer" do
      ws_a = workspace_fixture(%{name: "WS A", slug: "ask-ws-a"})
      ws_b = workspace_fixture(%{name: "WS B", slug: "ask-ws-b"})
      session_fixture(%{workspace: ws_a})
      session_fixture(%{workspace: ws_b})

      prompt =
        fn counts ->
          # the prompt must run BEFORE the write transaction (reconcile) opens,
          # so no default org/workspace exists yet, and receives the read-only
          # pre-pass orphan counts
          assert is_nil(Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug()))
          refute Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
          assert counts.orphan_workspaces == 1
          assert counts.orphan_orgs == 1
          :delete
        end

      assert {:ok, summary} = LocalMigration.run(cleanup: :ask, prompt: prompt)

      # the prompt returned :delete, so the orphaned workspace was removed
      assert summary.orphan_workspaces == 0
      assert summary.removed_workspaces == 1
      assert Repo.aggregate(Workspace, :count) == 1
    end

    test "cleanup: :ask keeps orphans when the prompt says so" do
      ws_a = workspace_fixture(%{name: "WS A", slug: "keep-ws-a"})
      ws_b = workspace_fixture(%{name: "WS B", slug: "keep-ws-b"})
      session_fixture(%{workspace: ws_a})
      session_fixture(%{workspace: ws_b})

      assert {:ok, summary} = LocalMigration.run(cleanup: :ask, prompt: fn _ -> :keep end)

      assert summary.orphan_workspaces == 1
      assert Map.get(summary, :removed_workspaces, 0) == 0
      assert Repo.aggregate(Workspace, :count) == 2
    end

    test "cleanup: :ask does not invoke the prompt when nothing is orphaned" do
      {:ok, org} = Accounts.create_org(%{name: "Solo Org", slug: "solo-org"})

      workspace_fixture(%{
        name: "Solo WS",
        slug: "solo-ws",
        org_id: org.id
      })

      session_fixture(%{workspace: Mission.get_workspace_by_slug("solo-ws")})

      assert {:ok, summary} =
               LocalMigration.run(
                 cleanup: :ask,
                 prompt: fn _ -> raise "prompt must not be called with no orphans" end
               )

      assert summary.orphan_workspaces == 0
      assert summary.orphan_orgs == 0
      assert Map.get(summary, :removed_workspaces, 0) == 0
      assert Map.get(summary, :removed_orgs, 0) == 0
    end
  end

  describe "run/0 outside local mode" do
    test "is a no-op and touches nothing" do
      Application.put_env(:controlkeel, :local_defaults_local_mode_fn, fn -> false end)
      on_exit(fn -> Application.delete_env(:controlkeel, :local_defaults_local_mode_fn) end)

      workspace = workspace_fixture(%{name: "Untouched", slug: "untouched-ws"})
      session_fixture(%{workspace: workspace})

      assert {:ok, :skipped_not_local} = LocalMigration.run()

      # no default org/workspace created, no workspaces deleted
      refute Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      assert Repo.get(Workspace, workspace.id)
    end
  end

  describe "render/1 and to_payload/1 (update notification)" do
    test "render reports sessions + orphans kept when cleanup kept orphans" do
      lines =
        LocalMigration.render(%{
          sessions_moved: 3,
          orphan_workspaces: 2,
          orphan_orgs: 1
        })

      assert Enum.join(lines, "\n") =~ "Moved 3 session(s) into the Default Workspace."
      assert Enum.join(lines, "\n") =~ "Left 2 leftover workspace(s) and 1 leftover org(s)"
    end

    test "render reports removal counts when orphans were deleted" do
      lines =
        LocalMigration.render(%{
          sessions_moved: 1,
          orphan_workspaces: 0,
          orphan_orgs: 0,
          removed_workspaces: 2,
          removed_orgs: 1
        })

      assert Enum.join(lines, "\n") =~ "Moved 1 session(s) into the Default Workspace."
      assert Enum.join(lines, "\n") =~ "Deleted 2 leftover workspace(s) and 1 leftover org(s)."
    end

    test "render stays quiet when nothing needed reconciliation" do
      assert LocalMigration.render(:already_reconciled) == [
               "Local data already matches the current architecture — nothing to reconcile."
             ]

      assert LocalMigration.render(:skipped_not_local) == []
    end

    test "to_payload is JSON-safe for every result shape" do
      assert LocalMigration.to_payload(%{
               sessions_moved: 1,
               orphan_workspaces: 2,
               orphan_orgs: 1,
               removed_workspaces: 1,
               removed_orgs: 1
             }) == %{
               "status" => "completed",
               "sessions_moved" => 1,
               "orphan_workspaces" => 2,
               "orphan_orgs" => 1,
               "removed_workspaces" => 1,
               "removed_orgs" => 1
             }

      assert LocalMigration.to_payload(:already_reconciled) == %{"status" => "already_reconciled"}
      assert LocalMigration.to_payload(:skipped_not_local) == %{"status" => "skipped_not_local"}
      assert LocalMigration.to_payload({:failed, :exception}) == %{"status" => "failed"}

      # every payload must be Jason-encodable (no tuples/atoms leaking)
      for result <- [
            %{sessions_moved: 1, orphan_workspaces: 1, orphan_orgs: 0},
            %{
              sessions_moved: 1,
              orphan_workspaces: 0,
              orphan_orgs: 0,
              removed_workspaces: 1,
              removed_orgs: 1
            },
            :already_reconciled,
            :skipped_not_local,
            {:failed, :exception}
          ] do
        assert {:ok, _} = Jason.encode(LocalMigration.to_payload(result))
      end
    end
  end

  # ──────────────── helpers ────────────────

  defp reset_migration_state! do
    Repo.delete_all(
      from(w in Workspace, where: w.slug == ^LocalDefaults.default_workspace_slug())
    )

    Repo.delete_all(from(o in Accounts.Org, where: o.slug == ^LocalDefaults.default_org_slug()))

    :ok
  end

  defp insert_memory_record(session, workspace) do
    %MemoryRecord{}
    |> MemoryRecord.changeset(%{
      workspace_id: workspace.id,
      session_id: session.id,
      record_type: "decision",
      title: "recorded note",
      summary: "summary",
      body: "body",
      tags: [],
      source_type: "test",
      source_id: "src-#{System.unique_integer([:positive])}",
      metadata: %{}
    })
    |> Repo.insert()
  end

  defp insert_analytics_event(session, workspace) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(%{
      event: "tool.called",
      source: "test",
      metadata: %{},
      happened_at: DateTime.utc_now() |> DateTime.truncate(:second),
      session_id: session.id,
      workspace_id: workspace.id
    })
    |> Repo.insert()
  end
end
