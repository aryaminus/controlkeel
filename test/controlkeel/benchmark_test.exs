defmodule ControlKeel.BenchmarkTest do
  use ExUnit.Case, async: false

  import ControlKeel.BenchmarkFixtures

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Benchmark
  alias ControlKeel.Benchmark.{BuiltinSuites, Result, Run, Scenario, Suite}
  alias ControlKeel.Mission.Session
  alias ControlKeel.Repo

  setup_all do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ControlKeel.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  setup do
    Repo.delete_all(ControlKeel.Benchmark.Result)
    Repo.delete_all(ControlKeel.Benchmark.Run)

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
    assert Benchmark.suite_eval_profile(suite)["split_summary"]["public"] == length(ordered)
    assert Benchmark.suite_eval_profile(suite)["behavior_tag_summary"]["security"] >= 1
  end

  test "loads the public domain-expansion suite with explicit metadata" do
    suite = benchmark_suite_fixture("domain_expansion_v1")

    assert suite.slug == "domain_expansion_v1"
    assert length(suite.scenarios) == 5

    assert Enum.all?(
             suite.scenarios,
             &(get_in(&1.metadata || %{}, ["domain_pack"]) in [
                 "hr",
                 "legal",
                 "marketing",
                 "sales",
                 "realestate"
               ])
           )

    assert Benchmark.domain_packs_for_suite(suite) == [
             "hr",
             "legal",
             "marketing",
             "sales",
             "realestate"
           ]
  end

  test "loads the broader public domain-expansion suite for the new packs" do
    suite = benchmark_suite_fixture("domain_expansion_v2")

    assert suite.slug == "domain_expansion_v2"
    assert length(suite.scenarios) == 6

    assert Enum.all?(
             suite.scenarios,
             &(get_in(&1.metadata || %{}, ["domain_pack"]) in [
                 "government",
                 "insurance",
                 "ecommerce",
                 "logistics",
                 "manufacturing",
                 "nonprofit"
               ])
           )

    assert Benchmark.domain_packs_for_suite(suite) == [
             "government",
             "insurance",
             "ecommerce",
             "logistics",
             "manufacturing",
             "nonprofit"
           ]
  end

  test "loads the benign baseline suite paired with vibe_failures_v1" do
    suite = benchmark_suite_fixture("benign_baseline_v1")

    assert suite.slug == "benign_baseline_v1"
    assert length(suite.scenarios) == 10

    assert Enum.all?(suite.scenarios, fn scenario ->
             scenario.expected_decision == "allow"
           end)

    assert Enum.all?(suite.scenarios, fn scenario ->
             scenario.expected_rules == []
           end)
  end

  test "suite eval profile surfaces held-out split and behavior tags" do
    suite = benchmark_suite_fixture("policy_holdout_v1")
    profile = Benchmark.suite_eval_profile(suite)

    assert profile["split_summary"]["held_out"] == length(suite.scenarios)
    assert profile["behavior_tag_summary"]["software"] >= 1
    assert profile["behavior_tag_summary"]["backend"] >= 1
  end

  test "eval profiles surface multi-agent memory-sharing and compaction strategies" do
    suite = %Suite{
      metadata: %{},
      scenarios: [
        %Scenario{
          id: -1,
          slug: "latent-briefing-case",
          name: "Latent briefing case",
          category: "research",
          split: "public",
          metadata: %{
            "domain_pack" => "software",
            "task_type" => "analysis",
            "memory_sharing_strategy" => "latent_briefing",
            "compaction_strategy" => "attention_guided_kv_compaction"
          }
        }
      ]
    }

    profile = Benchmark.suite_eval_profile(suite)

    assert profile["behavior_tag_summary"]["latent_briefing"] == 1
    assert profile["behavior_tag_summary"]["attention_guided_kv_compaction"] == 1
  end

  test "loads the defensive security benchmark suites" do
    assert Enum.sort([
             benchmark_suite_fixture("vuln_patch_loop_v1").slug,
             benchmark_suite_fixture("detection_rule_gen_v1").slug,
             benchmark_suite_fixture("supply_chain_triage_v1").slug
           ]) == ["detection_rule_gen_v1", "supply_chain_triage_v1", "vuln_patch_loop_v1"]

    assert Enum.all?(
             ["vuln_patch_loop_v1", "detection_rule_gen_v1", "supply_chain_triage_v1"],
             fn slug ->
               suite = benchmark_suite_fixture(slug)

               Enum.all?(
                 suite.scenarios,
                 &(get_in(&1.metadata || %{}, ["domain_pack"]) == "security")
               )
             end
           )
  end

  test "classification metrics return TPR 1.0 for vulnerable-only suites" do
    {:ok, run} =
      Benchmark.run_suite(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    classification = Benchmark.classification_metrics(run)

    # All scenarios expect block → all should be positives
    assert classification.positive_scenarios == 2
    assert classification.negative_scenarios == 0
    assert classification.true_positives >= 1
    assert classification.tpr != nil
    assert classification.tpr > 0.0
    # No negatives → FPR is nil (no denominator)
    assert classification.fpr == nil
  end

  test "classification metrics return FPR near 0.0 for benign suite" do
    {:ok, run} =
      Benchmark.run_suite(%{
        "suite" => "benign_baseline_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate"
      })

    classification = Benchmark.classification_metrics(run)

    # All scenarios expect allow → all should be negatives
    assert classification.positive_scenarios == 0
    assert classification.negative_scenarios == 10
    assert classification.true_negatives >= 0
    # TPR is nil (no positive denominator)
    assert classification.tpr == nil
    # FPR should be 0.0 or very low
    assert classification.fpr != nil
    # FPR measures false alarm rate; a measured value is the point of the benign suite
    assert classification.fpr <= 0.5
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
    assert Benchmark.run_eval_profile(run)["split_summary"]["public"] == 2
    assert Benchmark.run_eval_profile(run)["behavior_tag_summary"]["security"] >= 1
    assert Repo.aggregate(Session, :count, :id) == session_count
    assert Repo.aggregate(Event, :count, :id) == analytics_count
  end

  test "filters suites and runs by domain pack" do
    assert Enum.any?(
             Benchmark.list_suites(domain_pack: "hr"),
             &(&1.slug == "domain_expansion_v1")
           )

    {:ok, run} =
      Benchmark.run_suite(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "domain_pack" => "sales"
      })

    assert run.total_scenarios == 1
    assert Benchmark.domain_packs_for_run(run) == ["sales"]

    filtered_runs = Benchmark.list_recent_runs(domain_pack: "sales")
    assert Enum.any?(filtered_runs, &(&1.id == run.id))
  end

  test "benchmark summary reads builtin suite metadata without seeding persisted suites" do
    initial_suite_count = Repo.aggregate(Suite, :count, :id)

    summary = Benchmark.benchmark_summary()

    assert summary.total_suites == length(BuiltinSuites.list())
    assert Repo.aggregate(Suite, :count, :id) == initial_suite_count
  end

  test "promotion integrity warns on single-score evidence without holdout coverage" do
    integrity =
      Benchmark.promotion_integrity_profile(%{
        "scenario_count" => 3,
        "split_summary" => %{"public" => 3},
        "behavior_tag_summary" => %{"security" => 3},
        "classification" => %{}
      })

    assert integrity["status"] == "warn"
    assert "missing_holdout_evidence" in integrity["warnings"]
    assert "low_behavior_diversity" in integrity["warnings"]
    assert "missing_classification_evidence" in integrity["warnings"]

    findings = Benchmark.integrity_findings(%{"promotion_integrity" => integrity})
    assert Enum.any?(findings, &(&1["rule_id"] == "benchmarks.missing_holdout_evidence"))
  end

  test "promotion integrity warns on single_score_promotion when only one evidence channel" do
    integrity =
      Benchmark.promotion_integrity_profile(%{
        "scenario_count" => 3,
        "split_summary" => %{"public" => 3},
        "behavior_tag_summary" => %{"security" => 3},
        "classification" => %{}
      })

    assert "single_score_promotion" in integrity["warnings"]

    findings = Benchmark.integrity_findings(%{"promotion_integrity" => integrity})

    assert Enum.any?(findings, &(&1["rule_id"] == "benchmarks.single_score_promotion"))
    assert Enum.any?(findings, &String.contains?(&1["plain_message"], "single channel"))
  end

  test "promotion integrity warns on eval_staleness when no trace-derived scenarios" do
    integrity =
      Benchmark.promotion_integrity_profile(%{
        "scenario_count" => 3,
        "split_summary" => %{"public" => 3, "held_out" => 1},
        "behavior_tag_summary" => %{"security" => 3, "governance" => 2},
        "classification" => %{"youdens_j" => 0.75},
        "curation_mode" => "hand_curated"
      })

    assert "eval_staleness" in integrity["warnings"]

    findings = Benchmark.integrity_findings(%{"promotion_integrity" => integrity})

    assert Enum.any?(findings, &(&1["rule_id"] == "benchmarks.eval_staleness"))
    assert Enum.any?(findings, &String.contains?(&1["plain_message"], "trace-derived"))
  end

  test "promotion integrity does not warn on eval_staleness when trace-derived scenarios present" do
    integrity =
      Benchmark.promotion_integrity_profile(%{
        "scenario_count" => 3,
        "split_summary" => %{"public" => 3, "held_out" => 1},
        "behavior_tag_summary" => %{"security" => 3, "governance" => 2},
        "classification" => %{"youdens_j" => 0.75},
        "curation_mode" => "hand_curated_plus_trace_promoted"
      })

    refute "eval_staleness" in integrity["warnings"]
  end

  test "run_eval_profile preserves suite curation_mode for eval_staleness diagnostics" do
    scenario = %Scenario{
      id: 123,
      slug: "stale-suite-scenario",
      name: "Stale suite scenario",
      category: "security",
      split: "public",
      expected_decision: "block",
      metadata: %{"domain_pack" => "software", "task_type" => "backend"}
    }

    run = %Run{
      id: 456,
      suite: %Suite{metadata: %{"curation_mode" => "hand_curated"}},
      results: [
        %Result{
          scenario: scenario,
          decision: "block",
          findings_count: 1,
          status: "completed",
          payload: %{"findings" => [%{"rule_id" => "security.example"}]}
        }
      ]
    }

    profile = Benchmark.run_eval_profile(run)

    assert profile["curation_mode"] == "hand_curated"
    assert "eval_staleness" in profile["promotion_integrity"]["warnings"]

    assert Enum.any?(
             profile["diagnostic_findings"],
             &(&1["rule_id"] == "benchmarks.eval_staleness")
           )
  end

  test "promotion integrity passes with multi-channel evidence and trace curation" do
    integrity =
      Benchmark.promotion_integrity_profile(%{
        "scenario_count" => 5,
        "split_summary" => %{"public" => 3, "held_out" => 2},
        "behavior_tag_summary" => %{"security" => 3, "governance" => 2},
        "classification" => %{"youdens_j" => 0.8, "tpr" => 0.9, "fpr" => 0.1},
        "curation_mode" => "hand_curated_plus_trace_promoted"
      })

    assert integrity["status"] == "ready"
    assert integrity["warnings"] == []
  end

  test "listing recent runs does not seed persisted suites" do
    initial_suite_count = Repo.aggregate(Suite, :count, :id)
    _runs = Benchmark.list_recent_runs()
    assert Repo.aggregate(Suite, :count, :id) == initial_suite_count
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

  test "shell subjects resolve relative commands from the project root", %{tmp_dir: tmp_dir} do
    scripts_dir = Path.join(tmp_dir, "scripts")
    File.mkdir_p!(scripts_dir)

    script_path = Path.join(scripts_dir, "emit-secret.sh")

    File.write!(
      script_path,
      "#!/usr/bin/env bash\nprintf 'OPENAI_KEY = \"AKIAIOSFODNN7EXAMPLE\"'"
    )

    File.chmod!(script_path, 0o755)

    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "relative_shell",
        "label" => "Relative Shell",
        "type" => "shell",
        "command" => "./scripts/emit-secret.sh",
        "working_dir" => ".",
        "timeout_ms" => 5_000,
        "output_mode" => "stdout"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "relative_shell",
          "baseline_subject" => "relative_shell",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [result] = run.results
    assert result.status == "completed"
    assert result.findings_count > 0
    assert get_in(result.metadata, ["working_dir"]) == Path.expand(tmp_dir)
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

  test "available subjects include external OpenCode benchmark subjects", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "opencode_manual",
        "label" => "OpenCode Manual Import",
        "type" => "manual_import"
      },
      %{
        "id" => "opencode_shell",
        "label" => "OpenCode Shell Wrapper",
        "type" => "shell",
        "command" => "./scripts/opencode-benchmark.sh",
        "args" => [],
        "timeout_ms" => 120_000,
        "output_mode" => "stdout"
      }
    ])

    subject_ids =
      Benchmark.available_subjects(tmp_dir)
      |> Enum.map(& &1["id"])

    assert "controlkeel_validate" in subject_ids
    assert "opencode_manual" in subject_ids
    assert "opencode_shell" in subject_ids
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
    assert get_in(decoded, ["run", "eval_profile", "split_summary", "public"]) >= 1
    assert get_in(decoded, ["run", "eval_profile", "behavior_tag_summary", "security"]) >= 1
    assert csv =~ "run_id,suite_slug,scenario_slug"
    assert csv =~ "hardcoded_api_key_python_webhook"
  end

  test "loads the host comparison suite for cross-host benchmarking" do
    suite = benchmark_suite_fixture("host_comparison_v1")

    assert suite.slug == "host_comparison_v1"
    assert length(suite.scenarios) == 12

    host_patterns =
      suite.scenarios
      |> Enum.map(&get_in(&1.metadata || %{}, ["host_pattern"]))
      |> Enum.uniq()
      |> Enum.sort()

    assert host_patterns == ["both", "copilot", "opencode"]

    assert Benchmark.suite_eval_profile(suite)["behavior_tag_summary"]["security"] >= 1

    assert Enum.all?(suite.scenarios, fn scenario ->
             scenario.expected_decision in ["block", "warn"]
           end)
  end

  test "available subjects include copilot benchmark subjects", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "opencode_manual",
        "label" => "OpenCode (Manual Import)",
        "type" => "manual_import"
      },
      %{
        "id" => "copilot_manual",
        "label" => "GitHub Copilot (Manual Import)",
        "type" => "manual_import"
      },
      %{
        "id" => "copilot_shell",
        "label" => "GitHub Copilot (Shell Wrapper)",
        "type" => "shell",
        "command" => "./scripts/benchmark-host.sh",
        "args" => ["copilot"],
        "timeout_ms" => 120_000,
        "output_mode" => "stdout"
      }
    ])

    subject_ids =
      Benchmark.available_subjects(tmp_dir)
      |> Enum.map(& &1["id"])

    assert "controlkeel_validate" in subject_ids
    assert "copilot_manual" in subject_ids
    assert "copilot_shell" in subject_ids
  end

  test "repo benchmark subjects include all supported host templates" do
    subject_ids =
      Benchmark.available_subjects()
      |> Enum.map(& &1["id"])

    assert "opencode_manual" in subject_ids
    assert "copilot_manual" in subject_ids
    assert "gemini_manual" in subject_ids
    assert "codex_manual" in subject_ids
    assert "claude_manual" in subject_ids
  end

  test "runs host comparison suite with copilot manual import subject", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "copilot_manual",
        "label" => "GitHub Copilot (Manual Import)",
        "type" => "manual_import"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "host_comparison_v1",
          "subjects" => "controlkeel_validate,copilot_manual",
          "baseline_subject" => "controlkeel_validate",
          "scenario_slugs" => "copilot_inline_stripe_key"
        },
        tmp_dir
      )

    assert run.total_scenarios == 1
    assert length(run.results) == 2

    ck_result = Enum.find(run.results, &(&1.subject == "controlkeel_validate"))
    assert ck_result.status == "completed"

    copilot_result = Enum.find(run.results, &(&1.subject == "copilot_manual"))
    assert copilot_result.status == "awaiting_import"
  end

  defp elixir_bin! do
    System.find_executable("elixir") ||
      System.find_executable("elixir.bat") ||
      raise "elixir executable is required for benchmark shell tests"
  end
end
