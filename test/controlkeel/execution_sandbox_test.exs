defmodule ControlKeel.ExecutionSandboxTest do
  use ControlKeel.DataCase

  alias ControlKeel.ExecutionSandbox

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-sandbox-test-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    config_dir = Path.join(tmp_dir, ".controlkeel")
    File.mkdir_p!(config_dir)

    original_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_dir)

    on_exit(fn ->
      if original_home do
        System.put_env("CONTROLKEEL_HOME", original_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, config_dir: config_dir}
  end

  describe "local adapter" do
    test "runs a command and returns output" do
      assert {:ok, %{output: output, exit_status: 0}} =
               ExecutionSandbox.Local.run("echo", ["hello sandbox"], [])

      assert output =~ "hello sandbox"
    end

    test "returns non-zero exit status for failing command" do
      assert {:ok, %{exit_status: exit_status}} =
               ExecutionSandbox.Local.run("sh", ["-c", "exit 1"], [])

      assert exit_status != 0
    end

    test "returns error for missing command" do
      assert {:error, _reason} =
               ExecutionSandbox.Local.run("nonexistent_command_xyz_12345", [], [])
    end

    test "always available" do
      assert ExecutionSandbox.Local.available?() == true
    end

    test "adapter name" do
      assert ExecutionSandbox.Local.adapter_name() == "local"
    end
  end

  describe "docker adapter" do
    test "adapter name" do
      assert ExecutionSandbox.Docker.adapter_name() == "docker"
    end

    test "available check does not crash" do
      assert is_boolean(ExecutionSandbox.Docker.available?())
    end
  end

  describe "e2b adapter" do
    test "adapter name" do
      assert ExecutionSandbox.E2B.adapter_name() == "e2b"
    end

    test "available check does not crash" do
      assert is_boolean(ExecutionSandbox.E2B.available?())
    end
  end

  describe "nono adapter" do
    test "adapter name" do
      assert ExecutionSandbox.Nono.adapter_name() == "nono"
    end

    test "available check does not crash" do
      assert is_boolean(ExecutionSandbox.Nono.available?())
    end

    test "wraps commands with nono flags and inferred profile", %{tmp_dir: tmp_dir} do
      with_fake_nono(tmp_dir)

      project_root = Path.join(tmp_dir, "project")
      File.mkdir_p!(project_root)

      assert {:ok, %{output: output, exit_status: 0}} =
               ExecutionSandbox.Nono.run("codex", ["exec"], cwd: project_root)

      assert output =~ "PWD="
      assert output =~ "/controlkeel-sandbox-test-"
      assert output =~ "/project"
      assert output =~ "ARGS=run --profile codex --allow-cwd --rollback -- codex exec"
    end
  end

  describe "adapter resolution" do
    test "resolves local by default" do
      adapter = ExecutionSandbox.resolve_adapter(sandbox: "local")
      assert adapter == ExecutionSandbox.Local
    end

    test "resolves docker when requested (or falls back to local if unavailable)" do
      adapter = ExecutionSandbox.resolve_adapter(sandbox: "docker")
      assert adapter in [ExecutionSandbox.Docker, ExecutionSandbox.Local]
    end

    test "resolves e2b when requested (or falls back to local if unavailable)" do
      adapter = ExecutionSandbox.resolve_adapter(sandbox: "e2b")
      assert adapter in [ExecutionSandbox.E2B, ExecutionSandbox.Local]
    end

    test "resolves nono when requested (or falls back to local if unavailable)" do
      adapter = ExecutionSandbox.resolve_adapter(sandbox: "nono")
      assert adapter in [ExecutionSandbox.Nono, ExecutionSandbox.Local]
    end

    test "falls back to local for unknown adapter" do
      adapter = ExecutionSandbox.resolve_adapter(sandbox: "unknown")
      assert adapter == ExecutionSandbox.Local
    end
  end

  describe "supported_adapters/0" do
    test "returns four adapters" do
      adapters = ExecutionSandbox.supported_adapters()
      assert length(adapters) == 4

      ids = Enum.map(adapters, & &1[:id])
      assert "local" in ids
      assert "docker" in ids
      assert "e2b" in ids
      assert "nono" in ids
    end

    test "each adapter has required fields" do
      for adapter <- ExecutionSandbox.supported_adapters() do
        assert Map.has_key?(adapter, :id)
        assert Map.has_key?(adapter, :name)
        assert Map.has_key?(adapter, :description)
        assert Map.has_key?(adapter, :available)
      end
    end
  end

  describe "config persistence" do
    test "adapter_name uses opts over config" do
      assert ExecutionSandbox.adapter_name(sandbox: "docker") == "docker"
      assert ExecutionSandbox.adapter_name(sandbox: "nono") == "nono"
    end

    test "adapter_name defaults to local when no opts" do
      assert ExecutionSandbox.adapter_name([]) == "local"
    end

    test "defaults to local when config file does not exist" do
      assert ExecutionSandbox.adapter_name([]) == "local"
    end
  end

  defp with_fake_nono(tmp_dir) do
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    script_path = Path.join(bin_dir, "nono")

    File.write!(
      script_path,
      """
      #!/usr/bin/env sh
      set -eu

      if [ "${1:-}" = "--version" ]; then
        echo "nono 0.1.0"
        exit 0
      fi

      echo "PWD=$PWD"
      echo "ARGS=$*"
      """
    )

    File.chmod!(script_path, 0o755)

    original_path = System.get_env("PATH") || ""
    System.put_env("PATH", "#{bin_dir}:#{original_path}")

    on_exit(fn -> System.put_env("PATH", original_path) end)
  end
end
