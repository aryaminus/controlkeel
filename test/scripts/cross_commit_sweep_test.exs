defmodule ControlKeel.CrossCommitSweepTest do
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)

  test "workflow is bounded and read-only" do
    workflow = File.read!(Path.join(@root, ".github/workflows/cross-commit-sweep.yml"))

    assert workflow =~ "contents: read"
    assert workflow =~ "workflow_dispatch:"
    assert workflow =~ "schedule:"
    assert workflow =~ "lookback must be between 1 and 75"
    assert workflow =~ "actions/upload-artifact@v4"
    refute workflow =~ "pull-requests: write"
    refute workflow =~ "issues: write"
    refute workflow =~ "git push"
  end

  test "script reports missing test evidence without mutating the repository" do
    tmp =
      Path.join(System.tmp_dir!(), "ck-cross-commit-sweep-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp) end)
    File.mkdir_p!(Path.join(tmp, "lib"))
    File.mkdir_p!(Path.join(tmp, "test"))

    System.cmd("git", ["init", "-q", tmp])
    System.cmd("git", ["-C", tmp, "config", "user.email", "test@example.com"])
    System.cmd("git", ["-C", tmp, "config", "user.name", "Test"])
    File.write!(Path.join(tmp, "README.md"), "start\n")
    System.cmd("git", ["-C", tmp, "add", "."])
    System.cmd("git", ["-C", tmp, "commit", "-qm", "initial"])
    {base, 0} = System.cmd("git", ["-C", tmp, "rev-parse", "HEAD"])

    File.write!(Path.join(tmp, "lib/example.ex"), "defmodule Example, do: nil\n")
    System.cmd("git", ["-C", tmp, "add", "."])
    System.cmd("git", ["-C", tmp, "commit", "-qm", "change source"])

    output = Path.join(tmp, "report.md")

    {_, 0} =
      System.cmd("python3", [
        Path.join(@root, "scripts/cross_commit_sweep.py"),
        "--repo",
        tmp,
        "--base",
        String.trim(base),
        "--head",
        "HEAD",
        "--output",
        output
      ])

    report = File.read!(output)
    assert report =~ "Production or configuration files changed without test changes."
    assert report =~ "These are review prompts, not policy findings."
    assert String.trim(git_status(tmp)) == "?? report.md"
  end

  test "script reports git failures without a traceback" do
    {output, 1} =
      System.cmd(
        "python3",
        [
          Path.join(@root, "scripts/cross_commit_sweep.py"),
          "--repo",
          @root,
          "--base",
          "not-a-ref",
          "--output",
          Path.join(System.tmp_dir!(), "unused-sweep.md")
        ],
        stderr_to_stdout: true
      )

    refute output =~ "Traceback"
    assert output != ""
  end

  defp git_status(repo) do
    {status, 0} = System.cmd("git", ["-C", repo, "status", "--short"])
    status
  end
end
