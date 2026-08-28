defmodule ControlKeelWeb.APIHelpers do
  @moduledoc """
  Shared helpers for `/api/v1` controllers: workspace-scoped authorization
  (bootstrap vs service-account), integer param parsing, workspace resolution,
  and changeset error rendering.

  Extracted from `ApiController` so per-resource controllers (FindingController,
  …) share one authorization surface instead of duplicating privates.
  Controllers `import ControlKeel.Web.APIHelpers` — call sites stay unchanged.
  """

  alias ControlKeel.Mission
  alias ControlKeel.Platform

  @doc false
  def authorize_session_access(conn, session_id, scope) do
    with {:ok, parsed_id} <- parse_integer_param(session_id),
         %{} = session <- Mission.get_session(parsed_id) do
      authorize_workspace_for_conn(conn, session.workspace_id, scope)
    else
      {:error, :invalid_integer} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def authorize_finding_access(conn, finding, scope) do
    with %{} = session <- Mission.get_session(finding.session_id) do
      authorize_workspace_for_conn(conn, session.workspace_id, scope)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def authorize_task_access(conn, task_id, scope) do
    with {:ok, parsed_id} <- parse_integer_param(task_id),
         %{} = task <- Mission.get_task(parsed_id),
         %{} = session <- Mission.get_session(task.session_id) do
      authorize_workspace_for_conn(conn, session.workspace_id, scope)
    else
      {:error, :invalid_integer} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def authorize_workspace_access(conn, workspace_id, scope) do
    with {:ok, parsed_id} <- parse_integer_param(workspace_id) do
      authorize_workspace_for_conn(conn, parsed_id, scope)
    else
      {:error, :invalid_integer} -> {:error, :not_found}
    end
  end

  @doc false
  def authorize_workspace_for_conn(conn, workspace_id, scope) do
    case conn.assigns[:api_auth] do
      %{type: :bootstrap} ->
        :ok

      %{type: :service_account, service_account: service_account} ->
        if service_account.workspace_id == workspace_id and
             Platform.service_account_has_scope?(service_account, scope) do
          :ok
        else
          {:error, :forbidden}
        end

      _ ->
        :ok
    end
  end

  @doc false
  def current_workspace_id(conn) do
    case conn.assigns[:api_auth] do
      %{type: :service_account, service_account: %{workspace_id: ws_id}} when is_integer(ws_id) ->
        ws_id

      _ ->
        nil
    end
  end

  @doc false
  def parse_integer_param(value) when is_integer(value), do: {:ok, value}

  def parse_integer_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  def parse_integer_param(_), do: {:error, :invalid_integer}

  @doc false
  def finding_summary(finding) do
    summary = %{
      id: Map.get(finding, :id),
      rule_id: finding.rule_id,
      category: finding.category,
      severity: finding.severity,
      status: Map.get(finding, :status, "open"),
      plain_message: finding.plain_message,
      auto_fix_available: Map.get(finding, :auto_fix_available, false)
    }

    if ControlKeel.Governance.SecurityWorkflow.vulnerability_case?(finding) do
      Map.put(
        summary,
        :security_lifecycle,
        ControlKeel.Governance.SecurityWorkflow.vulnerability_case_summary(finding)
      )
    else
      summary
    end
  end

  @doc false
  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
