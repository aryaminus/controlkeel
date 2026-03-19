defmodule ControlKeelWeb.ApiController do
  use ControlKeelWeb, :controller

  alias ControlKeel.AgentRouter
  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Scanner.FastPath
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
    input = Map.take(params, ~w(content path kind session_id))

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

  # ─── Skills ───────────────────────────────────────────────────────────────────

  def list_skills(conn, params) do
    project_root = Map.get(params, "project_root")
    format = Map.get(params, "format", "json")
    skills = Registry.catalog(project_root)

    entries =
      Enum.map(skills, fn s ->
        %{
          name: s.name,
          description: s.description,
          scope: s.scope,
          allowed_tools: s.allowed_tools,
          license: s.license,
          compatibility: s.compatibility
        }
      end)

    result = %{skills: entries, total: length(entries)}

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
            license: skill.license,
            compatibility: skill.compatibility,
            body: skill.body
          }
        })
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
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

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
      validation_gate: task.validation_gate
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

  defp audit_log_to_csv(%{events: events, session_id: sid, session_title: title}) do
    header = "session_id,session_title,timestamp,type,rule_id,severity,category,status,plain_message,source,tool,provider,model,decision,cost_cents,tokens\r\n"

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
end
