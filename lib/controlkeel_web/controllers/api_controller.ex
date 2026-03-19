defmodule ControlKeelWeb.ApiController do
  use ControlKeelWeb, :controller

  alias ControlKeel.AgentRouter
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.PolicyTraining
  alias ControlKeel.Repo
  alias ControlKeel.Scanner.FastPath
  alias ControlKeel.Skills
  alias ControlKeel.Skills.Registry

  # ─── Sessions ────────────────────────────────────────────────────────────────

  def list_sessions(conn, _params) do
    sessions = Mission.list_recent_sessions(50)
    json(conn, %{sessions: Enum.map(sessions, &session_summary/1)})
  end

  def get_session(conn, %{"id" => id}) do
    case Mission.get_session_context(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      session ->
        json(conn, %{session: session_detail(session)})
    end
  end

  def create_session(conn, params) do
    attrs =
      Map.take(
        params,
        ~w(title objective occupation domain_pack budget_cents daily_budget_cents risk_tier status spent_cents execution_brief workspace_id)
      )

    case Mission.create_session(attrs) do
      {:ok, session} ->
        conn |> put_status(:created) |> json(%{session: session_summary(session)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid session", details: changeset_errors(changeset)})
    end
  end

  # ─── Tasks ───────────────────────────────────────────────────────────────────

  def create_task(conn, %{"session_id" => session_id} = params) do
    case Mission.get_session(session_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      _session ->
        attrs =
          params
          |> Map.take(~w(title validation_gate estimated_cost_cents position))
          |> Map.put("session_id", session_id)

        case Mission.create_task(attrs) do
          {:ok, task} ->
            conn |> put_status(:created) |> json(%{task: task_summary(task)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid task", details: changeset_errors(changeset)})
        end
    end
  end

  # ─── Validate ────────────────────────────────────────────────────────────────

  def validate(conn, params) do
    input = Map.take(params, ~w(content path kind session_id domain_pack))

    result = FastPath.scan(input)

    json(conn, %{
      allowed: result.allowed,
      decision: result.decision,
      summary: result.summary,
      findings: Enum.map(result.findings, &finding_summary/1)
    })
  end

  # ─── Findings ────────────────────────────────────────────────────────────────

  def list_findings(conn, params) do
    opts =
      params
      |> Map.take(~w(session_id severity status category))
      |> Enum.into(%{})

    page = Mission.browse_findings(opts)

    json(conn, %{
      findings: Enum.map(page.entries, &finding_summary/1),
      total: page.total_count,
      page: page.page,
      total_pages: page.total_pages
    })
  end

  def finding_action(conn, %{"id" => id, "action" => action} = params) do
    case Mission.get_finding(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "finding not found"})

      finding ->
        case action do
          "approve" ->
            {:ok, updated} = Mission.approve_finding(finding)
            json(conn, %{finding: finding_summary(updated)})

          "reject" ->
            reason = Map.get(params, "reason")
            {:ok, updated} = Mission.reject_finding(finding, reason)
            json(conn, %{finding: finding_summary(updated)})

          "escalate" ->
            {:ok, updated} = Mission.escalate_finding(finding)
            json(conn, %{finding: finding_summary(updated)})

          _ ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "unknown action", valid_actions: ~w(approve reject escalate)})
        end
    end
  end

  # ─── Budget ──────────────────────────────────────────────────────────────────

  def get_budget(conn, params) do
    session_id = Map.get(params, "session_id")

    if session_id do
      case Mission.get_session(session_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "session not found"})

        session ->
          rolling_24h = Budget.rolling_24h_spend_cents(session.id)

          json(conn, %{
            session_id: session.id,
            budget_cents: session.budget_cents,
            daily_budget_cents: session.daily_budget_cents,
            spent_cents: session.spent_cents,
            rolling_24h_spend_cents: rolling_24h,
            remaining_cents: max((session.budget_cents || 0) - (session.spent_cents || 0), 0)
          })
      end
    else
      sessions = Mission.list_recent_sessions(100)
      total_spent = Enum.reduce(sessions, 0, fn s, acc -> acc + (s.spent_cents || 0) end)
      total_budget = Enum.reduce(sessions, 0, fn s, acc -> acc + (s.budget_cents || 0) end)

      json(conn, %{
        total_sessions: length(sessions),
        total_spent_cents: total_spent,
        total_budget_cents: total_budget,
        remaining_cents: max(total_budget - total_spent, 0)
      })
    end
  end

  # ─── Task Update ─────────────────────────────────────────────────────────────

  def update_task(conn, %{"id" => id} = params) do
    case Mission.get_task!(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      task ->
        attrs = Map.take(params, ~w(status title validation_gate metadata))

        case Mission.update_task(task, attrs) do
          {:ok, updated} ->
            json(conn, %{task: task_summary(updated)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid attrs", details: changeset_errors(changeset)})
        end
    end
  rescue
    Ecto.NoResultsError ->
      conn |> put_status(:not_found) |> json(%{error: "task not found"})
  end

  # ─── Proof Bundle ─────────────────────────────────────────────────────────────

  def proof_bundle(conn, %{"task_id" => task_id}) do
    case Mission.proof_bundle(task_id) do
      {:ok, bundle} ->
        json(conn, %{proof: bundle})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})
    end
  end

  def list_proofs(conn, params) do
    browser = Mission.browse_proof_bundles(params)

    json(conn, %{
      proofs: Enum.map(browser.entries, &proof_summary/1),
      total: browser.total_count,
      page: browser.page,
      total_pages: browser.total_pages
    })
  end

  def get_proof(conn, %{"id" => id}) do
    case Mission.get_proof_bundle_with_context(String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "proof not found"})

      proof ->
        json(conn, %{proof: proof_detail(proof)})
    end
  end

  # ─── Benchmarks ───────────────────────────────────────────────────────────────

  def list_benchmarks(conn, params) do
    domain_pack = Map.get(params, "domain_pack")
    opts = benchmark_filter_opts(domain_pack)
    suites = Benchmark.list_suites(opts)
    runs = Benchmark.list_recent_runs(opts)
    summary = Benchmark.benchmark_summary(opts)

    summary =
      Map.update(summary, :latest_run, nil, fn
        nil -> nil
        run -> benchmark_run_summary(run)
      end)

    json(conn, %{
      selected_domain_pack: domain_pack,
      summary: summary,
      suites: Enum.map(suites, &benchmark_suite_summary/1),
      runs: Enum.map(runs, &benchmark_run_summary/1)
    })
  end

  def create_benchmark_run(conn, params) do
    attrs =
      Map.take(params, ~w(suite subjects baseline_subject scenario_slugs domain_pack))

    case Benchmark.run_suite(attrs) do
      {:ok, run} ->
        conn
        |> put_status(:created)
        |> json(%{run: benchmark_run_detail(run)})

      {:error, :suite_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "benchmark suite not found"})

      {:error, :no_scenarios} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no benchmark scenarios matched the current filters"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def get_benchmark_run(conn, %{"id" => id}) do
    case Benchmark.get_run(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "benchmark run not found"})

      run ->
        json(conn, %{run: benchmark_run_detail(run)})
    end
  end

  def import_benchmark_result(conn, %{"id" => id, "subject" => subject} = params) do
    attrs = Map.take(params, ~w(scenario_slug content path kind duration_ms metadata))

    with {:ok, run_id} <- parse_integer_param(id),
         {:ok, run} <- Benchmark.import_result(run_id, subject, attrs) do
      json(conn, %{run: benchmark_run_detail(run)})
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid benchmark run id"})

      {:error, :scenario_slug_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "scenario_slug is required"})

      {:error, :result_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "benchmark result slot not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "benchmark run not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def export_benchmark_run(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "json")

    with {:ok, run_id} <- parse_integer_param(id),
         {:ok, output} <- Benchmark.export_run(run_id, format) do
      case format do
        "csv" ->
          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"benchmark-run-#{run_id}.csv\""
          )
          |> send_resp(200, output)

        _other ->
          json(conn, Jason.decode!(output))
      end
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid benchmark run id"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "benchmark run not found"})
    end
  end

  def list_policies(conn, params) do
    artifacts =
      PolicyTraining.list_artifacts(%{
        "artifact_type" => params["type"] || params["artifact_type"],
        "status" => params["status"],
        "limit" => params["limit"]
      })

    json(conn, %{
      policies: Enum.map(artifacts, &policy_artifact_summary/1),
      active: %{
        router: maybe_policy_artifact_summary(PolicyTraining.active_artifact("router")),
        budget_hint: maybe_policy_artifact_summary(PolicyTraining.active_artifact("budget_hint"))
      },
      training_runs: Enum.map(PolicyTraining.list_training_runs(), &policy_training_run_summary/1)
    })
  end

  def train_policy(conn, params) do
    case PolicyTraining.start_training(%{"type" => params["type"]}) do
      {:ok, artifact} ->
        conn
        |> put_status(:created)
        |> json(%{policy: policy_artifact_detail(artifact)})

      {:error, :unknown_artifact_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "artifact type must be `router` or `budget_hint`"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def get_policy(conn, %{"id" => id}) do
    case PolicyTraining.get_artifact(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "policy artifact not found"})

      artifact ->
        json(conn, %{policy: policy_artifact_detail(artifact)})
    end
  end

  def promote_policy(conn, %{"id" => id}) do
    case PolicyTraining.promote_artifact(id) do
      {:ok, artifact} ->
        json(conn, %{policy: policy_artifact_detail(artifact)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "policy artifact not found"})

      {:error, {:promotion_failed, reasons}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "promotion gate failed", reasons: List.wrap(reasons)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def archive_policy(conn, %{"id" => id}) do
    case PolicyTraining.archive_artifact(id) do
      {:ok, artifact} ->
        json(conn, %{policy: policy_artifact_detail(Repo.preload(artifact, :training_run))})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "policy artifact not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # ─── Memory ──────────────────────────────────────────────────────────────────

  def search_memory(conn, params) do
    query = Map.get(params, "q", "")

    result =
      Memory.search(query, %{
        workspace_id: nil,
        session_id: normalize_integer_param(params["session_id"]),
        task_id: normalize_integer_param(params["task_id"]),
        record_type: params["type"]
      })

    json(conn, %{
      query: result.query,
      semantic_available: result.semantic_available,
      records: Enum.map(result.entries, &memory_hit_summary/1),
      total: result.total_count
    })
  end

  def archive_memory(conn, %{"id" => id}) do
    case Memory.archive_record(String.to_integer(id)) do
      {:ok, record} ->
        json(conn, %{memory: %{id: record.id, archived_at: record.archived_at}})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "memory record not found"})
    end
  end

  # ─── Audit Log ────────────────────────────────────────────────────────────────

  def audit_log(conn, %{"id" => session_id} = params) do
    case Mission.audit_log(session_id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:ok, log} ->
        format = Map.get(params, "format", "json")

        if format == "csv" do
          csv = audit_log_to_csv(log)

          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"audit-log-#{session_id}.csv\""
          )
          |> send_resp(200, csv)
        else
          json(conn, %{audit_log: log})
        end
    end
  end

  # ─── Complete Task ─────────────────────────────────────────────────────────────

  def complete_task(conn, %{"id" => task_id}) do
    case Mission.complete_task(String.to_integer(task_id)) do
      {:ok, task} ->
        json(conn, %{task: task_summary(task)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, :unresolved_findings, findings} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "task has unresolved findings",
          message:
            "#{length(findings)} finding(s) must be approved or resolved before marking this task done.",
          findings: Enum.map(findings, &finding_summary/1)
        })
    end
  end

  def pause_task(conn, %{"id" => task_id}) do
    case Mission.pause_task(String.to_integer(task_id), "api") do
      {:ok, %{task: task, resume_packet: packet}} ->
        json(conn, %{task: task_summary(task), resume_packet: packet})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def resume_task(conn, %{"id" => task_id}) do
    case Mission.resume_task(String.to_integer(task_id), "api") do
      {:ok, %{task: task, resume_packet: packet}} ->
        json(conn, %{task: task_summary(task), resume_packet: packet})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # ─── Skills ───────────────────────────────────────────────────────────────────

  def list_skills(conn, params) do
    project_root = Map.get(params, "project_root")
    format = Map.get(params, "format", "json")
    target = Map.get(params, "target")
    analysis = Registry.analyze(project_root)

    skills =
      if is_binary(target) and target != "" do
        Enum.filter(analysis.skills, &(target in (&1.compatibility_targets || [])))
      else
        analysis.skills
      end

    entries =
      Enum.map(skills, fn s ->
        %{
          name: s.name,
          description: s.description,
          scope: s.scope,
          allowed_tools: s.allowed_tools,
          required_mcp_tools: s.required_mcp_tools,
          license: s.license,
          compatibility: s.compatibility,
          compatibility_targets: s.compatibility_targets,
          source: s.source,
          install_state: s.install_state,
          diagnostics: Enum.map(s.diagnostics, &diagnostic_summary/1)
        }
      end)

    result = %{
      skills: entries,
      total: length(entries),
      trusted_project_skills: analysis.trusted_project?,
      diagnostics: Enum.map(analysis.diagnostics, &diagnostic_summary/1)
    }

    result =
      if format == "xml" do
        Map.put(result, :prompt_block, Registry.prompt_block(project_root))
      else
        result
      end

    json(conn, result)
  end

  def get_skill(conn, %{"name" => name} = params) do
    project_root = Map.get(params, "project_root")

    case Registry.get(name, project_root) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "skill not found"})

      skill ->
        json(conn, %{
          skill: %{
            name: skill.name,
            description: skill.description,
            scope: skill.scope,
            allowed_tools: skill.allowed_tools,
            required_mcp_tools: skill.required_mcp_tools,
            license: skill.license,
            compatibility: skill.compatibility,
            compatibility_targets: skill.compatibility_targets,
            source: skill.source,
            resources: skill.resources,
            diagnostics: Enum.map(skill.diagnostics, &diagnostic_summary/1),
            install_state: skill.install_state,
            body: skill.body
          }
        })
    end
  end

  def list_skill_targets(conn, _params) do
    json(conn, %{targets: Enum.map(Skills.targets(), &skill_target_summary/1)})
  end

  def export_skills(conn, params) do
    target = Map.get(params, "target", "open-standard")
    project_root = Map.get(params, "project_root", File.cwd!())
    scope = Map.get(params, "scope")

    case Skills.export(target, project_root, scope: scope) do
      {:ok, plan} ->
        json(conn, %{plan: skill_export_plan_summary(plan)})

      {:error, :unknown_target} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unknown skill target"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def install_skills(conn, params) do
    target = Map.get(params, "target", "open-standard")
    project_root = Map.get(params, "project_root", File.cwd!())
    scope = Map.get(params, "scope")

    case Skills.install(target, project_root, scope: scope) do
      {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
        json(conn, %{plan: skill_export_plan_summary(plan)})

      {:ok, result} ->
        json(conn, %{install: result})

      {:error, :unknown_target} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unknown skill target"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # ─── Agent Router ─────────────────────────────────────────────────────────────

  def route_agent(conn, params) do
    task_title = Map.get(params, "task", "")
    opts = build_router_opts(params)

    case AgentRouter.route(task_title, opts) do
      {:ok, recommendation} ->
        json(conn, %{recommendation: recommendation})

      {:error, :no_suitable_agent, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no_suitable_agent", message: message})
    end
  end

  defp build_router_opts(params) do
    []
    |> maybe_put_opt(:risk_tier, Map.get(params, "risk_tier"))
    |> maybe_put_opt(:budget_remaining_cents, Map.get(params, "budget_remaining_cents"))
    |> maybe_put_opt(:allowed_agents, Map.get(params, "allowed_agents"))
    |> maybe_put_opt(:domain_pack, Map.get(params, "domain_pack"))
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp diagnostic_summary(diagnostic) do
    %{
      level: diagnostic.level,
      code: diagnostic.code,
      message: diagnostic.message,
      path: diagnostic.path,
      skill_name: diagnostic.skill_name
    }
  end

  defp skill_target_summary(target) do
    %{
      id: target.id,
      label: target.label,
      description: target.description,
      native: target.native,
      default_scope: target.default_scope,
      supported_scopes: target.supported_scopes
    }
  end

  defp skill_export_plan_summary(plan) do
    %{
      target: plan.target,
      output_dir: plan.output_dir,
      scope: plan.scope,
      writes: plan.writes,
      instructions: plan.instructions,
      native_available: plan.native_available
    }
  end

  # ─── Serializers ─────────────────────────────────────────────────────────────

  defp session_summary(session) do
    %{
      id: session.id,
      title: session.title,
      objective: session.objective,
      status: session.status,
      risk_tier: session.risk_tier,
      spent_cents: session.spent_cents,
      budget_cents: session.budget_cents,
      inserted_at: session.inserted_at
    }
  end

  defp session_detail(session) do
    base = session_summary(session)

    Map.merge(base, %{
      execution_brief: session.execution_brief,
      tasks: Enum.map(Map.get(session, :tasks, []), &task_summary/1),
      findings: Enum.map(Map.get(session, :findings, []), &finding_summary/1)
    })
  end

  defp task_summary(task) do
    %{
      id: task.id,
      title: task.title,
      status: task.status,
      position: task.position,
      estimated_cost_cents: task.estimated_cost_cents,
      validation_gate: task.validation_gate,
      latest_proof: Mission.proof_summary_for_task(task)
    }
  end

  defp finding_summary(finding) do
    %{
      id: Map.get(finding, :id),
      rule_id: finding.rule_id,
      category: finding.category,
      severity: finding.severity,
      status: Map.get(finding, :status, "open"),
      plain_message: finding.plain_message,
      auto_fix_available: Map.get(finding, :auto_fix_available, false)
    }
  end

  defp proof_summary(proof) do
    %{
      id: proof.id,
      task_id: proof.task_id,
      task_title: proof.task && proof.task.title,
      session_id: proof.session_id,
      session_title: proof.session && proof.session.title,
      risk_tier: proof.session && proof.session.risk_tier,
      version: proof.version,
      status: proof.status,
      risk_score: proof.risk_score,
      deploy_ready: proof.deploy_ready,
      generated_at: proof.generated_at
    }
  end

  defp proof_detail(proof) do
    Map.merge(proof_summary(proof), %{
      open_findings_count: proof.open_findings_count,
      blocked_findings_count: proof.blocked_findings_count,
      approved_findings_count: proof.approved_findings_count,
      bundle: proof.bundle
    })
  end

  defp benchmark_suite_summary(suite) do
    %{
      id: suite.id,
      slug: suite.slug,
      name: suite.name,
      description: suite.description,
      version: suite.version,
      status: suite.status,
      scenario_count: length(suite.scenarios),
      domain_packs: Benchmark.domain_packs_for_suite(suite),
      metadata: suite.metadata
    }
  end

  defp benchmark_run_summary(run) do
    detail_metrics = Benchmark.run_detail_metrics(run)

    %{
      id: run.id,
      suite_slug: run.suite.slug,
      suite_name: run.suite.name,
      status: run.status,
      baseline_subject: run.baseline_subject,
      subjects: run.subjects,
      total_scenarios: run.total_scenarios,
      caught_count: run.caught_count,
      blocked_count: run.blocked_count,
      catch_rate: run.catch_rate,
      block_rate: detail_metrics.block_rate,
      expected_rule_hit_rate: detail_metrics.expected_rule_hit_rate,
      domain_packs: Benchmark.domain_packs_for_run(run),
      median_latency_ms: run.median_latency_ms,
      average_overhead_percent: run.average_overhead_percent,
      started_at: run.started_at,
      finished_at: run.finished_at
    }
  end

  defp benchmark_run_detail(run) do
    matrix = Benchmark.run_matrix(run)

    Map.merge(benchmark_run_summary(run), %{
      metadata: run.metadata,
      scenarios:
        Enum.map(matrix.scenarios, fn row ->
          %{
            scenario: %{
              slug: row.scenario.slug,
              name: row.scenario.name,
              category: row.scenario.category,
              incident_label: row.scenario.incident_label,
              expected_rules: row.scenario.expected_rules,
              expected_decision: row.scenario.expected_decision,
              split: row.scenario.split,
              metadata: row.scenario.metadata
            },
            results:
              Enum.map(row.results, fn result ->
                %{
                  id: result && result.id,
                  subject: result && result.subject,
                  subject_type: result && result.subject_type,
                  status: result && result.status,
                  decision: result && result.decision,
                  findings_count: result && result.findings_count,
                  matched_expected: result && result.matched_expected,
                  latency_ms: result && result.latency_ms,
                  overhead_percent: result && result.overhead_percent,
                  payload: result && result.payload,
                  metadata: result && result.metadata
                }
              end)
          }
        end)
    })
  end

  defp maybe_policy_artifact_summary(nil), do: nil
  defp maybe_policy_artifact_summary(artifact), do: policy_artifact_summary(artifact)

  defp policy_training_run_summary(run) do
    artifacts =
      if Ecto.assoc_loaded?(run.artifacts) do
        run.artifacts
      else
        []
      end

    %{
      id: run.id,
      artifact_type: run.artifact_type,
      status: run.status,
      training_scope: run.training_scope,
      dataset_summary: run.dataset_summary,
      training_metrics: run.training_metrics,
      validation_metrics: run.validation_metrics,
      held_out_metrics: run.held_out_metrics,
      failure_reason: run.failure_reason,
      inserted_at: run.inserted_at,
      finished_at: run.finished_at,
      artifact_ids: Enum.map(artifacts, & &1.id)
    }
  end

  defp policy_artifact_summary(artifact) do
    %{
      id: artifact.id,
      artifact_type: artifact.artifact_type,
      version: artifact.version,
      status: artifact.status,
      model_family: artifact.model_family,
      metrics: artifact.metrics,
      activated_at: artifact.activated_at,
      archived_at: artifact.archived_at,
      training_run_id: artifact.training_run_id
    }
  end

  defp policy_artifact_detail(artifact) do
    Map.merge(policy_artifact_summary(artifact), %{
      feature_spec: artifact.feature_spec,
      artifact: artifact.artifact,
      metadata: artifact.metadata,
      training_run:
        if(Ecto.assoc_loaded?(artifact.training_run),
          do: policy_training_run_summary(artifact.training_run),
          else: nil
        )
    })
  end

  defp memory_hit_summary(hit) do
    %{
      id: hit.id,
      record_type: hit.record_type,
      title: hit.title,
      summary: hit.summary,
      session_id: hit.session_id,
      task_id: hit.task_id,
      source_type: hit.source_type,
      source_id: hit.source_id,
      tags: hit.tags,
      inserted_at: hit.inserted_at,
      lexical_score: hit.lexical_score,
      semantic_score: hit.semantic_score,
      score: hit.score
    }
  end

  defp audit_log_to_csv(%{events: events, session_id: sid, session_title: title}) do
    header =
      "session_id,session_title,timestamp,type,rule_id,severity,category,status,plain_message,source,tool,provider,model,decision,cost_cents,tokens\r\n"

    rows =
      Enum.map(events, fn e ->
        [
          sid,
          title,
          e.timestamp,
          e.type,
          Map.get(e, :rule_id, ""),
          Map.get(e, :severity, ""),
          Map.get(e, :category, ""),
          Map.get(e, :status, ""),
          csv_escape(Map.get(e, :plain_message, "")),
          Map.get(e, :source, ""),
          Map.get(e, :tool, ""),
          Map.get(e, :provider, ""),
          Map.get(e, :model, ""),
          Map.get(e, :decision, ""),
          Map.get(e, :cost_cents, ""),
          Map.get(e, :tokens, "")
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\r\n")
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(str) when is_binary(str) do
    if String.contains?(str, [",", "\"", "\n"]) do
      "\"" <> String.replace(str, "\"", "\"\"") <> "\""
    else
      str
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp normalize_integer_param(nil), do: nil
  defp normalize_integer_param(value) when is_integer(value), do: value

  defp normalize_integer_param(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer_param(value) when is_integer(value), do: {:ok, value}

  defp parse_integer_param(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]
end
