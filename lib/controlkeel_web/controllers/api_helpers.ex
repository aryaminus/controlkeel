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
        authorize_bootstrap(conn, workspace_id, scope)

      # Unauthenticated loopback caller (local default, no token configured).
      # Recorded explicitly by Plugs.ApiAuth; unscoped by design for
      # single-user local operation.
      %{type: :local} ->
        :ok

      %{type: :service_account, service_account: service_account} ->
        if service_account.workspace_id == workspace_id and
             Platform.service_account_has_scope?(service_account, scope) do
          :ok
        else
          {:error, :forbidden}
        end

      # No credential was ever established (ApiAuth did not run, or a future
      # branch forgets to assign). Fail closed rather than authorize.
      _ ->
        {:error, :forbidden}
    end
  end

  # The bootstrap token is a break-glass credential, not a platform superuser.
  #
  # Previously it authorized every workspace unconditionally, so one leaked
  # env var was a silent, total cross-tenant compromise. Break-glass best
  # practice (OWASP, CyberArk, Microsoft Zero Trust) converges on four
  # properties: no standing privilege, least privilege for the actual task,
  # explicit activation, and full auditing of every use. This implements the
  # first two; the credential is opt-in per environment and scoped to a single
  # workspace rather than the whole platform.
  #
  # Local single-user mode is unaffected - this is a hosted-mode control.
  defp authorize_bootstrap(conn, workspace_id, _scope) do
    cond do
      ControlKeel.Runtime.Mode.current() == :local ->
        :ok

      not break_glass_enabled?() ->
        {:error, :forbidden}

      # Scoped break-glass: the operator must name the one workspace the
      # credential may act on. Without it, there is no least-privilege bound.
      is_nil(break_glass_workspace_id()) ->
        {:error, :forbidden}

      true ->
        if break_glass_workspace_id() == workspace_id do
          audit_break_glass_use(conn, workspace_id)
          :ok
        else
          {:error, :forbidden}
        end
    end
  end

  defp break_glass_enabled? do
    truthy?(Application.get_env(:controlkeel, :break_glass_enabled, false))
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp break_glass_workspace_id do
    case Application.get_env(:controlkeel, :break_glass_workspace_id) do
      id when is_integer(id) ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Every break-glass use is recorded. A credential that bypasses per-tenant
  # isolation is exactly the thing that must leave a trail.
  defp audit_break_glass_use(conn, workspace_id) do
    ControlKeel.Platform.record_nhi_event(nil, "break_glass_api_access",
      actor: "bootstrap-token",
      metadata: %{
        "workspace_id" => workspace_id,
        "path" => conn.request_path,
        "method" => conn.method,
        "remote_ip" => inspect(conn.remote_ip)
      }
    )
  rescue
    _ -> :ok
  end

  @doc """
  Resolves the `project_root` an API caller may operate on.

  Authenticated callers (bootstrap token or service account) may pass any
  root, preserving CLI/automation workflows.

  Unauthenticated callers (local no-token default) are pinned to the
  server's governed root: an absent param resolves to it, and a supplied
  root that resolves elsewhere is rejected with
  `{:error, :project_root_not_authorized}`. This keeps the skills/config
  endpoints from becoming arbitrary-filesystem read/write primitives.
  """
  def authorized_project_root(conn, params) do
    supplied = Map.get(params, "project_root")

    case conn.assigns[:api_auth] do
      %{type: auth_type} when auth_type in [:bootstrap, :service_account] ->
        {:ok, supplied || File.cwd!()}

      _ ->
        governed_root = ControlKeel.Project.Root.resolve(File.cwd!())

        case supplied do
          nil ->
            {:ok, governed_root}

          root when is_binary(root) and root != "" ->
            if ControlKeel.Project.Root.resolve(root) == governed_root do
              {:ok, governed_root}
            else
              {:error, :project_root_not_authorized}
            end

          _ ->
            {:error, :project_root_not_authorized}
        end
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
