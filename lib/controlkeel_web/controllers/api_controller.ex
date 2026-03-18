defmodule ControlKeelWeb.ApiController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Scanner.FastPath

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
    attrs = Map.take(params, ~w(title objective occupation domain_pack budget_cents daily_budget_cents risk_tier status spent_cents execution_brief workspace_id))

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

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
