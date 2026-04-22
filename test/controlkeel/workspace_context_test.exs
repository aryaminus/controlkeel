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
    assert [%{"subject" => "initial"} | _] = get_in(context, ["orientation", "recent_commits"])

    assert Enum.any?(
             get_in(context, ["orientation", "instruction_previews"]),
             &(&1["path"] == "AGENTS.md")
           )

    assert Enum.any?(
             get_in(context, ["orientation", "active_assumptions"]),
             &String.contains?(&1, "repo instructions")
           )
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

  test "build/1 surfaces design drift signals for hotspots and oversized files", %{
    tmp_dir: tmp_dir
  } do
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    large_body = Enum.map_join(1..820, "\n", fn index -> "line_#{index} = #{index}" end)
    source_path = Path.join(tmp_dir, "lib/demo.ex")

    File.write!(source_path, large_body)
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n")

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    assert {"", 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    Enum.each(1..3, fn iteration ->
      File.write!(source_path, large_body <> "\n# change #{iteration}\n")
      assert {"", 0} = System.cmd("git", ["add", "lib/demo.ex"], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["commit", "-m", "change #{iteration}"], cd: tmp_dir)
    end)

    context = WorkspaceContext.build(tmp_dir)

    assert get_in(context, ["design_drift", "high_risk"]) == true

    assert Enum.any?(
             get_in(context, ["design_drift", "large_files"]),
             &(&1["path"] == "lib/demo.ex")
           )

    assert Enum.any?(
             get_in(context, ["design_drift", "recent_hotspots"]),
             &(&1["path"] == "lib/demo.ex")
           )

    assert Enum.any?(
             get_in(context, ["design_drift", "signals"]),
             &(&1["code"] == "very_large_source_file")
           )

    assert Enum.any?(
             get_in(context, ["design_drift", "signals"]),
             &(&1["code"] == "recent_edit_hotspot")
           )

    assert get_in(context, ["design_drift", "complexity_budget", "level"]) == "high"

    assert get_in(context, ["design_drift", "complexity_budget", "review_pressure"]) ==
             "require_small_steps_and_stronger_tests"

    [finding] = WorkspaceContext.complexity_budget_findings(context["design_drift"])
    assert finding["rule_id"] == "design.complexity_budget.high"
    assert finding["metadata"]["complexity_budget"]["level"] == "high"
  end

  test "build/1 returns unavailable for missing or non-git roots", %{tmp_dir: tmp_dir} do
    missing = Path.join(tmp_dir, "missing")
    non_git = Path.join(tmp_dir, "plain")
    File.mkdir_p!(non_git)

    assert WorkspaceContext.build(missing)["available"] == false
    assert WorkspaceContext.build(non_git)["available"] == false
  end
end
