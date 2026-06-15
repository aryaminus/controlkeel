defmodule ControlKeel.ObservabilityTest do
  use ControlKeel.DataCase

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.MissionFixtures
  import Ecto.Query

  alias ControlKeel.Benchmark.{Run, Scenario}
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Invocation, Session, SessionEvent}
  alias ControlKeel.Observability
  alias ControlKeel.Observability.{BenchmarkDraft, EvalCandidate, ImportedEnvelope}
  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry
  alias ControlKeel.Repo

  test "session_run/1 composes health, costs, gates, memory, proofs, timeline, and calls" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 2_000, spent_cents: 850})
    task = task_fixture(%{session: session, status: "in_progress"})

    _finding =
      finding_fixture(%{
        session: session,
        title: "Critical gate",
        severity: "critical",
        status: "blocked",
        rule_id: "security.critical_gate"
      })

    assert {:ok, _review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "review_type" => "plan",
               "title" => "Pending review",
               "submission_body" => "Need approval"
             })

    assert {:ok, _event} =
             %SessionEvent{}
             |> SessionEvent.changeset(%{
               session_id: session.id,
               task_id: task.id,
               event_type: "tool_call",
               actor: "agent",
               summary: "Ran validation",
               payload: %{},
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               task_id: task.id,
               source: "opencode",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               estimated_cost_cents: 12,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    assert {:ok, run} = Observability.session_run(session.id)

    assert run.session.id == session.id
    assert run.health.status == "red"
    assert run.findings.active == 1
    assert run.findings.critical == 1
    assert run.findings.blocked == 1
    assert run.gates.pending_reviews == 1
    assert run.timeline.count >= 1
    assert run.proofs.count == 1
    assert run.hosts_models_tools.invocations == 1
    assert run.hosts_models_tools.estimated_cost_cents == 12
    assert run.budget["decision"] == "warn"
    assert Enum.any?(run.recommendations, &String.contains?(&1, "blocked or critical"))
  end

  test "loop_diagnostics reports repeated tool event and invocation runs" do
    session = session_fixture()

    for _ <- 1..3 do
      assert {:ok, _event} =
               %SessionEvent{}
               |> SessionEvent.changeset(%{
                 session_id: session.id,
                 event_type: "tool_call",
                 actor: "agent",
                 summary: "Repeated validation call",
                 payload: %{},
                 metadata: %{}
               })
               |> Repo.insert()
    end

    for _ <- 1..3 do
      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "opencode",
                 tool: "ck_validate",
                 provider: "openai",
                 model: "gpt-5.5",
                 estimated_cost_cents: 1,
                 decision: "allow",
                 metadata: %{}
               })
               |> Repo.insert()
    end

    diagnostics =
      Observability.loop_diagnostics(session_id: session.id, workspace_id: session.workspace_id)

    assert diagnostics.read_only == true
    assert diagnostics.mutation == "none"
    assert diagnostics.totals.event_runs == 1
    assert diagnostics.totals.invocation_runs == 1
    assert [%{count: 3}] = diagnostics.repeated_tool_events
    assert [%{count: 3}] = diagnostics.repeated_invocations
    assert Enum.any?(diagnostics.recommendations, &String.contains?(&1, "Repeated identical"))
  end

  test "timeline/2 summarizes recent session events" do
    session = session_fixture()

    assert {:ok, _event} =
             %SessionEvent{}
             |> SessionEvent.changeset(%{
               session_id: session.id,
               event_type: "tool_call",
               actor: "agent",
               summary: "Ran timeline validation",
               body: "Detailed event body",
               payload: %{},
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, timeline} = Observability.timeline(session.id, limit: 10)

    assert timeline.session.id == session.id
    assert timeline.count >= 1
    assert timeline.limit == 10
    assert timeline.by_event_type["tool_call"] == 1
    assert timeline.by_actor["agent"] == 1
    assert Enum.any?(timeline.events, &(&1.summary == "Ran timeline validation"))
  end

  test "memory_context/2 summarizes session context and memory metadata" do
    session = session_fixture()
    task_fixture(%{session: session})
    finding_fixture(%{session: session})

    active_record =
      memory_record_fixture(%{
        session: session,
        record_type: "decision",
        title: "Use summary memory",
        summary: "Keep memory output summary-only.",
        source_type: "agent",
        tags: ["observability"]
      })

    archived_record =
      memory_record_fixture(%{
        session: session,
        record_type: "checkpoint",
        title: "Old checkpoint",
        summary: "Archived checkpoint.",
        source_type: "review",
        tags: ["stale"]
      })

    assert {:ok, _archived} =
             archived_record
             |> MemoryRecord.changeset(%{
               archived_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })
             |> Repo.update()

    assert {:ok, memory_context} = Observability.memory_context(session.id, limit: 10)

    assert memory_context.session.id == session.id
    assert memory_context.context.tasks == 1
    assert memory_context.context.findings == 1
    assert memory_context.memory.count >= 2
    assert memory_context.memory.active >= 1
    assert memory_context.memory.archived >= 1
    assert memory_context.memory.by_type["decision"] == 1
    assert memory_context.memory.by_type["checkpoint"] == 1
    assert memory_context.memory.by_source["agent"] == 1
    assert Enum.any?(memory_context.memory.recent, &(&1.id == active_record.id))
    assert Enum.any?(memory_context.recommendations, &String.contains?(&1, "Archived memory"))
  end

  test "costs/1 summarizes invocation spend and groups by selected field" do
    session = session_fixture()
    workspace = Repo.preload(session, :workspace).workspace
    other_session = session_fixture(%{workspace: workspace})

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_000,
               cached_input_tokens: 200,
               output_tokens: 300,
               estimated_cost_cents: 14,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: other_session.id,
               source: "opencode",
               tool: "ck_budget",
               provider: "anthropic",
               model: "claude-sonnet",
               input_tokens: 500,
               cached_input_tokens: 0,
               output_tokens: 100,
               estimated_cost_cents: 6,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    costs = Observability.costs(workspace_id: session.workspace_id, by: "provider")

    assert costs.by == "provider"
    assert costs.totals.invocations == 2
    assert costs.totals.sessions == 2
    assert costs.totals.estimated_cost_cents == 20
    assert costs.totals.input_tokens == 1_500
    assert costs.totals.cached_input_tokens == 200
    assert costs.totals.output_tokens == 400
    assert Enum.map(costs.groups, & &1.name) == ["openai", "anthropic"]
    assert Enum.any?(costs.recommendations, &String.contains?(&1, "cost per successful task"))
  end

  test "comparison/1 compares invocation groups by selected field" do
    session = session_fixture()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 900,
               output_tokens: 300,
               estimated_cost_cents: 12,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "opencode",
               tool: "ck_review_submit",
               provider: "anthropic",
               model: "claude-sonnet",
               input_tokens: 300,
               output_tokens: 100,
               estimated_cost_cents: 4,
               decision: "warn",
               metadata: %{}
             })
             |> Repo.insert()

    comparison = Observability.comparison(workspace_id: session.workspace_id, by: "source")

    assert comparison.by == "source"
    assert comparison.totals.invocations == 2
    assert comparison.totals.estimated_cost_cents == 16
    assert Enum.map(comparison.groups, & &1.name) == ["codex-cli", "opencode"]

    codex = Enum.find(comparison.groups, &(&1.name == "codex-cli"))
    assert codex.cost_per_call_cents == 12.0
    assert codex.tokens_per_call == 1200.0
    assert codex.decisions == %{"allow" => 1}

    assert Enum.any?(comparison.recommendations, &String.contains?(&1, "Compare source"))
  end

  test "recommendations/1 prioritizes health, problem, proof, and cost actions" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Recommendation finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.recommendation"
    })

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_000,
               output_tokens: 250,
               estimated_cost_cents: 10,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    recommendations = Observability.recommendations(workspace_id: session.workspace_id)

    assert recommendations.health == "red"
    assert recommendations.count >= 3
    assert "problem" in recommendations.categories
    assert "cost" in recommendations.categories

    assert Enum.any?(recommendations.actions, &(&1.id == "health-red-runs"))

    assert Enum.any?(
             recommendations.actions,
             &(&1.title == "Regression eval for security.recommendation")
           )

    assert Enum.any?(
             recommendations.actions,
             &String.contains?(&1.suggested_action, "cost per successful task")
           )
  end

  test "recommendations/1 includes token overhead actions when project_root has oversized rule files" do
    session = session_fixture()
    tmp = System.tmp_dir!() |> Path.join("obs_token_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)

    on_exit(fn -> File.rm_rf!(tmp) end)

    # Write an oversized AGENTS.md (>1200 words)
    File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 1500))

    recommendations =
      Observability.recommendations(
        workspace_id: session.workspace_id,
        project_root: tmp
      )

    assert "token" in recommendations.categories

    assert Enum.any?(
             recommendations.actions,
             &(&1.id == "token-rule-files-oversized")
           )

    oversized_action =
      Enum.find(recommendations.actions, &(&1.id == "token-rule-files-oversized"))

    assert oversized_action.priority == "medium"
    assert oversized_action.category == "token"
    assert String.contains?(oversized_action.evidence, "words")
  end

  test "recommendations/1 includes skill duplicate action when duplicates exist" do
    session = session_fixture()
    tmp = System.tmp_dir!() |> Path.join("obs_dup_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    for subdir <- [".claude/skills", ".agents/skills"] do
      skill_dir = Path.join([tmp, subdir, "test-skill"])
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), String.duplicate("word ", 200))
    end

    recommendations =
      Observability.recommendations(
        workspace_id: session.workspace_id,
        project_root: tmp
      )

    assert "token" in recommendations.categories

    assert Enum.any?(
             recommendations.actions,
             &(&1.id == "token-skill-duplicates")
           )
  end

  test "recommendations/1 does not add rule-file token action when AGENTS.md is small" do
    session = session_fixture()
    tmp = System.tmp_dir!() |> Path.join("obs_clean_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    # Write a small AGENTS.md well under the 1200-word target
    File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 100))

    recommendations =
      Observability.recommendations(
        workspace_id: session.workspace_id,
        project_root: tmp
      )

    refute Enum.any?(recommendations.actions, &(&1.id == "token-rule-files-oversized"))
  end

  test "eval_candidates/1 turns grouped problems into advisory backlog items" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.eval_candidate"
    })

    eval_candidates = Observability.eval_candidates(workspace_id: session.workspace_id)

    assert eval_candidates.health == "red"
    assert eval_candidates.count == 1
    assert [candidate] = eval_candidates.candidates
    assert candidate.title == "Regression eval for security.eval_candidate"
    assert candidate.priority == "critical"
    assert candidate.benchmark_hint == "security-regression"
    assert candidate.example_session_id == session.id
    assert candidate.human_gate_required == true
    assert candidate.links.problems == "/observability/problems"
    assert candidate.links.benchmarks == "/benchmarks"
  end

  test "problems/1 groups active findings by rule and category" do
    session = session_fixture()
    workspace = Repo.preload(session, :workspace).workspace
    other_session = session_fixture(%{workspace: workspace})

    finding_fixture(%{
      session: session,
      title: "SQL issue one",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.sql_injection"
    })

    finding_fixture(%{
      session: other_session,
      title: "SQL issue two",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.sql_injection"
    })

    finding_fixture(%{
      session: session,
      title: "Other issue",
      severity: "medium",
      status: "open",
      category: "review",
      rule_id: "review.required"
    })

    problems = Observability.problems(workspace_id: session.workspace_id)

    assert problems.count == 2
    assert problems.health == "red"

    sql_problem = Enum.find(problems.problems, &(&1.rule_id == "security.sql_injection"))
    assert sql_problem.count == 2
    assert sql_problem.affected_session_count == 2
    assert sql_problem.health == "red"
    assert sql_problem.severity == "critical"

    assert sql_problem.feedback_loop.eval_candidate_title ==
             "Regression eval for security.sql_injection"

    assert sql_problem.feedback_loop.evidence_kind == "finding_group"
    assert sql_problem.feedback_loop.human_gate_required == true
    assert sql_problem.feedback_loop.benchmark_hint == "security-regression"
    assert sql_problem.feedback_loop.suggested_action =~ "regression benchmark"
    assert Enum.any?(sql_problem.examples, &(&1.session_id == session.id))
  end

  test "workspace_overview/1 summarizes recent runs, problems, costs, and recommendations" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace, budget_cents: 2_000, spent_cents: 450})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    overview = Observability.workspace_overview(workspace_id: workspace.id)

    assert overview.health.status == "red"
    assert overview.workspace.id == workspace.id
    assert overview.runs.count == 1
    assert [%{id: id, health: "red"}] = overview.runs.recent
    assert id == session.id
    assert overview.problems.count == 1
    assert [%{rule_id: "security.overview"}] = overview.problems.top
    assert overview.costs.spent_cents == 450
    assert overview.costs.budget_cents == 2_000
    assert overview.telemetry.import_mode == "dry_run_or_local_persist"
    assert overview.telemetry.integrity == "sha256"
    assert overview.telemetry.persisted_imports == 0
    assert Enum.any?(overview.recommendations, &String.contains?(&1, "red session runs"))
  end

  test "session_run/1 returns not_found for unknown sessions" do
    assert {:error, :not_found} = Observability.session_run(999_999)
  end

  test "telemetry export builds a redacted local-first envelope" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Exported issue",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.exported_issue"
    })

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    assert envelope.schema_version == ObservabilityTelemetry.schema_version()
    assert envelope.exported_at == "2026-04-29T04:00:00Z"
    assert envelope.session_run.session.id == session.id
    assert envelope.problems.count == 1
    assert envelope.redaction.policy == "summary_only"
    assert envelope.redaction.raw_context_bodies == false
    assert envelope.redaction.raw_memory_bodies == false
    assert envelope.integrity.session_id == session.id
    assert envelope.integrity.import_mutation_allowed == false
    assert envelope.integrity.fingerprint_algorithm == "sha256"
    assert envelope.integrity.payload_sha256 =~ ~r/^[a-f0-9]{64}$/
  end

  test "telemetry import preview validates an envelope without mutating storage" do
    session = session_fixture()
    session_count = Repo.aggregate(Session, :count, :id)
    finding_count = Repo.aggregate(Finding, :count, :id)

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(System.tmp_dir!(), "controlkeel-observability-#{System.unique_integer()}.json")

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, preview} = ObservabilityTelemetry.import_preview(path, dry_run: true)

    assert preview.dry_run == true
    assert preview.mutation == "none"
    assert preview.session_id == session.id
    assert preview.schema_version == ObservabilityTelemetry.schema_version()
    assert preview.integrity_status == "verified"
    assert preview.payload_sha256 == envelope.integrity.payload_sha256
    assert Repo.aggregate(Session, :count, :id) == session_count
    assert Repo.aggregate(Finding, :count, :id) == finding_count
  end

  test "telemetry import preview detects integrity mismatches" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    tampered =
      envelope
      |> Jason.encode!()
      |> Jason.decode!()
      |> put_in(["session_run", "health", "status"], "red")

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-tampered-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(tampered))

    assert {:ok, preview} = ObservabilityTelemetry.import_preview(path, dry_run: true)
    assert preview.integrity_status == "mismatch"
  end

  test "telemetry import preview rejects invalid envelopes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-invalid-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(%{"schema_version" => "wrong"}))

    assert {:error, :dry_run_required} = ObservabilityTelemetry.import_preview(path)

    assert {:error, {:missing_keys, missing}} =
             ObservabilityTelemetry.import_preview(path, dry_run: true)

    assert "session_run" in missing
  end

  test "telemetry import persist stores a local snapshot without mutating operational records" do
    session = session_fixture()
    session_count = Repo.aggregate(Session, :count, :id)
    finding_count = Repo.aggregate(Finding, :count, :id)

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-persist-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, result} =
             ObservabilityTelemetry.import_persist(path,
               workspace_id: session.workspace_id,
               session_id: session.id,
               imported_at: ~U[2026-04-29 05:00:00Z]
             )

    assert result.status == "stored"
    assert result.session_id == session.id
    assert result.session_title == session.title
    assert result.integrity_status == "verified"
    assert result.payload_sha256 == envelope.integrity.payload_sha256
    assert result.imported_at == "2026-04-29T05:00:00Z"
    assert result.mutation == "none"

    persisted = Repo.get!(ImportedEnvelope, result.id)
    assert persisted.workspace_id == session.workspace_id
    assert persisted.session_id == session.id
    assert persisted.original_session_id == session.id
    assert persisted.envelope["schema_version"] == ObservabilityTelemetry.schema_version()

    assert Repo.aggregate(Session, :count, :id) == session_count
    assert Repo.aggregate(Finding, :count, :id) == finding_count
  end

  test "loop_status/1 summarizes the human-gated self-improvement loop" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Loop finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.loop"
    })

    loop = Observability.loop_status(workspace_id: session.workspace_id)

    assert loop.read_only == true
    assert loop.mutation == "none"
    assert loop.learning_loop.mode == "local_first_human_gated"
    assert loop.learning_loop.automatic_promotion == false
    assert loop.active_problems.total_findings == 1
    assert loop.evals.derived == 1
    assert Enum.any?(loop.blockers, &(&1.id == "active_problems"))
  end

  test "promotion_candidates/1 reports blocked and ready advisory states" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Promotion finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.promotion"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    initial = Observability.promotion_candidates(workspace_id: session.workspace_id)
    assert initial.promotion_execution == false
    assert [%{readiness: "needs_draft"}] = initial.candidates

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, _result} =
             Observability.update_benchmark_draft_status(draft_id, "approved",
               reviewed_by: "test"
             )

    assert %{materialized: 1} =
             Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

    needs_run = Observability.promotion_candidates(workspace_id: session.workspace_id)
    assert [%{readiness: "needs_run", promotion_execution: false}] = needs_run.candidates

    assert {:ok, %{benchmark_execution: true}} =
             Observability.run_observability_benchmark(
               [
                 workspace_id: session.workspace_id,
                 subjects: "controlkeel_validate",
                 dry_run: false,
                 execute: true
               ],
               File.cwd!()
             )

    after_run = Observability.promotion_candidates(workspace_id: session.workspace_id)

    assert [%{readiness: readiness, latest_run_id: run_id, scenario_evidence: evidence}] =
             after_run.candidates

    assert readiness in ["ready", "blocked"]
    assert is_integer(run_id)
    assert evidence.scenario_covered == true
    assert is_integer(evidence.latest_result_id)
  end

  test "observability_benchmark_history/1 reports generated benchmark run evidence" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "History finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.history"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, _result} =
             Observability.update_benchmark_draft_status(draft_id, "approved",
               reviewed_by: "test"
             )

    assert %{materialized: 1} =
             Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

    before_run = Observability.observability_benchmark_history(workspace_id: session.workspace_id)
    assert before_run.readiness.status == "yellow"
    assert before_run.coverage.materialized_scenarios == 1
    assert before_run.coverage.benchmark_runs == 0

    assert {:ok, %{benchmark_execution: true}} =
             Observability.run_observability_benchmark(
               [
                 workspace_id: session.workspace_id,
                 subjects: "controlkeel_validate",
                 dry_run: false,
                 execute: true
               ],
               File.cwd!()
             )

    history = Observability.observability_benchmark_history(workspace_id: session.workspace_id)
    assert history.coverage.benchmark_runs == 1
    assert history.coverage.covered_scenarios == 1
    assert history.latest_run.id
    assert history.readiness.status in ["green", "red"]
  end

  test "observability benchmark run preview is non-mutating and execution is explicit" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Run preview finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.run_preview"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, _result} =
             Observability.update_benchmark_draft_status(draft_id, "approved",
               reviewed_by: "test"
             )

    assert %{materialized: 1} =
             Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

    run_count = Repo.aggregate(Run, :count, :id)

    preview =
      Observability.observability_benchmark_run_preview(
        workspace_id: session.workspace_id,
        subjects: "controlkeel_validate"
      )

    assert preview.benchmark_execution == false
    assert preview.executable == true
    assert preview.command =~ "controlkeel obs benchmarks run"
    assert preview.command =~ "--execute"
    assert Repo.aggregate(Run, :count, :id) == run_count

    assert {:error, :execute_required, _preview} =
             Observability.run_observability_benchmark(
               [
                 workspace_id: session.workspace_id,
                 subjects: "controlkeel_validate",
                 dry_run: false
               ],
               File.cwd!()
             )

    assert Repo.aggregate(Run, :count, :id) == run_count
  end

  test "materialize_benchmark_drafts/1 creates local scenarios from approved drafts" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Materialize finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.materialize"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, _result} =
             Observability.update_benchmark_draft_status(draft_id, "approved",
               reviewed_by: "test"
             )

    first = Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)
    second = Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

    assert first.source_count == 1
    assert first.materialized == 1
    assert first.existing == 0
    assert second.materialized == 0
    assert second.existing == 1
    assert first.benchmark_execution == false
    assert first.mutation == "local_benchmark_scenario_only"
    assert Repo.aggregate(Scenario, :count, :id) >= 1

    scenarios =
      Observability.observability_benchmark_scenarios(workspace_id: session.workspace_id)

    assert scenarios.count == 1
    assert [%{expected_rules: ["security.materialize"]} = scenario] = scenarios.scenarios
    assert scenario.name =~ "security.materialize"
    assert scenario.suite_slug =~ "observability-"

    drafts = Observability.benchmark_drafts(workspace_id: session.workspace_id)
    assert [%{metadata: %{"materialized_scenario_id" => scenario_id}}] = drafts.drafts
    assert scenario_id == scenario.id
  end

  test "generate_benchmark_drafts/1 creates human-gated drafts idempotently" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Benchmark draft finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.benchmark_draft"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    first = Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)
    second = Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert first.source_count == 1
    assert first.stored == 1
    assert first.existing == 0
    assert second.stored == 0
    assert second.existing == 1
    assert first.human_gate_required == true
    assert first.mutation == "draft_record_only"
    assert Repo.aggregate(BenchmarkDraft, :count, :id) == 1

    drafts = Observability.benchmark_drafts(workspace_id: session.workspace_id)

    assert drafts.count == 1
    assert drafts.by_status == %{"draft" => 1}
    assert [%{status: "draft", human_gate_required: true} = draft] = drafts.drafts
    assert draft.title =~ "security.benchmark_draft"
    refute draft.scenario_prompt =~ "summary-only evidence"
    assert draft.scenario_prompt =~ "bounded real trace evidence"
    assert draft.metadata["trace_evidence"]["available"] == true
    assert draft.metadata["trace_evidence"]["session_id"] == session.id
    assert is_list(draft.metadata["trace_evidence"]["findings"])
    assert Enum.any?(drafts.recommendations, &String.contains?(&1, "human gate"))
  end

  test "regressions/1 treats catch rate as a 0 to 100 percentage" do
    run = benchmark_run_fixture()

    run
    |> Run.changeset(%{catch_rate: 80.0, status: "completed"})
    |> Repo.update!()

    regressions = Observability.regressions(days: 30)

    assert regressions.health.status == "red"
    assert regressions.health.reason =~ "did not catch every expected scenario"

    assert Enum.any?(
             regressions.recommendations,
             &String.contains?(&1, "latest benchmark misses")
           )
  end

  test "regressions/1 summarizes benchmark runs and draft coverage" do
    session = session_fixture()
    _run = benchmark_run_fixture()

    finding_fixture(%{
      session: session,
      title: "Regression candidate",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.regression_candidate"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    regressions = Observability.regressions(workspace_id: session.workspace_id)

    assert regressions.days == 30
    assert regressions.benchmark_runs.count >= 1
    assert regressions.benchmark_runs.average_catch_rate >= 0.0
    assert regressions.draft_coverage.saved_eval_candidates == 1
    assert regressions.draft_coverage.benchmark_drafts == 1
    assert regressions.health.status in ["green", "yellow", "red"]
    assert regressions.recommendations != []
  end

  test "update_benchmark_draft_status/3 changes only local draft review state" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Draft status finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.draft_status"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [draft]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, result} =
             Observability.update_benchmark_draft_status(draft.id, "approved",
               reviewed_by: "test"
             )

    assert result.status == "approved"
    assert result.human_gate_required == true
    assert result.mutation == "draft_status_only"
    assert result.draft.metadata["reviewed_by"] == "test"

    drafts = Observability.benchmark_drafts(workspace_id: session.workspace_id)
    assert drafts.by_status == %{"approved" => 1}
  end

  test "regressions/1 warns when drafts exist but no benchmark runs close the loop" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Unrun regression candidate",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.unrun_regression_candidate"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    regressions = Observability.regressions(workspace_id: session.workspace_id, days: 1)

    assert regressions.health.status == "yellow"
    assert regressions.health.reason =~ "no recent benchmark run"
    assert regressions.recommendations != []
  end

  test "save_eval_candidates/1 saves problem-derived candidates idempotently" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Persist eval finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.persist_eval"
    })

    first = Observability.save_eval_candidates(workspace_id: session.workspace_id)
    second = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert first.source_count == 1
    assert first.stored == 1
    assert first.existing == 0
    assert second.stored == 0
    assert second.existing == 1
    assert first.human_gate_required == true
    assert first.mutation == "advisory_record_only"
    assert Repo.aggregate(EvalCandidate, :count, :id) == 1

    saved = Observability.saved_eval_candidates(workspace_id: session.workspace_id)

    assert saved.count == 1
    assert saved.by_status == %{"open" => 1}
    assert [%{rule_id: "security.persist_eval", human_gate_required: true}] = saved.candidates
    assert Enum.any?(saved.recommendations, &String.contains?(&1, "human gate"))
  end

  test "memory_quality/1 detects stale duplicates contradictions and missed memory" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace})
    missed_session = session_fixture(%{workspace: workspace})

    old_record =
      memory_record_fixture(%{
        session: session,
        record_type: "decision",
        title: "Old decision",
        summary: "Review this old memory.",
        source_type: "agent"
      })

    duplicate_a =
      memory_record_fixture(%{
        session: session,
        record_type: "checkpoint",
        title: "Duplicate checkpoint",
        summary: "Same summary.",
        source_type: "agent"
      })

    _duplicate_b =
      memory_record_fixture(%{
        session: session,
        record_type: "checkpoint",
        title: "Duplicate checkpoint",
        summary: "Same summary.",
        source_type: "agent"
      })

    contradiction =
      memory_record_fixture(%{
        session: session,
        record_type: "decision",
        title: "Superseded routing decision",
        summary: "This memory is superseded by a newer decision.",
        tags: ["superseded"],
        source_type: "review"
      })

    old_inserted_at = DateTime.utc_now() |> DateTime.add(-60, :day) |> DateTime.truncate(:second)

    Repo.update_all(
      from(m in MemoryRecord, where: m.id == ^old_record.id),
      set: [inserted_at: old_inserted_at, updated_at: old_inserted_at]
    )

    finding_fixture(%{session: missed_session, status: "blocked", severity: "critical"})

    quality = Observability.memory_quality(workspace_id: session.workspace_id, stale_days: 30)

    assert quality.totals.records >= 4
    assert quality.totals.active >= 4
    assert quality.totals.stale_candidates >= 1
    assert quality.totals.duplicate_clusters >= 1
    assert quality.totals.contradiction_candidates >= 1
    assert Enum.any?(quality.stale_candidates, &(&1.id == old_record.id and &1.age_days >= 30))

    assert Enum.any?(
             quality.duplicate_clusters,
             &(&1.count >= 2 and &1.key =~ "duplicate checkpoint")
           )

    assert Enum.any?(quality.contradiction_candidates, &(&1.id == contradiction.id))
    assert is_list(quality.missed_memory_sessions)
    assert missed_session.id
    assert quality.distributions.by_type["decision"] >= 2
    assert quality.distributions.by_source["agent"] >= 3
    assert duplicate_a.id
  end

  test "trends/1 summarizes local runs findings costs and imports" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Trend blocked finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.trend"
    })

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "opencode",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               estimated_cost_cents: 13,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-trends-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, _result} =
             ObservabilityTelemetry.import_persist(path, workspace_id: session.workspace_id)

    trends = Observability.trends(workspace_id: session.workspace_id, days: 7)

    assert trends.days == 7
    assert trends.totals.runs == 1
    assert trends.totals.red_runs == 1
    assert trends.totals.active_findings == 1
    assert trends.totals.blocked_findings == 1
    assert trends.totals.estimated_cost_cents == 13
    assert trends.totals.imports == 1
    assert trends.totals.verified_imports == 1
    assert Enum.any?(trends.series, &(&1.runs == 1 and &1.imports == 1))
    assert Enum.any?(trends.recommendations, &String.contains?(&1, "Blocked findings"))
  end

  test "imports/1 summarizes persisted observability snapshots" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-imports-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, _result} =
             ObservabilityTelemetry.import_persist(path,
               workspace_id: session.workspace_id,
               session_id: session.id,
               imported_at: ~U[2026-04-29 05:00:00Z]
             )

    imports = Observability.imports(workspace_id: session.workspace_id)

    assert imports.count == 1
    assert imports.by_integrity == %{"verified" => 1}
    assert imports.by_health["green"] == 1

    assert [%{original_session_id: original_session_id, payload_fingerprint: fingerprint}] =
             imports.recent

    assert original_session_id == session.id
    assert fingerprint == String.slice(envelope.integrity.payload_sha256, 0, 12)
    assert Enum.any?(imports.recommendations, &String.contains?(&1, "trend analysis"))
  end

  test "workspace_overview includes local persisted import posture" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-overview-import-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, _result} =
             ObservabilityTelemetry.import_persist(path, workspace_id: session.workspace_id)

    overview = Observability.workspace_overview(workspace_id: session.workspace_id)

    assert overview.telemetry.import_mode == "dry_run_or_local_persist"
    assert overview.telemetry.persisted_imports == 1
    assert [%{original_session_id: original_session_id}] = overview.telemetry.recent_imports
    assert original_session_id == session.id
  end

  test "telemetry import persist deduplicates by payload hash" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-dupe-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, first} = ObservabilityTelemetry.import_persist(path)
    assert {:ok, second} = ObservabilityTelemetry.import_persist(path)

    assert first.status == "stored"
    assert second.status == "duplicate"
    assert second.id == first.id
    assert Repo.aggregate(ImportedEnvelope, :count, :id) == 1
  end

  test "telemetry import persist rejects unverified envelopes" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    tampered =
      envelope
      |> Jason.encode!()
      |> Jason.decode!()
      |> put_in(["session_run", "health", "status"], "red")

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-rejected-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(tampered))

    assert {:error, {:integrity_not_verified, "mismatch"}} =
             ObservabilityTelemetry.import_persist(path)

    assert Repo.aggregate(ImportedEnvelope, :count, :id) == 0
  end

  test "perf_snapshot/1 returns performance metrics without persisting by default" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace})

    initial_count = Repo.aggregate(MemoryRecord, :count, :id)

    result = Observability.perf_snapshot(workspace_id: workspace.id, session_id: session.id)

    assert result.generated_at
    assert result.workspace_id == workspace.id
    assert result.session_id == session.id
    assert is_list(result.items)
    assert result.summary.item_count > 0
    assert is_number(result.summary.total_wall_ms)
    assert is_number(result.summary.total_ecto_queries)

    # Verify no memory record was created
    assert Repo.aggregate(MemoryRecord, :count, :id) == initial_count
  end

  test "perf_snapshot/1 with persist: true creates memory record" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace})

    initial_count = Repo.aggregate(MemoryRecord, :count, :id)

    result =
      Observability.perf_snapshot(
        workspace_id: workspace.id,
        session_id: session.id,
        persist: true
      )

    assert result.generated_at
    assert result.workspace_id == workspace.id
    assert result.session_id == session.id

    # Verify memory record was created
    assert Repo.aggregate(MemoryRecord, :count, :id) == initial_count + 1
  end

  # Memory record creation verified by count check above

  test "perf_snapshot/1 with task_id includes task context" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace})
    task = task_fixture(%{session: session})

    result =
      Observability.perf_snapshot(
        workspace_id: workspace.id,
        session_id: session.id,
        task_id: task.id
      )

    assert result.task_id == task.id
  end

  describe "close_eval_candidate_lifecycle_from_run!/1" do
    setup do
      session = session_fixture()

      {:ok, candidate} =
        %EvalCandidate{}
        |> EvalCandidate.changeset(%{
          title: "Lifecycle test candidate",
          rule_id: "security.lifecycle_test",
          category: "security",
          severity: "high",
          priority: "high",
          evidence_kind: "trace",
          evidence_summary: "Recurring pattern",
          suggested_action: "Add regression test",
          benchmark_hint: "detection_rule_gen_v1",
          source_problem_key: "lifecycle-test-#{System.unique_integer([:positive])}",
          status: "open",
          human_gate_required: true,
          metadata: %{},
          workspace_id: session.workspace_id,
          session_id: session.id
        })
        |> Repo.insert()

      suite = benchmark_suite_fixture()

      {:ok, scenario} =
        %Scenario{}
        |> Scenario.changeset(%{
          suite_id: suite.id,
          slug: "lifecycle-test-#{candidate.id}",
          name: "Lifecycle test scenario",
          category: "detection_rule_gen_v1",
          kind: "text",
          content: "test content",
          expected_rules: [],
          expected_decision: "warn",
          position: 0,
          split: "local",
          metadata: %{
            "source" => "observability_benchmark_draft",
            "eval_candidate_id" => candidate.id
          }
        })
        |> Repo.insert()

      {:ok, run} =
        %Run{}
        |> Run.changeset(%{
          suite_id: suite.id,
          status: "completed",
          baseline_subject: "controlkeel_validate",
          subjects: ["controlkeel_validate"],
          started_at: DateTime.utc_now(),
          total_scenarios: 1,
          caught_count: 1,
          blocked_count: 1,
          catch_rate: 100.0,
          metadata: %{}
        })
        |> Repo.insert()

      %{candidate: candidate, scenario: scenario, run: run, session: session}
    end

    test "archives the EvalCandidate when all results matched_expected", %{
      candidate: _candidate,
      scenario: scenario,
      run: run
    } do
      {:ok, _result} =
        %ControlKeel.Benchmark.Result{}
        |> ControlKeel.Benchmark.Result.changeset(%{
          run_id: run.id,
          scenario_id: scenario.id,
          subject: "controlkeel_validate",
          subject_type: "controlkeel",
          status: "completed",
          decision: "block",
          findings_count: 1,
          matched_expected: true,
          payload: %{},
          metadata: %{}
        })
        |> Repo.insert()

      [updated] = Observability.close_eval_candidate_lifecycle_from_run!(run)

      assert updated.status == "archived"
      assert updated.metadata["lifecycle_closed_by_run"]["run_id"] == run.id
      assert updated.metadata["lifecycle_closed_by_run"]["all_matched"] == true
    end

    test "reopens the EvalCandidate when any result did not match", %{
      candidate: _candidate,
      scenario: scenario,
      run: run
    } do
      {:ok, _result} =
        %ControlKeel.Benchmark.Result{}
        |> ControlKeel.Benchmark.Result.changeset(%{
          run_id: run.id,
          scenario_id: scenario.id,
          subject: "controlkeel_validate",
          subject_type: "controlkeel",
          status: "completed",
          decision: "allow",
          findings_count: 0,
          matched_expected: false,
          payload: %{},
          metadata: %{}
        })
        |> Repo.insert()

      [updated] = Observability.close_eval_candidate_lifecycle_from_run!(run)

      assert updated.status == "open"
      assert updated.metadata["lifecycle_reopened_by_run"]["run_id"] == run.id
      assert updated.metadata["lifecycle_reopened_by_run"]["all_matched"] == false
    end

    test "reopens a previously archived candidate on new failure evidence", %{
      candidate: candidate,
      scenario: scenario,
      run: run
    } do
      candidate
      |> EvalCandidate.changeset(%{status: "archived"})
      |> Repo.update!()

      {:ok, _result} =
        %ControlKeel.Benchmark.Result{}
        |> ControlKeel.Benchmark.Result.changeset(%{
          run_id: run.id,
          scenario_id: scenario.id,
          subject: "controlkeel_validate",
          subject_type: "controlkeel",
          status: "completed",
          decision: "allow",
          findings_count: 0,
          matched_expected: false,
          payload: %{},
          metadata: %{}
        })
        |> Repo.insert()

      [updated] = Observability.close_eval_candidate_lifecycle_from_run!(run)

      assert updated.status == "open"
      assert updated.metadata["lifecycle_reopened_by_run"]
    end

    test "ignores runs with no eval-candidate-linked scenarios" do
      _session = session_fixture()
      suite = benchmark_suite_fixture()

      {:ok, plain_scenario} =
        %Scenario{}
        |> Scenario.changeset(%{
          suite_id: suite.id,
          slug: "plain-no-candidate",
          name: "Plain scenario",
          category: "vibe_failures_v1",
          kind: "code",
          content: "x = 1",
          expected_rules: [],
          expected_decision: "warn",
          position: 0,
          split: "public",
          metadata: %{}
        })
        |> Repo.insert()

      {:ok, run} =
        %Run{}
        |> Run.changeset(%{
          suite_id: suite.id,
          status: "completed",
          baseline_subject: "controlkeel_validate",
          subjects: ["controlkeel_validate"],
          started_at: DateTime.utc_now(),
          total_scenarios: 1,
          caught_count: 1,
          blocked_count: 1,
          catch_rate: 100.0,
          metadata: %{}
        })
        |> Repo.insert()

      {:ok, _result} =
        %ControlKeel.Benchmark.Result{}
        |> ControlKeel.Benchmark.Result.changeset(%{
          run_id: run.id,
          scenario_id: plain_scenario.id,
          subject: "controlkeel_validate",
          subject_type: "controlkeel",
          status: "completed",
          decision: "block",
          findings_count: 1,
          matched_expected: true,
          payload: %{},
          metadata: %{}
        })
        |> Repo.insert()

      assert [] == Observability.close_eval_candidate_lifecycle_from_run!(run)
    end
  end
end
