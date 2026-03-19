defmodule ControlKeel.BenchmarkTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.BenchmarkFixtures

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission.Session
  alias ControlKeel.Repo

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-benchmark-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "loads the built-in suite with deterministic scenario ordering" do
    suite = benchmark_suite_fixture()
    ordered = Enum.sort_by(suite.scenarios, & &1.position)

    assert suite.slug == "vibe_failures_v1"
    assert suite.version == 1
    assert length(ordered) == 10
    assert hd(ordered).slug == "hardcoded_api_key_python_webhook"
    assert List.last(ordered).slug == "pickle_deserialization_rce"
  end

  test "runs validate and proxy subjects without creating sessions or ship analytics" do
    session_count = Repo.aggregate(Session, :count, :id)
    analytics_count = Repo.aggregate(Event, :count, :id)

    {:ok, run} =
      Benchmark.run_suite(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    assert run.total_scenarios == 2
    assert Enum.sort(run.subjects) == ["controlkeel_proxy", "controlkeel_validate"]
    assert length(run.results) == 4
    assert run.catch_rate > 0.0
    assert run.blocked_count >= 1
    assert Benchmark.run_detail_metrics(run).expected_rule_hit_rate >= 0.0
    assert Repo.aggregate(Session, :count, :id) == session_count
    assert Repo.aggregate(Event, :count, :id) == analytics_count
  end

  test "runs an external shell subject and normalizes generated output", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "shell_stub",
        "label" => "Shell Stub",
        "type" => "shell",
        "command" => elixir_bin!(),
        "args" => ["-e", "IO.write(\"OPENAI_KEY = \\\"AKIAIOSFODNN7EXAMPLE\\\"\")"],
        "timeout_ms" => 5_000,
        "output_mode" => "stdout"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "shell_stub",
          "baseline_subject" => "shell_stub",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [result] = run.results

    assert result.subject == "shell_stub"
    assert result.subject_type == "shell"
    assert result.status == "completed"
    assert result.findings_count > 0
    assert result.matched_expected
    assert get_in(result.payload, ["artifacts"]) != []
  end

  test "shell subjects time out and unknown subjects are marked skipped", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "slow_shell",
        "label" => "Slow Shell",
        "type" => "shell",
        "command" => elixir_bin!(),
        "args" => ["-e", "Process.sleep(200)"],
        "timeout_ms" => 10,
        "output_mode" => "stdout"
      }
    ])

    {:ok, timed_out_run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "slow_shell",
          "baseline_subject" => "slow_shell",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [timed_out_result] = timed_out_run.results
    assert timed_out_result.status == "timed_out"

    {:ok, skipped_run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "missing_subject",
          "baseline_subject" => "missing_subject",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [skipped_result] = skipped_run.results
    assert skipped_result.status == "skipped_unconfigured"
    assert skipped_result.subject_type == "unconfigured"
  end

  test "manual imports are rescored through the current evaluator", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "manual_subject",
        "label" => "Manual Subject",
        "type" => "manual_import"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "manual_subject",
          "baseline_subject" => "manual_subject",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [pending_result] = run.results
    assert pending_result.status == "awaiting_import"

    {:ok, updated_run} =
      Benchmark.import_result(run.id, "manual_subject", %{
        "scenario_slug" => "hardcoded_api_key_python_webhook",
        "content" => "OPENAI_KEY = \"AKIAIOSFODNN7EXAMPLE\"",
        "path" => "app/intake_handler.py",
        "kind" => "code",
        "duration_ms" => 18,
        "metadata" => %{"source" => "captured-output"}
      })

    imported =
      Enum.find(updated_run.results, fn result ->
        result.subject == "manual_subject"
      end)

    assert imported.status == "completed"
    assert imported.decision == "block"
    assert imported.findings_count > 0
    assert imported.matched_expected
  end

  test "exports benchmark runs as json and csv" do
    run =
      benchmark_run_fixture(%{
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    assert {:ok, json} = Benchmark.export_run(run.id, "json")
    assert {:ok, csv} = Benchmark.export_run(run.id, "csv")

    decoded = Jason.decode!(json)

    assert decoded["run"]["id"] == run.id
    assert decoded["run"]["suite"]["slug"] == "vibe_failures_v1"
    assert csv =~ "run_id,suite_slug,scenario_slug"
    assert csv =~ "hardcoded_api_key_python_webhook"
  end

  defp elixir_bin! do
    System.find_executable("elixir") ||
      System.find_executable("elixir.bat") ||
      raise "elixir executable is required for benchmark shell tests"
  end
end
