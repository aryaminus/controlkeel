defmodule ControlKeel.HarnessToolsTest do
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)
  @python System.find_executable("python3")

  test "performance comparator enforces review for regressions" do
    tmp = temp_dir("performance")
    baseline = evidence("base", [10, 10, 11, 10, 9], "baseline")
    candidate = evidence("candidate", [20, 20, 21, 19, 20], "candidate")
    File.write!(Path.join(tmp, "baseline.json"), Jason.encode!(baseline))
    File.write!(Path.join(tmp, "candidate.json"), Jason.encode!(candidate))

    {output, 2} =
      python("performance_evidence.py", [
        "compare",
        "--baseline",
        Path.join(tmp, "baseline.json"),
        "--candidate",
        Path.join(tmp, "candidate.json")
      ])

    assert Jason.decode!(output)["status"] == "regression_requires_review"

    approved =
      put_in(candidate, ["regression_review"], %{
        "status" => "approved",
        "review_id" => 42,
        "reviewed_by" => "performance-reviewer"
      })

    File.write!(Path.join(tmp, "candidate.json"), Jason.encode!(approved))

    {output, 0} =
      python("performance_evidence.py", [
        "compare",
        "--baseline",
        Path.join(tmp, "baseline.json"),
        "--candidate",
        Path.join(tmp, "candidate.json")
      ])

    assert Jason.decode!(output)["status"] == "pass"
  end

  test "performance comparator rejects stale candidate commits" do
    tmp = git_repo("performance-commit")
    File.write!(Path.join(tmp, "README.md"), "fixture\n")
    commit_all(tmp)
    baseline = evidence("base", [10, 10, 11, 10, 9], "baseline")
    candidate = evidence("stale", [10, 10, 11, 10, 9], "candidate")
    File.write!(Path.join(tmp, "baseline.json"), Jason.encode!(baseline))
    File.write!(Path.join(tmp, "candidate.json"), Jason.encode!(candidate))

    {error, 1} =
      python("performance_evidence.py", [
        "compare",
        "--baseline",
        Path.join(tmp, "baseline.json"),
        "--candidate",
        Path.join(tmp, "candidate.json"),
        "--repo",
        tmp
      ])

    assert error =~ "candidate commit_sha is stale"
  end

  test "test inventory audit detects missing and unexecuted tests" do
    tmp = git_repo("inventory")
    File.mkdir_p!(Path.join(tmp, "test"))
    File.write!(Path.join(tmp, "test/example_test.exs"), "defmodule ExampleTest do\nend\n")
    commit_all(tmp)
    inventory = Path.join(tmp, "inventory.json")

    {_, 0} =
      python("test_inventory.py", ["generate", "--repo", tmp, "--output", inventory], [
        {"SOURCE_DATE_EPOCH", "0"}
      ])

    {output, 2} = python("test_inventory.py", ["audit", "--repo", tmp, "--inventory", inventory])

    assert "test has no passing execution: test/example_test.exs (unexecuted)" in Jason.decode!(
             output
           )["issues"]

    File.rm!(Path.join(tmp, "test/example_test.exs"))
    {output, 2} = python("test_inventory.py", ["audit", "--repo", tmp, "--inventory", inventory])
    assert Enum.any?(Jason.decode!(output)["issues"], &String.starts_with?(&1, "missing test:"))
  end

  test "profiling adapter is bounded and dry-run by default" do
    {output, 0} =
      python("profile_beam.py", ["--profiler", "cprof", "--expression", "Enum.sum(1..10)"])

    plan = Jason.decode!(output)
    refute plan["executed"]
    assert plan["command"] == ["mix", "profile.cprof", "-e", "Enum.sum(1..10)"]
    assert plan["timeout_seconds"] == 30
  end

  test "profiling adapter reports subprocess errors without a traceback" do
    {output, 1} =
      python(
        "profile_beam.py",
        ["--profiler", "cprof", "--expression", "Enum.sum(1..10)", "--execute"],
        [{"PATH", ""}]
      )

    refute output =~ "Traceback"
    assert output =~ "mix"
  end

  test "evidence audit rejects stale generated artifacts" do
    tmp = git_repo("evidence-audit")
    File.write!(Path.join(tmp, "README.md"), "fixture\n")
    commit_all(tmp)
    evidence_dir = Path.join(tmp, "evidence")
    File.mkdir_p!(evidence_dir)

    File.write!(
      Path.join(evidence_dir, "candidate.json"),
      Jason.encode!(evidence("stale", [1, 2, 3, 4, 5], "candidate"))
    )

    {output, 2} =
      python("evidence_audit.py", ["--repo", tmp, "--evidence-dir", evidence_dir])

    assert Jason.decode!(output)["issues"]
           |> Enum.any?(&String.starts_with?(&1, "stale performance candidate:"))
  end

  defp evidence(commit, samples, role) do
    %{
      "schema_version" => 1,
      "evidence_kind" => "performance",
      "evidence_role" => role,
      "benchmark" => "tools-list",
      "commit_sha" => commit,
      "environment" => %{"otp" => "28", "arch" => "arm64"},
      "samples_ms" => samples,
      "allowed_regression_percent" => 10
    }
  end

  defp python(script, args, env \\ []) do
    System.cmd(@python, [Path.join(@root, "scripts/#{script}") | args],
      env: env,
      stderr_to_stdout: true
    )
  end

  defp temp_dir(name) do
    path = Path.join(System.tmp_dir!(), "ck-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp git_repo(name) do
    path = temp_dir(name)
    System.cmd("git", ["init", "-q", path])
    System.cmd("git", ["-C", path, "config", "user.email", "test@example.com"])
    System.cmd("git", ["-C", path, "config", "user.name", "Test"])
    path
  end

  defp commit_all(path) do
    System.cmd("git", ["-C", path, "add", "."])
    System.cmd("git", ["-C", path, "commit", "-qm", "fixture"])
  end
end
