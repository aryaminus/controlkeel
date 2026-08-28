defmodule ControlKeelWeb.API.FindingController do
  @moduledoc """
  `/api/v1` finding endpoints, extracted from `ApiController` as the first
  per-resource controller split. Authorization + shared rendering come from
  `ControlKeelWeb.APIHelpers`.
  """

  use ControlKeelWeb, :controller

  import ControlKeelWeb.APIHelpers

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def list_findings(conn, params) do
    opts =
      params
      |> Map.take(
        ~w(session_id severity status category finding_family patch_status disclosure_status maintainer_scope)
      )
      |> Enum.into(%{})
      |> Map.put("workspace_id", current_workspace_id(conn))

    page = Mission.browse_findings(opts)

    json(conn, %{
      findings: Enum.map(page.entries, &finding_summary/1),
      security_summary: page.security_summary,
      filters: page.filters,
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
        with :ok <- authorize_finding_access(conn, finding, "findings:write") do
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
        else
          {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
        end
    end
  end

  def create_finding(conn, params) do
    session_id = Arguments.parse_integer(params["session_id"])

    decision = Map.get(params, "decision", "warn")
    status = if decision == "block", do: "blocked", else: "open"

    attrs = %{
      "session_id" => session_id,
      "task_id" => Arguments.parse_integer(params["task_id"]),
      "category" => Map.get(params, "category", "security"),
      "severity" => Map.get(params, "severity", "medium"),
      "rule_id" => Map.get(params, "rule_id", "agent.manual_review"),
      "plain_message" => Map.get(params, "plain_message", ""),
      "title" => Map.get(params, "title", Map.get(params, "rule_id", "Finding")),
      "status" => status,
      "auto_resolved" => false,
      "metadata" => Map.get(params, "metadata", %{})
    }

    with :ok <- authorize_session_access(conn, session_id, "findings:write"),
         {:ok, finding} <- Mission.create_finding(attrs) do
      conn |> put_status(:created) |> json(%{finding: finding_summary(finding)})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid finding", details: changeset_errors(changeset)})
    end
  end
end
