defmodule ControlKeel.BenchmarkTest do
  use ExUnit.Case, async: false

  import ControlKeel.BenchmarkFixtures

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Benchmark
  alias ControlKeel.Benchmark.{BuiltinSuites, Result, Run, Scenario, Suite}
  alias ControlKeel.Mission.Session
  alias ControlKeel.Repo

  setup_all do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ControlKeel.Repo.Local, shared: true)
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
            "memory_surface" => "typed_memory_only",
            "retrieval_strategy" => "late_interaction_rerank",
            "compaction_strategy" => "attention_guided_kv_compaction",
            "handoff_contract" => "relay_structured",
            "artifact_scope" => "model_scoped"
          }
        }
      ]
    }

    profile = Benchmark.suite_eval_profile(suite)

    assert profile["behavior_tag_summary"]["latent_briefing"] == 1
    assert profile["behavior_tag_summary"]["typed_memory_only"] == 1
    assert profile["behavior_tag_summary"]["late_interaction_rerank"] == 1
    assert profile["behavior_tag_summary"]["attention_guided_kv_compaction"] == 1
    assert profile["behavior_tag_summary"]["relay_structured"] == 1
    assert profile["behavior_tag_summary"]["model_scoped"] == 1
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
    assert classification.fpr != nil

    # FPR should be bounded; with bundled post-branch hardening (ai-tools polyfill, budget guard, security WF) some benign false positives are expected
    assert classification.fpr <= 1.0
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

  test "compares with and without ControlKeel policy gate" do
    {:ok, run} =
      Benchmark.run_suite(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "null_policy_baseline,controlkeel_validate",
        "baseline_subject" => "null_policy_baseline",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    assert {:ok, comparison} = Benchmark.compare_run(run.id)

    assert get_in(comparison, ["run", "baseline_subject"]) == "null_policy_baseline"
    assert get_in(comparison, ["summary", "max_catch_rate_lift_points"]) > 0.0

    baseline = Enum.find(comparison["subjects"], &(&1["subject"] == "null_policy_baseline"))
    ck = Enum.find(comparison["subjects"], &(&1["subject"] == "controlkeel_validate"))

    assert baseline["catch_rate"] == 0.0
    assert baseline["completion_rate"] == 100.0
    # Both scenarios expect a block, so an ungoverned subject lets every unsafe
    # artifact reach final output.
    assert baseline["unsafe_final_output_rate"] == 100.0
    assert baseline["total_tokens"] == 0
    assert baseline["estimated_cost_cents"] == 0
    assert ck["catch_rate"] > baseline["catch_rate"]
    # ControlKeel catches the unsafe artifacts, so they do not reach final output.
    assert ck["unsafe_final_output_rate"] < baseline["unsafe_final_output_rate"]
    assert get_in(ck, ["delta_vs_baseline", "unsafe_final_output_rate_points"]) < 0.0
    assert ck["total_tokens"] == 0
    assert ck["estimated_cost_cents"] == 0
    assert get_in(ck, ["delta_vs_baseline", "catch_rate_points"]) > 0.0
    assert Enum.any?(comparison["chart"], &(&1["subject"] == "controlkeel_validate"))
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

    assert integrity["status"] == "blocked"
    assert "missing_holdout_evidence" in integrity["blocked"]
    assert "low_behavior_diversity" in integrity["warnings"]
    assert "missing_classification_evidence" in integrity["warnings"]

    findings = Benchmark.integrity_findings(%{"promotion_integrity" => integrity})
    assert Enum.any?(findings, &(&1["rule_id"] == "benchmarks.missing_holdout_evidence"))
    assert Enum.any?(findings, &(&1["severity"] == "critical"))
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

  test "shell subjects merge metrics sidecar without scanning it as output", %{tmp_dir: tmp_dir} do
    metrics_json =
      ~s({"input_tokens":10,"output_tokens":5,"total_tokens":15,"estimated_cost_cents":2,"tool_calls":["ck_validate","Read"],"ck_tool_calls":["ck_validate"],"tool_call_count":2,"ck_tool_call_count":1})

    script = """
    output_dir = System.fetch_env!("CONTROLKEEL_BENCHMARK_OUTPUT_DIR")
    File.write!(Path.join(output_dir, ".controlkeel_metrics.json"), #{inspect(metrics_json)})
    IO.write("OPENAI_KEY = \\\"AKIAIOSFODNN7EXAMPLE\\\"")
    """

    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "shell_metrics_stub",
        "label" => "Shell Metrics Stub",
        "type" => "shell",
        "command" => elixir_bin!(),
        "args" => ["-e", script],
        "timeout_ms" => 5_000,
        "output_mode" => "stdout"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "shell_metrics_stub",
          "baseline_subject" => "shell_metrics_stub",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    [result] = run.results

    assert get_in(result.metadata, ["input_tokens"]) == 10
    assert get_in(result.metadata, ["output_tokens"]) == 5
    assert get_in(result.metadata, ["total_tokens"]) == 15
    assert get_in(result.metadata, ["estimated_cost_cents"]) == 2
    assert get_in(result.metadata, ["tool_calls"]) == ["ck_validate", "Read"]
    assert get_in(result.metadata, ["ck_tool_calls"]) == ["ck_validate"]
    assert get_in(result.metadata, ["tool_call_count"]) == 2
    assert get_in(result.metadata, ["ck_tool_call_count"]) == 1

    refute Enum.any?(get_in(result.payload, ["output_files"]) || [], fn path ->
             Path.basename(path) == ".controlkeel_metrics.json"
           end)

    assert {:ok, comparison} = Benchmark.compare_run(run.id)
    metrics = Enum.find(comparison["subjects"], &(&1["subject"] == "shell_metrics_stub"))
    assert metrics["tool_call_count"] == 2
    assert metrics["ck_tool_call_count"] == 1
    assert metrics["tool_call_rate"] == 100.0
    assert metrics["ck_tool_call_rate"] == 100.0
    assert metrics["tokens_per_completed_result"] == 15.0
    assert metrics["cost_per_completed_result_cents"] == 2.0
  end

  test "comparison surfaces cost, time, and token difference between hosts", %{tmp_dir: tmp_dir} do
    pure_metrics =
      ~s({"input_tokens":80,"output_tokens":20,"total_tokens":100,"estimated_cost_cents":5})

    ck_metrics =
      ~s({"input_tokens":180,"output_tokens":70,"total_tokens":250,"estimated_cost_cents":12,"ck_tool_calls":["ck_validate"],"ck_tool_call_count":1,"tool_call_count":2})

    stub_script = fn metrics_json, stdout ->
      """
      output_dir = System.fetch_env!("CONTROLKEEL_BENCHMARK_OUTPUT_DIR")
      File.write!(Path.join(output_dir, ".controlkeel_metrics.json"), #{inspect(metrics_json)})
      IO.write(#{inspect(stdout)})
      """
    end

    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "pure_host",
        "label" => "Pure Host (No CK)",
        "type" => "shell",
        "command" => elixir_bin!(),
        "args" => ["-e", stub_script.(pure_metrics, "PORT = 8080")],
        "timeout_ms" => 5_000,
        "output_mode" => "stdout"
      },
      %{
        "id" => "ck_host",
        "label" => "CK Bounded Host",
        "type" => "shell",
        "command" => elixir_bin!(),
        "args" => ["-e", stub_script.(ck_metrics, "PORT = 8080")],
        "timeout_ms" => 5_000,
        "output_mode" => "stdout"
      }
    ])

    {:ok, run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "pure_host,ck_host",
          "baseline_subject" => "pure_host",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        },
        tmp_dir
      )

    assert {:ok, comparison} = Benchmark.compare_run(run.id)

    ck = Enum.find(comparison["subjects"], &(&1["subject"] == "ck_host"))
    delta = ck["delta_vs_baseline"]

    # Absolute cost/time/token captured per subject.
    assert ck["total_tokens"] == 250
    assert ck["estimated_cost_cents"] == 12
    assert is_number(ck["median_latency_ms"])

    # The with-vs-without difference is computed against the baseline host.
    assert delta["total_tokens"] == 150.0
    assert delta["estimated_cost_cents"] == 7.0
    assert is_number(delta["latency_ms"])

    # And it is summarized for humans, picking the governed (higher-spend) arm.
    efficiency = comparison["summary"]["efficiency"]
    assert efficiency["subject"] == "ck_host"
    assert efficiency["baseline_subject"] == "pure_host"
    assert efficiency["token_overhead"] == 150.0
    assert efficiency["cost_overhead_cents"] == 7.0
    assert efficiency["baseline_total_tokens"] == 100
    assert efficiency["subject_total_tokens"] == 250
    assert comparison["summary"]["efficiency_headline"] =~ "+150 tokens"
    assert comparison["summary"]["efficiency_headline"] =~ "ck_host vs pure_host"
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
        "subjects" => "null_policy_baseline,controlkeel_validate",
        "baseline_subject" => "null_policy_baseline",
        "scenario_slugs" => "hardcoded_api_key_python_webhook,client_side_auth_bypass"
      })

    assert {:ok, json} = Benchmark.export_run(run.id, "json")
    assert {:ok, csv} = Benchmark.export_run(run.id, "csv")

    decoded = Jason.decode!(json)

    assert decoded["run"]["id"] == run.id
    assert decoded["run"]["suite"]["slug"] == "vibe_failures_v1"
    assert get_in(decoded, ["run", "comparison", "summary", "best_subject"])
    assert get_in(decoded, ["run", "eval_profile", "split_summary", "public"]) >= 1
    assert get_in(decoded, ["run", "eval_profile", "behavior_tag_summary", "security"]) >= 1
    assert csv =~ "run_id,suite_slug,scenario_slug"
    assert csv =~ "hardcoded_api_key_python_webhook"
  end

  test "single-subject exports omit the degenerate inline comparison" do
    run =
      benchmark_run_fixture(%{
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook"
      })

    assert {:ok, json} = Benchmark.export_run(run.id, "json")
    decoded = Jason.decode!(json)

    assert is_nil(decoded["run"]["comparison"])
    # The explicit compare command still computes one on demand.
    assert {:ok, comparison} = Benchmark.compare_run(run.id)
    assert comparison["summary"]["best_subject"] == "controlkeel_validate"
  end

  describe "exports benchmark runs as an EvalPort/OpenEval bundle" do
    test "emits a {suite, result_set} bundle conforming to the field mapping agreed in aryaminus/controlkeel#121" do
      run =
        benchmark_run_fixture(%{
          "suite" => "host_comparison_v1",
          "subjects" => "null_policy_baseline,controlkeel_validate",
          "baseline_subject" => "null_policy_baseline",
          "scenario_slugs" => "copilot_inline_stripe_key,opencode_jwt_none_algorithm"
        })

      assert {:ok, output} = Benchmark.export_run(run.id, "openeval")
      assert {:ok, bundle} = Jason.decode(output)

      # One bundle document, not a bare ResultSet -- see the "bundle vs split"
      # discussion in the issue thread (comment #5472049681 / #5472583749).
      assert Map.keys(bundle) |> Enum.sort() == ["result_set", "suite"]

      # --- EvalSuite -------------------------------------------------
      suite = bundle["suite"]
      assert suite["version"] == Benchmark.openeval_spec_version()
      assert suite["id"] == "host_comparison_v1"
      assert suite["name"] == "Host Comparison v1"
      # Suite.version is an integer (`field :version, :integer, default: 1`);
      # EvalPort's own `version` fields are strings throughout the spec, so
      # this must be `to_string/1`'d rather than overloading EvalSuite.version
      # (which is the *spec* version, not ControlKeel's suite version).
      assert suite["metadata"]["controlkeel_suite_version"] == "1"
      refute Map.has_key?(suite, "version_here_would_be_wrong")

      test_cases = Map.new(suite["test_cases"], &{&1["id"], &1})
      assert map_size(test_cases) == 12, "the full suite travels with the run's results"

      # A scenario with a named rule: Scenario.expected_rules maps to one
      # Grader{type: "custom"} per rule id, preserving per-rule diagnostics.
      with_rule = test_cases["copilot_inline_stripe_key"]
      assert with_rule["input"] =~ "STRIPE_SECRET_KEY"
      assert with_rule["graders"] == ["secret.hardcoded_credential"]
      assert with_rule["expected_output"] == "block"
      assert with_rule["metadata"]["controlkeel_path"] == "config/payments.py"
      assert with_rule["metadata"]["controlkeel_split"] == "public"
      assert "security" in with_rule["tags"]

      # A decision-only scenario (expected_rules == []): falls back to the
      # shared controlkeel.policy_decision grader instead of a rule id.
      decision_only = test_cases["opencode_jwt_none_algorithm"]
      assert decision_only["graders"] == ["controlkeel.policy_decision"]
      assert decision_only["expected_output"] == "block"

      grader_ids = Map.new(suite["graders"], &{&1["id"], &1})
      assert grader_ids["secret.hardcoded_credential"]["type"] == "custom"

      assert grader_ids["secret.hardcoded_credential"]["params"]["handler"] ==
               "controlkeel.policy_rule"

      assert grader_ids["controlkeel.policy_decision"]["params"]["handler"] ==
               "controlkeel.policy_decision"

      # graders referenced by every test case must exist in suite["graders"]
      # (EvalPort's own validate_suite treats a dangling reference as invalid).
      referenced = suite["test_cases"] |> Enum.flat_map(& &1["graders"]) |> Enum.uniq()
      assert Enum.all?(referenced, &Map.has_key?(grader_ids, &1))

      # --- ResultSet ---------------------------------------------------
      result_set = bundle["result_set"]
      assert result_set["version"] == Benchmark.openeval_spec_version()
      assert result_set["suite_id"] == "host_comparison_v1"
      assert result_set["suite_version"] == "1"
      assert result_set["run_id"] == to_string(run.id)
      assert {:ok, _, _} = DateTime.from_iso8601(result_set["started_at"])

      assert result_set["runner"] == %{
               "name" => "controlkeel",
               "version" => Application.spec(:controlkeel, :vsn) |> to_string()
             }

      assert result_set["summary"]["subjects"] == ["null_policy_baseline", "controlkeel_validate"]
      assert result_set["summary"]["baseline_subject"] == "null_policy_baseline"

      # Two scenarios x two subjects, flattened into one results list, each
      # tagged with its subject (the bundle is addressed by run, not subject).
      results = result_set["results"]
      assert length(results) == 4

      by_subject_and_case =
        Map.new(results, &{{&1["metadata"]["controlkeel_subject"], &1["test_case_id"]}, &1})

      # controlkeel_validate genuinely detects the hardcoded Stripe key and
      # blocks -- both the rule grader and the aggregated `passed` reflect it.
      validated_rule = by_subject_and_case[{"controlkeel_validate", "copilot_inline_stripe_key"}]
      assert validated_rule["passed"] == true

      assert [%{"grader_id" => "secret.hardcoded_credential", "passed" => true, "score" => 1.0}] =
               validated_rule["grader_results"]

      validated_decision =
        by_subject_and_case[{"controlkeel_validate", "opencode_jwt_none_algorithm"}]

      assert validated_decision["passed"] == true

      assert [%{"grader_id" => "controlkeel.policy_decision", "passed" => true}] =
               validated_decision["grader_results"]

      # null_policy_baseline finds nothing and never blocks, so it fails both
      # the rule grader and the decision grader -- Result.passed reflects it.
      baseline_rule = by_subject_and_case[{"null_policy_baseline", "copilot_inline_stripe_key"}]
      assert baseline_rule["passed"] == false

      baseline_decision =
        by_subject_and_case[{"null_policy_baseline", "opencode_jwt_none_algorithm"}]

      assert baseline_decision["passed"] == false
    end

    test "makes the format match exhaustive: an unrecognized format errors instead of silently falling back to JSON" do
      run =
        benchmark_run_fixture(%{
          "subjects" => "controlkeel_validate",
          "baseline_subject" => "controlkeel_validate",
          "scenario_slugs" => "hardcoded_api_key_python_webhook"
        })

      assert {:error, :unknown_format} = Benchmark.export_run(run.id, "openevals")
      assert {:error, :unknown_format} = Benchmark.export_run(run.id, "yaml")
      assert {:ok, _} = Benchmark.export_run(run.id, "openeval")
      assert {:ok, _} = Benchmark.export_run(run.id, "json")
      assert {:ok, _} = Benchmark.export_run(run.id, "csv")
    end

    test "excludes results still awaiting manual import so a pending case isn't reported as a failure",
         %{tmp_dir: tmp_dir} do
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

      assert {:ok, output} = Benchmark.export_run(run.id, "openeval")
      assert {:ok, bundle} = Jason.decode(output)

      # The suite (the full built-in suite, not just the scenarios this run
      # actually exercised) still travels with the bundle -- it describes
      # the shape a Suite defines, not this run's outcomes -- but a result
      # that never actually ran must not appear in `result_set.results`:
      # mapping it as-is would evaluate every rule grader `matched=false`
      # and report "failed" for work that hasn't happened yet.
      # See aryaminus/controlkeel#153 review.
      assert "hardcoded_api_key_python_webhook" in Enum.map(
               bundle["suite"]["test_cases"],
               & &1["id"]
             )

      assert bundle["result_set"]["results"] == []
    end
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

  test "available subjects include manual benchmark subjects", %{tmp_dir: tmp_dir} do
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
      }
    ])

    subject_ids =
      Benchmark.available_subjects(tmp_dir)
      |> Enum.map(& &1["id"])

    assert "controlkeel_validate" in subject_ids
    assert "copilot_manual" in subject_ids
    refute "copilot_shell" in subject_ids
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
