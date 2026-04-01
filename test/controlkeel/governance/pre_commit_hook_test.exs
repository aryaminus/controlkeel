defmodule ControlKeel.Governance.PreCommitHookTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.PreCommitHook

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-precommit-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "install writes git pre-commit hook", %{tmp_dir: tmp_dir} do
    assert {:ok, :installed} = PreCommitHook.install(tmp_dir)

    hook_path = Path.join([tmp_dir, ".git", "hooks", "pre-commit"])
    assert File.exists?(hook_path)
    content = File.read!(hook_path)
    assert content =~ "controlkeel"
  end

  test "install with enforce flag", %{tmp_dir: tmp_dir} do
    assert {:ok, :installed} = PreCommitHook.install(tmp_dir, enforce: true)

    hook_path = Path.join([tmp_dir, ".git", "hooks", "pre-commit"])
    content = File.read!(hook_path)
    assert content =~ "--enforce"
  end

  test "install updates existing controlkeel hook", %{tmp_dir: tmp_dir} do
    PreCommitHook.install(tmp_dir)
    assert {:ok, :updated} = PreCommitHook.install(tmp_dir)
  end

  test "install rejects non-controlkeel hook", %{tmp_dir: tmp_dir} do
    hooks_dir = Path.join([tmp_dir, ".git", "hooks"])
    File.mkdir_p!(hooks_dir)
    File.write!(Path.join(hooks_dir, "pre-commit"), "#!/bin/sh\necho other hook")

    assert {:error, :hook_exists} = PreCommitHook.install(tmp_dir)
  end

  test "uninstall removes controlkeel hook", %{tmp_dir: tmp_dir} do
    PreCommitHook.install(tmp_dir)
    assert {:ok, :uninstalled} = PreCommitHook.uninstall(tmp_dir)

    hook_path = Path.join([tmp_dir, ".git", "hooks", "pre-commit"])
    refute File.exists?(hook_path)
  end

  test "uninstall does nothing if no hook exists", %{tmp_dir: tmp_dir} do
    assert {:ok, :no_hook_found} = PreCommitHook.uninstall(tmp_dir)
  end

  test "check returns allow when no files staged", %{tmp_dir: tmp_dir} do
    assert {:ok, result} = PreCommitHook.check(tmp_dir)
    assert result.decision == "allow"
    assert result.findings == []
  end

  test "install with mix_task type returns ok" do
    assert {:ok, :mix_task_available} = PreCommitHook.install("/tmp", type: :mix_task)
  end

  test "install with github_action type returns ok" do
    assert {:ok, :github_action_available} =
             PreCommitHook.install("/tmp", type: :github_action)
  end
end
