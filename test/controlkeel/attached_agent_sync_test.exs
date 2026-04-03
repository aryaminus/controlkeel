defmodule ControlKeel.AttachedAgentSyncTest do
  use ControlKeel.DataCase

  alias ControlKeel.AttachedAgentSync
  alias ControlKeel.ProjectBinding

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-attached-sync-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "sync refreshes stale repo-native attachments to the current CK version", %{
    tmp_dir: tmp_dir
  } do
    current_version = to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")

    binding = %{
      "workspace_id" => 1,
      "session_id" => 1,
      "agent" => "claude",
      "attached_agents" => %{
        "augment" => %{
          "target" => "augment-native",
          "scope" => "project",
          "controlkeel_version" => "0.0.1"
        }
      },
      "bootstrap" => %{"mode" => "project", "auto_bootstrapped" => false}
    }

    assert {:ok, written} = ProjectBinding.write(binding, tmp_dir)
    assert {:ok, synced, changes} = AttachedAgentSync.sync(written, tmp_dir, mode: :project)

    assert [%{"agent" => "augment", "status" => "synced"}] = changes
    assert synced["attached_agents"]["augment"]["controlkeel_version"] == current_version
    assert synced["attached_agents"]["augment"]["synced_at"]
    assert File.exists?(Path.join(tmp_dir, ".augment/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".augment/commands/controlkeel-review.md"))
  end

  test "sync skips agents already on the current version", %{tmp_dir: tmp_dir} do
    current_version = to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")

    binding = %{
      "workspace_id" => 1,
      "session_id" => 1,
      "agent" => "claude",
      "attached_agents" => %{
        "augment" => %{
          "target" => "augment-native",
          "scope" => "project",
          "controlkeel_version" => current_version
        }
      },
      "bootstrap" => %{"mode" => "project", "auto_bootstrapped" => false}
    }

    assert {:ok, written} = ProjectBinding.write(binding, tmp_dir)
    assert {:ok, synced, []} = AttachedAgentSync.sync(written, tmp_dir, mode: :project)
    assert synced["attached_agents"]["augment"]["controlkeel_version"] == current_version
    refute synced["attached_agents"]["augment"]["synced_at"]
  end
end
