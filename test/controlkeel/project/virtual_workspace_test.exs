defmodule ControlKeel.Project.VirtualWorkspaceTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mission
  alias ControlKeel.Project.VirtualWorkspace

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-virtual-workspace-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.mkdir_p!(Path.join(tmp_dir, "test"))
    File.mkdir_p!(Path.join(tmp_dir, "deps/vendor"))

    File.write!(
      Path.join(tmp_dir, "lib/checkpoint_store.ex"),
      "defmodule CheckpointStore do\n  def target, do: :needle\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "test/checkpoint_store_test.exs"),
      "defmodule CheckpointStoreTest do\n  @needle :needle\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "lib/matcher.ex"),
      "defmodule Matcher do\n  def match?, do: true\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "deps/vendor/checkpoint_store.ex"),
      "defmodule Vendor.CheckpointStore do\n  @needle :needle\nend\n"
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    workspace_attrs = %{
      name: "Virtual Workspace",
      slug: "virtual-workspace-#{System.unique_integer([:positive])}",
      industry: "software",
      agent: "test",
      budget_cents: 0,
      compliance_profile: "none",
      status: "active",
      org_id: ControlKeel.AccountsFixtures.org_fixture().id
    }

    assert {:ok, workspace} = Mission.create_workspace(workspace_attrs)

    session_attrs = %{
      title: "Virtual workspace session",
      objective: "Search orientation",
      risk_tier: "low",
      status: "planned",
      budget_cents: 0,
      daily_budget_cents: 0,
      spent_cents: 0,
      execution_brief: %{},
      metadata: %{"runtime_context" => %{"project_root" => tmp_dir}},
      workspace_id: workspace.id
    }

    assert {:ok, session} = Mission.create_session(session_attrs)

    %{session: session}
  end

  describe "resolve_root/2 with stale runtime_context" do
    setup do
      bound_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-bound-root-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(bound_dir)
      File.mkdir_p!(bound_dir)
      # Project marker so Root.resolve stops here rather than walking up.
      File.write!(Path.join(bound_dir, "mix.exs"), "~")

      workspace_attrs = %{
        name: "Stale root workspace",
        slug: "stale-root-#{System.unique_integer([:positive])}",
        industry: "software",
        agent: "test",
        budget_cents: 0,
        compliance_profile: "none",
        status: "active",
        org_id: ControlKeel.AccountsFixtures.org_fixture().id
      }

      assert {:ok, workspace} = Mission.create_workspace(workspace_attrs)

      # Session carries a runtime_context.project_root pointing at a dir that
      # does not exist on disk (the regression we are guarding against).
      stale_root =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-deleted-root-#{System.unique_integer([:positive])}"
        )

      session_attrs = %{
        title: "Stale runtime root session",
        objective: "Fallback to binding",
        risk_tier: "low",
        status: "planned",
        budget_cents: 0,
        daily_budget_cents: 0,
        spent_cents: 0,
        execution_brief: %{},
        metadata: %{"runtime_context" => %{"project_root" => stale_root}},
        workspace_id: workspace.id
      }

      assert {:ok, session} = Mission.create_session(session_attrs)

      # Write a project binding at bound_dir that owns this session.
      ControlKeel.Project.Binding.write(
        %{
          "workspace_id" => workspace.id,
          "session_id" => session.id,
          "agent" => "test"
        },
        bound_dir
      )

      on_exit(fn -> File.rm_rf!(bound_dir) end)

      %{session: session, bound_dir: bound_dir, stale_root: stale_root}
    end

    test "falls back to the project binding when runtime root is missing on disk",
         %{session: session, bound_dir: bound_dir, stale_root: stale_root} do
      refute File.dir?(stale_root)

      assert {:ok, resolved} = VirtualWorkspace.resolve_root(session.id, bound_dir)
      # Binding canonicalizes via Root.resolve (realpath), so compare canonical forms.
      assert resolved == ControlKeel.Project.Root.resolve(bound_dir)
    end

    test "prefers the runtime root when it exists on disk", %{
      session: session,
      bound_dir: bound_dir
    } do
      # Refresh the session metadata to a real runtime root.
      real_runtime =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-real-runtime-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(real_runtime)

      {:ok, _} =
        Mission.update_session(session, %{
          metadata: %{"runtime_context" => %{"project_root" => real_runtime}}
        })

      assert {:ok, resolved} = VirtualWorkspace.resolve_root(session.id, bound_dir)
      assert resolved == Path.expand(real_runtime)

      File.rm_rf!(real_runtime)
    end
  end

  test "find ranks source-ish paths first and emits orientation metadata", %{session: session} do
    assert {:ok, result} = VirtualWorkspace.find(session.id, "checkpoint_store", limit: 10)

    [first | rest] = result["matches"]

    assert first["path"] == "lib/checkpoint_store.ex"
    assert first["rank"] == 1
    assert first["orientation_hint"] == "source"
    assert first["path_depth"] == 2
    assert "basename" in first["matched_on"]
    assert is_integer(first["orientation_score"])

    assert Enum.any?(rest, &(&1["orientation_hint"] == "test"))
    refute Enum.any?(result["matches"], &String.starts_with?(&1["path"], "deps/"))
  end

  test "find with glob pattern matches basenames", %{session: session} do
    assert {:ok, result} = VirtualWorkspace.find(session.id, "*.ex", limit: 10)

    assert result["match_mode"] == "glob"
    assert result["count"] >= 2

    paths = Enum.map(result["matches"], & &1["path"])
    assert "lib/checkpoint_store.ex" in paths
    assert "lib/matcher.ex" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "deps/"))
  end

  test "find with glob pattern crosses directory segments", %{session: session} do
    assert {:ok, result} = VirtualWorkspace.find(session.id, "**/*test*", limit: 10)

    assert result["match_mode"] == "glob"
    assert result["count"] >= 1

    paths = Enum.map(result["matches"], & &1["path"])
    assert "test/checkpoint_store_test.exs" in paths
  end

  test "find with non-glob query uses substring matching", %{session: session} do
    assert {:ok, result} = VirtualWorkspace.find(session.id, "checkpoint", limit: 10)

    assert result["match_mode"] == "substring"
    assert result["count"] >= 2
  end

  test "grep emits file summaries and per-match orientation metadata", %{session: session} do
    assert {:ok, result} =
             VirtualWorkspace.grep(session.id, "needle", limit: 10, fixed_strings: true)

    assert result["file_count"] == 2
    assert [%{"path" => "lib/checkpoint_store.ex", "rank" => 1} | _] = result["files"]

    assert Enum.all?(result["matches"], &is_integer(&1["rank"]))
    assert Enum.all?(result["matches"], &is_integer(&1["file_match_count"]))
    assert Enum.any?(result["matches"], &(&1["orientation_hint"] == "source"))
  end
end
