defmodule ControlKeelWeb.ApiController do
  use ControlKeelWeb, :controller

  import ControlKeelWeb.APIHelpers

  alias ControlKeel.Agent.ACPRegistry
  alias ControlKeel.Agent.Execution
  alias ControlKeel.Agent.Router
  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.Ops.Distribution
  alias ControlKeel.Governance
  alias ControlKeel.Intent
  alias ControlKeel.Project.Local
  alias ControlKeel.Memory
  alias ControlKeel.Mission.Decomposition
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Mcp.ProtocolAccess
  alias ControlKeel.Repo
  alias ControlKeel.Scanner.FastPath
  alias ControlKeel.Skills
  alias ControlKeel.Skills.Registry

  def action(conn, _opts) do
    agent_json? = agent_json_requested?(conn)

    conn =
      if agent_json? do
        Plug.Conn.register_before_send(conn, &wrap_agent_json_response/1)
      else
        conn
      end

    apply(__MODULE__, action_name(conn), [conn, conn.params])
  end

  # ─── Sessions ────────────────────────────────────────────────────────────────

  def list_sessions(conn, _params) do
    sessions = Mission.list_recent_sessions(50, current_workspace_id(conn))
    json(conn, %{sessions: Enum.map(sessions, &session_summary/1)})
  end

  def get_session(conn, %{"id" => id}) do
    with {:ok, session_id} <- parse_integer_param(id),
         %{} = session <- Mission.get_session(session_id),
         :ok <- authorize_workspace_for_conn(conn, session.workspace_id, "sessions:read"),
         %{} = context <- Mission.get_session_context(session_id) do
      json(conn, %{session: session_detail(context)})
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create_review(conn, params) do
    attrs =
      Map.take(
        params,
        ~w(session_id task_id title review_type submission_body annotations feedback_notes submitted_by metadata previous_review_id)
      )

    with :ok <- authorize_review_target(conn, attrs),
         {:ok, review} <- Mission.submit_review(attrs) do
      conn |> put_status(:created) |> json(%{review: review_summary(review)})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "review target not found"})

      {:error, {:invalid_arguments, message}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid review", details: changeset_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def get_review(conn, %{"id" => id}) do
    case parse_integer_param(id) do
      {:ok, review_id} ->
        case Mission.get_review_with_context(review_id) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "review not found"})

          review ->
            case authorize_workspace_for_conn(conn, review.session.workspace_id, "reviews:read") do
              :ok ->
                json(conn, %{review: review_summary(review)})

              {:error, :forbidden} ->
                conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
            end
        end

      {:error, :invalid_integer} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "review id must be an integer"})
    end
  end

  def respond_review(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ~w(decision status feedback_notes annotations reviewed_by metadata))

    with {:ok, review_id} <- parse_integer_param(id),
         {:ok, review} <- fetch_review(review_id),
         :ok <- authorize_session_access(conn, review.session_id, "reviews:write"),
         {:ok, updated} <- Mission.respond_review(review, attrs) do
      json(conn, %{review: review_summary(updated)})
    else
      {:error, :invalid_integer} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "review id must be an integer"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "review not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, {:invalid_arguments, message}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid review", details: changeset_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def create_session(conn, params) do
    attrs = session_create_attrs(params)

    with :ok <-
           maybe_authorize_workspace_id(
             conn,
             attrs["workspace_id"] || attrs[:workspace_id],
             "sessions:write"
           ),
         {:ok, session} <- Mission.create_session(attrs) do
      conn |> put_status(:created) |> json(%{session: session_summary(session)})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid session", details: changeset_errors(changeset)})
    end
  end

  def list_domains(conn, _params) do
    occupation_profiles = Intent.occupation_profiles()

    domains =
      Intent.supported_packs()
      |> Enum.map(fn domain_pack ->
        occupations =
          Enum.filter(occupation_profiles, &(&1.domain_pack == domain_pack))

        preflight =
          Intent.preflight_context(%{
            "occupation" => occupations |> List.first() |> Map.fetch!(:id),
            "idea" => ""
          })

        %{
          id: domain_pack,
          label: Intent.pack_label(domain_pack),
          industry: preflight.industry,
          compliance: preflight.compliance,
          stack_guidance: preflight.stack_guidance,
          validation_language: preflight.validation_language,
          occupations:
            Enum.map(occupations, fn profile ->
              %{
                id: profile.id,
                label: profile.label,
                description: profile.description
              }
            end)
        }
      end)

    occupations =
      Enum.map(occupation_profiles, fn profile ->
        %{
          id: profile.id,
          label: profile.label,
          domain_pack: profile.domain_pack,
          domain_pack_label: Intent.pack_label(profile.domain_pack),
          industry: profile.industry,
          description: profile.description
        }
      end)

    json(conn, %{domains: domains, occupations: occupations})
  end

  def context(conn, params) do
    context_params = Map.take(params, ~w(session_id task_id))

    case CkContext.call(context_params) do
      {:ok, payload} ->
        json(conn, %{context: payload})

      {:error, {:invalid_arguments, message}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})
    end
  end

  def improvement_summary(conn, params) do
    limit =
      case parse_integer_param(Map.get(params, "limit", "10")) do
        {:ok, parsed} -> parsed
        {:error, :invalid_integer} -> 10
      end

    sessions = Mission.list_recent_sessions(limit, current_workspace_id(conn))
    benchmark_summary = Benchmark.benchmark_summary()

    json(conn, %{
      summary: AutonomyLoop.workspace_improvement_summary(sessions),
      benchmark_summary: benchmark_summary_payload(benchmark_summary),
      sessions:
        Enum.map(sessions, fn session ->
          Map.merge(session_summary(session), %{
            improvement_loop: AutonomyLoop.session_improvement_loop(session)
          })
        end)
    })
  end

  # ─── Tasks ───────────────────────────────────────────────────────────────────

  def create_task(conn, %{"session_id" => session_id} = params) do
    case Mission.get_session(session_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      _session ->
        with :ok <- authorize_session_access(conn, session_id, "tasks:execute") do
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
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  def run_task(conn, %{"id" => id} = params) do
    project_root = Map.get(params, "project_root", File.cwd!())

    with {:ok, task_id} <- parse_integer_param(id),
         :ok <- authorize_task_access(conn, task_id, "tasks:execute"),
         {:ok, result} <-
           Execution.run_task(task_id,
             project_root: project_root,
             agent: Map.get(params, "agent"),
             mode: Map.get(params, "mode")
           ) do
      json(conn, %{run: result})
    else
      {:error, {:policy_blocked, reason}} ->
        conn |> put_status(:forbidden) |> json(%{error: "policy_blocked", message: reason})

      {:error, :invalid_id} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "task id must be an integer"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def run_session(conn, %{"id" => id} = params) do
    project_root = Map.get(params, "project_root", File.cwd!())

    with {:ok, session_id} <- parse_integer_param(id),
         :ok <- authorize_session_access(conn, session_id, "tasks:execute"),
         {:ok, result} <-
           Execution.run_session(session_id,
             project_root: project_root,
             agent: Map.get(params, "agent"),
             mode: Map.get(params, "mode")
           ) do
      json(conn, %{run: result})
    else
      {:error, :invalid_id} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "session id must be an integer"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
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
      findings: Enum.map(result.findings, &finding_summary/1),
      advisory: result.advisory
    })
  end

  # ─── Findings ────────────────────────────────────────────────────────────────

  # ─── Budget ──────────────────────────────────────────────────────────────────

  def get_budget(conn, params) do
    session_id = Map.get(params, "session_id")

    if session_id do
      case Mission.get_session(session_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "session not found"})

        session ->
          with :ok <- authorize_workspace_for_conn(conn, session.workspace_id, "budget:read") do
            rolling_24h = Budget.rolling_24h_spend_cents(session.id)

            json(conn, %{
              session_id: session.id,
              budget_cents: session.budget_cents,
              daily_budget_cents: session.daily_budget_cents,
              spent_cents: session.spent_cents,
              rolling_24h_spend_cents: rolling_24h,
              remaining_cents: max((session.budget_cents || 0) - (session.spent_cents || 0), 0)
            })
          else
            {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
          end
      end
    else
      sessions = Mission.list_recent_sessions(100, current_workspace_id(conn))
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
        with :ok <- authorize_task_access(conn, task.id, "tasks:execute") do
          attrs = Map.take(params, ~w(status title validation_gate metadata))

          case Mission.update_task(task, attrs) do
            {:ok, updated} ->
              json(conn, %{task: task_summary(updated)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "invalid attrs", details: changeset_errors(changeset)})
          end
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  rescue
    Ecto.NoResultsError ->
      conn |> put_status(:not_found) |> json(%{error: "task not found"})
  end

  # ─── Proof Bundle ─────────────────────────────────────────────────────────────

  def proof_bundle(conn, %{"task_id" => task_id}) do
    with {:ok, parsed_task_id} <- parse_integer_param(task_id),
         :ok <- authorize_task_access(conn, parsed_task_id, "proofs:read"),
         {:ok, bundle} <- Mission.proof_bundle(parsed_task_id) do
      json(conn, %{proof: bundle})
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "task not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def list_proofs(conn, params) do
    browser =
      Mission.browse_proof_bundles(Map.put(params, "workspace_id", current_workspace_id(conn)))

    json(conn, %{
      proofs: Enum.map(browser.entries, &proof_summary/1),
      total: browser.total_count,
      page: browser.page,
      total_pages: browser.total_pages
    })
  end

  def get_proof(conn, %{"id" => id}) do
    with {:ok, proof_id} <- parse_integer_param(id),
         %{} = proof <- Mission.get_proof_bundle_with_context(proof_id),
         :ok <- authorize_workspace_for_conn(conn, proof.session.workspace_id, "proofs:read") do
      json(conn, %{proof: proof_detail(proof)})
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:not_found) |> json(%{error: "proof not found"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "proof not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
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

  def compare_benchmark_run(conn, %{"id" => id}) do
    case Benchmark.compare_run(id) do
      {:ok, comparison} ->
        json(conn, %{comparison: comparison})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "benchmark run not found"})
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

      # This clause is intentionally kept even though the type checker flags it as
      # "redundant": Benchmark.import_result can return {:error, %Ecto.Changeset{}}
      # (and other non-atom reasons) because Repo.update failures from its internal
      # update/recalculate steps pass through its with/else unhandled. The checker
      # does not model Ecto changeset error returns, so it wrongly assumes only the
      # atom errors above are possible. Without this clause a validation failure on
      # the public import endpoint would surface as a 500 CaseClauseError instead of
      # this 422. Do not remove it.
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def export_benchmark_run(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "json")

    # `--format openeval` (aryaminus/controlkeel#121) is CLI-only for now:
    # this endpoint group has no workspace scoping yet (#142), and wiring the
    # flag here is deliberately deferred until that lands rather than
    # shipping tests now that would need redoing once it's scoped. Reject
    # explicitly instead of silently emitting the bundle over an unscoped
    # HTTP endpoint.
    if format in ["openeval", :openeval] do
      conn
      |> put_status(:not_implemented)
      |> json(%{
        error:
          "format=openeval is not available on this endpoint yet (tracked in #142); " <>
            "use `controlkeel benchmark export <run-id> --format openeval` instead"
      })
    else
      do_export_benchmark_run(conn, id, format)
    end
  end

  defp do_export_benchmark_run(conn, id, format) do
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

      {:error, :unknown_format} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unknown export format: #{inspect(format)}"})
    end
  end

  # ─── Memory ──────────────────────────────────────────────────────────────────

  def search_memory(conn, params) do
    query = Map.get(params, "q", "")

    with {:ok, opts} <- memory_search_opts(conn, params) do
      result =
        Memory.search(query, %{
          workspace_id: opts.workspace_id,
          org_id: opts.org_id,
          visibility: opts.visibility,
          session_id: opts.session_id,
          task_id: Arguments.parse_integer(params["task_id"]),
          record_type: params["type"]
        })

      json(conn, %{
        query: result.query,
        semantic_available: result.semantic_available,
        records: Enum.map(result.entries, &memory_hit_summary/1),
        total: result.total_count
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def archive_memory(conn, %{"id" => id}) do
    with {:ok, parsed_id} <- parse_integer_param(id),
         %{} = record <- Memory.get_record(parsed_id),
         :ok <- authorize_workspace_for_conn(conn, record.workspace_id, "memory:write"),
         {:ok, archived} <- Memory.archive_record(record) do
      json(conn, %{memory: %{id: archived.id, archived_at: archived.archived_at}})
    else
      {:error, :invalid_integer} ->
        conn |> put_status(:not_found) |> json(%{error: "memory record not found"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "memory record not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "memory record not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create_memory(conn, params) do
    session_id = Arguments.parse_integer(params["session_id"])
    body = Map.get(params, "memory", Map.get(params, "body", ""))

    case session_id && Mission.get_session(session_id) do
      %{} = session ->
        with :ok <- authorize_session_access(conn, session_id, "memory:write") do
          attrs = %{
            "workspace_id" => session.workspace_id,
            "session_id" => session_id,
            "task_id" => Arguments.parse_integer(params["task_id"]),
            "record_type" => Map.get(params, "record_type", "decision"),
            "title" => Map.get(params, "title", String.slice(body, 0, 80)),
            "summary" => Map.get(params, "summary", body),
            "body" => body,
            "tags" => Map.get(params, "tags", []),
            "source_type" => Map.get(params, "source_type", "user"),
            "source_id" => Map.get(params, "source_id"),
            "visibility" => Map.get(params, "visibility", "workspace"),
            "shared_org_id" => Arguments.parse_integer(params["shared_org_id"]),
            "metadata" => Map.get(params, "metadata", %{})
          }

          case Memory.record(attrs) do
            {:ok, record} ->
              conn
              |> put_status(:created)
              |> json(%{
                memory: %{id: record.id, record_type: record.record_type, title: record.title}
              })

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "invalid memory", details: changeset_errors(changeset)})
          end
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})
    end
  end

  # ─── Audit Log ────────────────────────────────────────────────────────────────

  def audit_log(conn, %{"id" => session_id} = params) do
    format = Map.get(params, "format", "json")

    with :ok <- authorize_session_access(conn, session_id, audit_scope_for(format)) do
      case format do
        "pdf" ->
          case Platform.export_audit_log(String.to_integer(session_id), "pdf") do
            {:ok, %{payload: payload}} ->
              conn
              |> put_resp_content_type("application/pdf")
              |> put_resp_header(
                "content-disposition",
                "attachment; filename=\"audit-log-#{session_id}.pdf\""
              )
              |> send_resp(200, payload)

            {:error, :renderer_unavailable} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "pdf_export_unavailable"})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "session not found"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end

        "csv" ->
          case Platform.export_audit_log(String.to_integer(session_id), "csv") do
            {:ok, %{payload: csv}} ->
              conn
              |> put_resp_content_type("text/csv")
              |> put_resp_header(
                "content-disposition",
                "attachment; filename=\"audit-log-#{session_id}.csv\""
              )
              |> send_resp(200, csv)

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "session not found"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end

        _ ->
          case Mission.audit_log(session_id) do
            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "session not found"})

            {:ok, log} ->
              _ = Platform.export_audit_log(String.to_integer(session_id), "json")
              json(conn, %{audit_log: log})
          end
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  # ─── Graph / Execution ───────────────────────────────────────────────────────

  def session_graph(conn, %{"id" => session_id}) do
    with :ok <- authorize_session_access(conn, session_id, "tasks:read") do
      session_id = String.to_integer(session_id)
      json(conn, %{graph: Platform.ensure_session_graph(session_id)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def execute_session(conn, %{"id" => session_id} = params) do
    with :ok <- authorize_session_access(conn, session_id, "tasks:execute") do
      {:ok, graph} = Platform.execute_session(String.to_integer(session_id), params)
      json(conn, %{graph: graph})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
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

      {:error, :proof_not_ready, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "proof_not_ready", message: reason})

      {:error, :budget_exhausted} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "budget_exhausted"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
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

  def claim_task(conn, %{"id" => task_id} = params) do
    with :ok <- authorize_task_access(conn, task_id, "tasks:claim") do
      case Platform.claim_task(String.to_integer(task_id), current_service_account(conn), params) do
        {:ok, task_run} ->
          json(conn, %{task_run: task_run_summary(task_run)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "task not found"})

        {:error, :budget_exhausted} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "budget_exhausted",
            message: "Session budget exhausted; use skip_budget_check/force to bypass."
          })

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "task not found"})
    end
  end

  def heartbeat_task(conn, %{"id" => task_id} = params) do
    with :ok <- authorize_task_access(conn, task_id, "tasks:report") do
      case Platform.heartbeat_task(
             String.to_integer(task_id),
             current_service_account(conn),
             params
           ) do
        {:ok, task_run} ->
          json(conn, %{task_run: task_run_summary(task_run)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "task run not found"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "task not found"})
    end
  end

  def task_checks(conn, %{"id" => task_id, "checks" => checks}) when is_list(checks) do
    with :ok <- authorize_task_access(conn, task_id, "tasks:report") do
      case Platform.record_task_checks(
             String.to_integer(task_id),
             current_service_account(conn),
             checks
           ) do
        {:ok, results} ->
          json(conn, %{checks: Enum.map(results, &task_check_summary/1)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "task run not found"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "task not found"})
    end
  end

  def task_checks(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: "checks must be a list"})
  end

  def report_task(conn, %{"id" => task_id} = params) do
    with :ok <- authorize_task_access(conn, task_id, "tasks:report") do
      case Platform.report_task(String.to_integer(task_id), current_service_account(conn), params) do
        {:ok, task_run} ->
          json(conn, %{task_run: task_run_summary(task_run)})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "task run not found"})

        {:error, {:unresolved_findings, findings, _task}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "task has unresolved findings",
            findings: Enum.map(findings, &finding_summary/1)
          })

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "task not found"})
    end
  end

  # ─── Platform ────────────────────────────────────────────────────────────────

  def list_service_accounts(conn, %{"id" => workspace_id}) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "service_accounts:read") do
      accounts =
        workspace_id
        |> String.to_integer()
        |> Platform.list_service_accounts()

      json(conn, %{service_accounts: Enum.map(accounts, &service_account_summary/1)})
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create_service_account(conn, %{"id" => workspace_id} = params) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "service_accounts:write") do
      actor = get_in(conn.assigns, [:current_user, :email])

      case Platform.provision_agent_identity(String.to_integer(workspace_id), params,
             actor: actor
           ) do
        {:ok, %{service_account: account, token: token}} ->
          conn
          |> put_status(:created)
          |> json(%{service_account: service_account_summary(account), token: token})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid service account", details: changeset_errors(changeset)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def rotate_service_account(conn, %{"id" => id}) do
    case Platform.get_service_account(String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "service account not found"})

      account ->
        with :ok <-
               authorize_workspace_for_conn(conn, account.workspace_id, "service_accounts:write") do
          actor = get_in(conn.assigns, [:current_user, :email])

          case Platform.rotate_agent_identity_token(String.to_integer(id), actor: actor) do
            {:ok, %{service_account: updated, token: token}} ->
              json(conn, %{service_account: service_account_summary(updated), token: token})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  def revoke_service_account(conn, %{"id" => id}) do
    case Platform.get_service_account(String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "service account not found"})

      account ->
        with :ok <-
               authorize_workspace_for_conn(conn, account.workspace_id, "service_accounts:write") do
          actor = get_in(conn.assigns, [:current_user, :email])

          case Platform.revoke_agent_identity(String.to_integer(id), actor: actor) do
            {:ok, revoked} ->
              json(conn, %{service_account: service_account_summary(revoked)})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not found"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  def list_nhi_audit_events(conn, %{"id" => id}) do
    case Platform.get_service_account(String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "service account not found"})

      account ->
        with :ok <-
               authorize_workspace_for_conn(conn, account.workspace_id, "service_accounts:read") do
          events = Platform.list_nhi_audit_events(String.to_integer(id))

          json(conn, %{
            events:
              Enum.map(events, fn e ->
                %{
                  id: e.id,
                  event_type: e.event_type,
                  actor: e.actor,
                  metadata: ControlKeel.Platform.NhiAuditEvent.decode_metadata(e),
                  occurred_at: e.occurred_at
                }
              end)
          })
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  def get_workspace_tool_policy(conn, %{"id" => workspace_id}) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "workspace:read") do
      policy = ControlKeel.Accounts.get_workspace_tool_policy(String.to_integer(workspace_id))

      json(conn, %{
        workspace_id: String.to_integer(workspace_id),
        mode: policy.mode,
        tools: ControlKeel.Accounts.WorkspaceToolPolicy.decode_tools(policy)
      })
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def set_workspace_tool_policy(conn, %{"id" => workspace_id} = params) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "workspace:write") do
      mode = params["mode"] || "inherit"
      tools = params["tools"] || []

      case ControlKeel.Accounts.set_workspace_tool_policy(
             String.to_integer(workspace_id),
             mode,
             tools
           ) do
        {:ok, policy} ->
          json(conn, %{
            workspace_id: String.to_integer(workspace_id),
            mode: policy.mode,
            tools: ControlKeel.Accounts.WorkspaceToolPolicy.decode_tools(policy)
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid policy", details: changeset_errors(changeset)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def list_workspace_policy_sets(conn, %{"id" => workspace_id}) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "policy_sets:read") do
      workspace_id = String.to_integer(workspace_id)

      json(conn, %{
        assignments:
          Enum.map(
            Platform.list_workspace_policy_sets(workspace_id),
            &policy_assignment_summary/1
          ),
        available_policy_sets: Enum.map(Platform.list_policy_sets(), &policy_set_summary/1)
      })
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create_policy_set(conn, %{"id" => workspace_id} = params) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "policy_sets:write") do
      case Platform.create_policy_set(params) do
        {:ok, policy_set} ->
          conn |> put_status(:created) |> json(%{policy_set: policy_set_summary(policy_set)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid policy set", details: changeset_errors(changeset)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def apply_policy_set(conn, %{"id" => workspace_id, "policy_set_id" => policy_set_id} = params) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "policy_sets:write") do
      case Platform.apply_policy_set(
             String.to_integer(workspace_id),
             String.to_integer(policy_set_id),
             params
           ) do
        {:ok, assignment} ->
          json(conn, %{
            assignment: policy_assignment_summary(Repo.preload(assignment, :policy_set))
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid policy assignment", details: changeset_errors(changeset)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def list_webhooks(conn, %{"id" => workspace_id}) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "webhooks:read") do
      webhooks =
        workspace_id
        |> String.to_integer()
        |> Platform.list_webhooks()

      json(conn, %{webhooks: Enum.map(webhooks, &webhook_summary/1)})
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create_webhook(conn, %{"id" => workspace_id} = params) do
    with :ok <- authorize_workspace_access(conn, workspace_id, "webhooks:write") do
      case Platform.create_webhook(String.to_integer(workspace_id), params) do
        {:ok, webhook} ->
          conn |> put_status(:created) |> json(%{webhook: webhook_summary(webhook)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid webhook", details: changeset_errors(changeset)})
      end
    else
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def replay_webhook(conn, %{"id" => id}) do
    case Platform.get_webhook(String.to_integer(id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "webhook not found"})

      webhook ->
        with :ok <- authorize_workspace_for_conn(conn, webhook.workspace_id, "webhooks:write") do
          case Platform.replay_webhook(String.to_integer(id)) do
            {:ok, delivery} ->
              json(conn, %{delivery: delivery_summary(delivery)})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "delivery not found"})

            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  # ─── Providers and Bootstrap ────────────────────────────────────────────────

  def list_providers(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    status = ProviderBroker.status(project_root)

    json(conn, %{
      project_root: status["project_root"],
      selected_source: status["selected_source"],
      selected_provider: status["selected_provider"],
      profiles: status["profiles"],
      attached_agents: status["attached_agents"]
    })
  end

  def provider_status(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    json(conn, %{status: ProviderBroker.status(project_root)})
  end

  def set_default_provider(conn, params) do
    source = Map.get(params, "source")
    scope = Map.get(params, "scope", "user")
    project_root = Map.get(params, "project_root", File.cwd!())

    case ProviderBroker.set_default_source(source, scope: scope, project_root: project_root) do
      {:ok, _config} ->
        json(conn, %{status: ProviderBroker.status(project_root)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def bootstrap_project(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    overrides = Map.take(params, ~w(agent))
    ephemeral_ok? = Map.get(params, "ephemeral_ok", true)

    case Local.load_or_bootstrap(project_root, overrides, ephemeral_ok: ephemeral_ok?) do
      {:ok, binding, session, mode} ->
        json(conn, %{
          binding: binding,
          session: session_summary(session),
          mode: mode,
          provider_status: ProviderBroker.status(project_root)
        })

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # ─── Repo Governance ────────────────────────────────────────────────────────

  def review_diff(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    session_id = Arguments.parse_integer(Map.get(params, "session_id"))

    with {:ok, base_ref} <- require_param(params, "base"),
         {:ok, head_ref} <- require_param(params, "head"),
         :ok <- maybe_authorize_review(conn, session_id),
         {:ok, review} <-
           Governance.review_diff(base_ref, head_ref,
             session_id: session_id,
             domain_pack: Map.get(params, "domain_pack"),
             project_root: project_root,
             dependency_review: Map.get(params, "dependency_review"),
             github: Map.get(params, "github")
           ) do
      json(conn, %{review: review})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :missing_param, key} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "`#{key}` is required"})

      {:error, message} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})
    end
  end

  def review_pr(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    session_id = Arguments.parse_integer(Map.get(params, "session_id"))

    governance_opts = [
      session_id: session_id,
      domain_pack: Map.get(params, "domain_pack"),
      project_root: project_root,
      dependency_review: Map.get(params, "dependency_review"),
      github: Map.get(params, "github")
    ]

    with :ok <- maybe_authorize_review(conn, session_id),
         {:ok, review} <- review_pr_request(params, governance_opts) do
      json(conn, %{review: review})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, message} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})
    end
  end

  defp review_pr_request(%{"pr_url" => pr_url}, opts) when is_binary(pr_url) and pr_url != "" do
    Governance.review_pr_url(pr_url, opts)
  end

  defp review_pr_request(%{"patch" => patch}, opts) when is_binary(patch) and patch != "" do
    Governance.review_patch(patch, opts)
  end

  defp review_pr_request(_params, _opts) do
    {:error, "Provide `patch` or `pr_url`."}
  end

  def release_readiness(conn, params) do
    session_id = Arguments.parse_integer(Map.get(params, "session_id"))

    with {:ok, session_id} <- ensure_integer_param(session_id, "session_id"),
         :ok <- authorize_session_access(conn, session_id, "tasks:read"),
         {:ok, readiness} <-
           Governance.release_readiness(%{
             session_id: session_id,
             sha: Map.get(params, "sha"),
             smoke: Map.get(params, "smoke"),
             provenance: Map.get(params, "provenance"),
             github: Map.get(params, "github")
           }) do
      json(conn, %{release: readiness})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :missing_param, key} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "`#{key}` is required"})

      {:error, message} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})
    end
  end

  def install_github_governance(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())

    case Governance.install_github_scaffolding(project_root) do
      {:ok, install} ->
        json(conn, %{install: install})

      {:error, message} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})
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
          disallowed_tools: s.disallowed_tools,
          required_mcp_tools: s.required_mcp_tools,
          context: s.context,
          agent: s.agent,
          paths: s.paths,
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
            disallowed_tools: skill.disallowed_tools,
            required_mcp_tools: skill.required_mcp_tools,
            context: skill.context,
            agent: skill.agent,
            paths: skill.paths,
            hooks: skill.hooks,
            model: skill.model,
            effort: skill.effort,
            shell: skill.shell,
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

  def list_skill_targets(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())

    json(conn, %{
      targets: Enum.map(Skills.targets(), &skill_target_summary/1),
      agents: Enum.map(Skills.agent_integrations(), &agent_integration_summary/1),
      registry_status: ACPRegistry.status(),
      installation_channels: Distribution.install_channels(),
      provider_status: ProviderBroker.status(project_root)
    })
  end

  def list_agents(conn, params) do
    project_root = Map.get(params, "project_root", File.cwd!())
    doctor = Execution.doctor(project_root)
    json(conn, %{agents: doctor["agents"], doctor: doctor})
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

    case Router.route(task_title, opts) do
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
      supported_scopes: target.supported_scopes,
      release_bundle: target.release_bundle
    }
  end

  defp fetch_review(review_id) do
    case Mission.get_review(review_id) do
      nil -> {:error, :not_found}
      review -> {:ok, review}
    end
  end

  defp review_summary(review) do
    review = Mission.get_review_with_context(review.id)

    %{
      id: review.id,
      title: review.title,
      review_type: review.review_type,
      status: review.status,
      session_id: review.session_id,
      task_id: review.task_id,
      submission_body: review.submission_body,
      annotations: review.annotations,
      feedback_notes: review.feedback_notes,
      agent_feedback: ControlKeel.Mission.ReviewBridge.agent_feedback(review),
      submitted_by: review.submitted_by,
      reviewed_by: review.reviewed_by,
      previous_review_id: review.previous_review_id,
      responded_at: review.responded_at,
      inserted_at: review.inserted_at,
      browser_url: ControlKeel.Mission.ReviewBridge.browser_url(review),
      task_title: review.task && review.task.title,
      previous_status: review.previous_review && review.previous_review.status
    }
  end

  defp agent_integration_summary(integration) do
    %{
      id: integration.id,
      label: integration.label,
      category: integration.category,
      support_class: integration.support_class,
      description: integration.description,
      attach_command: integration.attach_command,
      runtime_export_command: integration.runtime_export_command,
      config_location: integration.config_location,
      companion_delivery: integration.companion_delivery,
      install_experience: integration.install_experience,
      review_experience: integration.review_experience,
      submission_mode: integration.submission_mode,
      feedback_mode: integration.feedback_mode,
      phase_model: integration.phase_model,
      browser_embed: integration.browser_embed,
      subagent_visibility: integration.subagent_visibility,
      runtime_transport: integration.runtime_transport,
      runtime_auth_owner: integration.runtime_auth_owner,
      runtime_session_support: integration.runtime_session_support,
      runtime_review_transport: integration.runtime_review_transport,
      runtime_capabilities: integration.runtime_capabilities,
      plan_phase_support: integration.plan_phase_support,
      artifact_surfaces: integration.artifact_surfaces,
      package_outputs: integration.package_outputs,
      direct_install_methods: integration.direct_install_methods,
      confidence_level: integration.confidence_level,
      preferred_target: integration.preferred_target,
      default_scope: integration.default_scope,
      supported_scopes: integration.supported_scopes,
      router_agent_id: integration.router_agent_id,
      auto_bootstrap: integration.auto_bootstrap,
      provider_bridge: integration.provider_bridge,
      auth_mode: integration.auth_mode,
      auth_owner: ControlKeel.Agent.Integration.auth_owner(integration),
      mcp_mode: integration.mcp_mode,
      skills_mode: integration.skills_mode,
      alias_of: integration.alias_of,
      agent_uses_ck_via: integration.agent_uses_ck_via,
      ck_runs_agent_via: integration.ck_runs_agent_via,
      execution_support: integration.execution_support,
      autonomy_mode: integration.autonomy_mode,
      experience_profile: integration.experience_profile || %{},
      upstream_slug: integration.upstream_slug,
      upstream_docs_url: integration.upstream_docs_url,
      registry_match: integration.registry_match || false,
      registry_id: integration.registry_id,
      registry_version: integration.registry_version,
      registry_url: integration.registry_url,
      registry_stale: integration.registry_stale,
      required_mcp_tools: integration.required_mcp_tools,
      install_channels: ControlKeel.Agent.Integration.install_channels(integration.id),
      export_targets: integration.export_targets
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
      inserted_at: session.inserted_at,
      runtime_context: get_in(session.metadata || %{}, ["runtime_context"]),
      decomposition_strategy: get_in(session.metadata || %{}, ["decomposition_strategy"]),
      autonomy_profile: AutonomyLoop.session_autonomy_profile(session),
      outcome_profile: AutonomyLoop.session_outcome_profile(session)
    }
  end

  defp session_detail(session) do
    base = session_summary(session)

    Map.merge(base, %{
      execution_brief: session.execution_brief,
      session_metrics: ControlKeel.Analytics.session_metrics(session.id),
      improvement_loop: AutonomyLoop.session_improvement_loop(session),
      tasks: Enum.map(Map.get(session, :tasks, []), &task_summary/1),
      findings: Enum.map(Map.get(session, :findings, []), &finding_summary/1)
    })
  end

  defp session_create_attrs(params) do
    metadata =
      params
      |> Map.get("metadata", %{})
      |> normalize_session_metadata()
      |> maybe_put_string("autonomy_mode", Map.get(params, "autonomy_mode"))
      |> maybe_put_string("outcome_target", Map.get(params, "outcome_target"))
      |> maybe_put_string("outcome_metric", Map.get(params, "outcome_metric"))
      |> maybe_put_string("outcome_window", Map.get(params, "outcome_window"))

    params
    |> Map.take(
      ~w(title objective occupation domain_pack budget_cents daily_budget_cents risk_tier status spent_cents execution_brief workspace_id)
    )
    |> Map.put("metadata", metadata)
  end

  defp normalize_session_metadata(value) when is_map(value), do: value
  defp normalize_session_metadata(_value), do: %{}

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, _key, ""), do: map
  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  defp task_summary(task) do
    %{
      id: task.id,
      title: task.title,
      status: task.status,
      position: task.position,
      estimated_cost_cents: task.estimated_cost_cents,
      validation_gate: task.validation_gate,
      runtime_context: get_in(task.metadata || %{}, ["runtime_context"]),
      decomposition: Decomposition.task_summary(task),
      latest_proof: Mission.proof_summary_for_task(task),
      assurance: Mission.task_assurance_summary(task)
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

  defp benchmark_summary_payload(summary) do
    Map.update(summary, :latest_run, nil, fn
      nil -> nil
      run -> benchmark_run_summary(run)
    end)
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

  defp service_account_summary(account) do
    %{
      id: account.id,
      workspace_id: account.workspace_id,
      name: account.name,
      oauth_client_id: ProtocolAccess.oauth_client_id(account),
      scopes: ControlKeel.Platform.ServiceAccount.scope_list(account),
      status: account.status,
      last_used_at: account.last_used_at,
      inserted_at: account.inserted_at
    }
  end

  defp policy_set_summary(policy_set) do
    %{
      id: policy_set.id,
      name: policy_set.name,
      scope: policy_set.scope,
      description: policy_set.description,
      status: policy_set.status,
      rules_count: length(ControlKeel.Platform.PolicySet.rule_entries(policy_set)),
      metadata: policy_set.metadata
    }
  end

  defp policy_assignment_summary(assignment) do
    %{
      id: assignment.id,
      workspace_id: assignment.workspace_id,
      policy_set_id: assignment.policy_set_id,
      precedence: assignment.precedence,
      enabled: assignment.enabled,
      policy_set: assignment.policy_set && policy_set_summary(assignment.policy_set)
    }
  end

  defp webhook_summary(webhook) do
    %{
      id: webhook.id,
      workspace_id: webhook.workspace_id,
      name: webhook.name,
      url: webhook.url,
      subscribed_events: ControlKeel.Platform.IntegrationWebhook.event_list(webhook),
      status: webhook.status,
      inserted_at: webhook.inserted_at
    }
  end

  defp delivery_summary(delivery) do
    %{
      id: delivery.id,
      webhook_id: delivery.webhook_id,
      workspace_id: delivery.workspace_id,
      event: delivery.event,
      response_code: delivery.response_code,
      response_body: delivery.response_body,
      attempts: delivery.attempts,
      status: delivery.status,
      last_attempted_at: delivery.last_attempted_at,
      next_retry_at: delivery.next_retry_at
    }
  end

  defp task_run_summary(run) do
    %{
      id: run.id,
      task_id: run.task_id,
      session_id: run.session_id,
      service_account_id: run.service_account_id,
      status: run.status,
      execution_mode: run.execution_mode,
      claimed_at: run.claimed_at,
      started_at: run.started_at,
      finished_at: run.finished_at,
      external_ref: run.external_ref,
      output: run.output,
      metadata: run.metadata,
      checks: Enum.map(run.check_results || [], &task_check_summary/1)
    }
  end

  defp task_check_summary(check) do
    %{
      id: check.id,
      task_run_id: check.task_run_id,
      check_type: check.check_type,
      status: check.status,
      summary: check.summary,
      payload: check.payload
    }
  end

  defp agent_json_requested?(conn) do
    raw_query_format_agent?(conn.query_string) or
      Map.get(conn.query_params, "format") == "agent" or
      Map.get(conn.params, "format") == "agent" or
      Enum.any?(conn.req_headers, fn {key, value} ->
        (String.downcase(to_string(key)) == "accept" and
           String.contains?(to_string(value), "application/vnd.controlkeel.agent+json")) or
          (String.downcase(to_string(key)) == "user-agent" and
             String.contains?(String.downcase(to_string(value)), "opencode"))
      end)
  end

  defp raw_query_format_agent?(query_string) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
    |> Map.get("format")
    |> Kernel.==("agent")
  end

  defp raw_query_format_agent?(_query_string), do: false

  defp wrap_agent_json_response(%{resp_body: body} = conn) when not is_nil(body) do
    body_bin = IO.iodata_to_binary(body)

    case Jason.decode(body_bin) do
      {:ok, decoded} ->
        new_body = Jason.encode!(agent_envelope(conn, decoded))

        conn
        |> Map.put(:resp_body, new_body)
        |> Plug.Conn.put_resp_header("content-length", Integer.to_string(byte_size(new_body)))

      {:error, _} ->
        conn
    end
  end

  defp wrap_agent_json_response(conn), do: conn

  defp agent_envelope(_conn, %{"status" => "ok", "data" => _} = decoded), do: decoded
  defp agent_envelope(_conn, %{"status" => "error", "error" => _} = decoded), do: decoded

  defp agent_envelope(conn, decoded) when conn.status < 400 do
    %{
      status: "ok",
      command: api_command(conn),
      data: decoded,
      version: app_version()
    }
  end

  defp agent_envelope(conn, decoded) do
    %{
      status: "error",
      command: api_command(conn),
      error: api_error_message(decoded, conn.status),
      code: api_error_code(decoded, conn.status),
      details: decoded,
      version: app_version()
    }
  end

  defp api_command(conn) do
    explicit_command = conn.params["command"] || conn.params["method"]

    if is_binary(explicit_command) and explicit_command != "" do
      explicit_command
    else
      case Map.get(conn.private, :phoenix_action) do
        :list_providers -> "provider.list"
        :provider_status -> "config.providers"
        :list_agents -> "app.agents"
        :context -> "config.get"
        other -> to_string(other || "api")
      end
    end
  end

  defp api_error_message(%{"error" => error}, _status) when is_binary(error), do: error
  defp api_error_message(%{"message" => message}, _status) when is_binary(message), do: message
  defp api_error_message(_decoded, status), do: Plug.Conn.Status.reason_phrase(status)

  defp api_error_code(%{"code" => code}, _status) when is_binary(code), do: code

  defp api_error_code(_decoded, status),
    do:
      status |> Plug.Conn.Status.reason_phrase() |> String.downcase() |> String.replace(" ", "_")

  defp app_version do
    :controlkeel
    |> Application.spec(:vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  defp require_param(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_param, key}
    end
  end

  defp ensure_integer_param(nil, key), do: {:error, :missing_param, key}
  defp ensure_integer_param(value, _key), do: {:ok, value}

  defp maybe_authorize_review(_conn, nil), do: :ok

  defp maybe_authorize_review(conn, session_id) do
    authorize_session_access(conn, session_id, "tasks:execute")
  end

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  defp current_service_account(conn) do
    case conn.assigns[:api_auth] do
      %{type: :service_account, service_account: service_account} -> service_account
      _ -> nil
    end
  end

  defp memory_search_opts(conn, params) do
    session_id = Arguments.parse_integer(params["session_id"])

    case {session_id, current_service_account(conn)} do
      {nil, nil} ->
        {:ok, %{workspace_id: nil, org_id: nil, visibility: nil, session_id: nil}}

      {nil, %{workspace_id: workspace_id}} ->
        with :ok <- authorize_workspace_for_conn(conn, workspace_id, "memory:read") do
          {:ok, %{workspace_id: workspace_id, org_id: nil, visibility: nil, session_id: nil}}
        end

      {session_id, _account} when is_integer(session_id) ->
        with %{} = session <- Mission.get_session(session_id),
             :ok <- authorize_workspace_for_conn(conn, session.workspace_id, "memory:read") do
          {:ok,
           %{
             workspace_id: session.workspace_id,
             org_id: nil,
             visibility: nil,
             session_id: session_id
           }}
        else
          nil -> {:error, :not_found}
          {:error, :forbidden} -> {:error, :forbidden}
        end
    end
  end

  defp maybe_authorize_workspace_id(conn, workspace_id, scope) do
    case Arguments.parse_integer(workspace_id) do
      nil -> :ok
      parsed_id -> authorize_workspace_for_conn(conn, parsed_id, scope)
    end
  end

  defp authorize_review_target(conn, attrs) do
    cond do
      task_id = Arguments.parse_integer(attrs["task_id"] || attrs[:task_id]) ->
        authorize_task_access(conn, task_id, "reviews:write")

      session_id = Arguments.parse_integer(attrs["session_id"] || attrs[:session_id]) ->
        authorize_session_access(conn, session_id, "reviews:write")

      true ->
        :ok
    end
  end

  defp audit_scope_for("pdf"), do: "audit:export"
  defp audit_scope_for("csv"), do: "audit:read"
  defp audit_scope_for(_format), do: "audit:read"
end
