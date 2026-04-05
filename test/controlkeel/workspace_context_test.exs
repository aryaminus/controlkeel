defmodule ControlKeel.WorkspaceContextTest do
  use ExUnit.Case, async: true

  alias ControlKeel.WorkspaceContext

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-workspace-context-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "build/1 returns git context and detected instruction files", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "AGENTS.md"), "repo instructions\n")
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n")
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Demo.MixProject do end\n")

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    context = WorkspaceContext.build(tmp_dir)

    assert context["available"] == true
    assert Path.basename(context["repo_root"]) == Path.basename(tmp_dir)
    assert is_binary(get_in(context, ["git", "branch"]))
    assert String.length(get_in(context, ["git", "head_sha"])) == 40
    assert Enum.any?(context["instruction_files"], &(&1["path"] == "AGENTS.md"))
    assert Enum.any?(context["instruction_files"], &(&1["path"] == "README.md"))
    assert Enum.any?(context["key_files"], &(&1["path"] == "mix.exs"))
  end

  test "cache key changes when tracked instruction files change", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "AGENTS.md"), "repo instructions\n")
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n")

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    first = WorkspaceContext.build(tmp_dir)
    File.write!(Path.join(tmp_dir, "AGENTS.md"), "updated instructions\n")
    second = WorkspaceContext.build(tmp_dir)

    assert first["cache_key"] != second["cache_key"]
    assert get_in(second, ["git", "status_counts", "modified"]) >= 1
  end

  test "build/1 returns unavailable for missing or non-git roots", %{tmp_dir: tmp_dir} do
    missing = Path.join(tmp_dir, "missing")
    non_git = Path.join(tmp_dir, "plain")
    File.mkdir_p!(non_git)

    assert WorkspaceContext.build(missing)["available"] == false
    assert WorkspaceContext.build(non_git)["available"] == false
  end
end
