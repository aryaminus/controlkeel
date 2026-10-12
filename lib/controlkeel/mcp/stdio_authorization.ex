defmodule ControlKeel.Mcp.StdioAuthorization do
  @moduledoc """
  Authorization gate for the local stdio MCP transport.

  The hosted transport (`ControlKeel.Mcp.ProtocolInterop`) routes every
  `tools/call` through `Policy.check/3`, `Accounts.check_workspace_tool_policy/2`,
  `Guardrails.scan/2`, service-account scope verification, and `AuditLog.record/2`.
  The stdio transport — the default for Claude Code, Cursor, and Codex, i.e. how
  most agents actually connect — bypassed that chain entirely.
  `ControlKeel.MCP.Server` never passed an `:authorize` closure, so
  `ControlKeel.MCP.Protocol.authorize_tool/3` returned `:ok` for every call and
  no audit row was written. Ungoverned stdio also served the full tool catalog,
  including tools the hosted whitelist deliberately withholds.

  This module restores the subset of the hosted chain that needs no principal.
  There is no CLI identity to authenticate, so the service-account stages
  (`Policy.check/3`, resource access, tool scopes) remain unavailable. The two
  stages that are pure functions of (workspace, tool, arguments) are enforced:

    * `Accounts.check_workspace_tool_policy/2` — per-workspace allow/deny lists
    * `Guardrails.scan/2` — inbound secret-pattern scanning

  Every decision, allowed or denied, is written to `AuditLog`, so stdio traffic
  becomes as visible as hosted traffic.

  Tool parity with the hosted catalog is deliberately not enforced here. The
  hosted whitelist is sized for multi-tenant callers authenticated by a service
  account; stdio runs as the developer's own OS identity on their own checkout,
  and withholding `ck_execute_code`, `ck_git_commit`, `ck_rollback`,
  `ck_checkpoint_restore`, `ck_worktree_switch`, and `ck_external_service` there
  would remove capabilities `controlkeel attach` promises to local agents. Those
  tools are now *governed* on stdio instead of *hidden*: a workspace tool policy
  can deny any of them, and the existing `tool_groups` binding/env filters can
  still remove them from `tools/list`.

  ## Workspace resolution

  The workspace comes from the project binding ControlKeel already writes at
  `controlkeel/project.json` (or its ephemeral variant) — the same file
  `ControlKeel.MCP.Protocol` reads for adaptive tool-group selection.
  `CK_PROJECT_ROOT` selects it, falling back to the server's working directory.

  ## Fail-open and fail-closed

    * **No binding** (`{:error, :not_found}`) → local single-user mode. There is
      no workspace, so there is no workspace tool policy to enforce;
      `Accounts.check_workspace_tool_policy(nil, _)` is `:ok` by definition.
      Calls are allowed and still audited with a `NULL` workspace, so a project
      that was never bootstrapped keeps working and stays observable.
    * **Unreadable or tampered binding** (any other read error) → denied. A
      corrupt binding is not proof that the project is unbound, so it must not
      silently downgrade a governed project into local mode.
    * **Policy or guardrail evaluation raises or exits** → denied. When
      ControlKeel cannot prove a call is allowed it must not answer "allowed".

  Guardrails still run with no workspace bound: they are an application-level
  operator setting (disabled by default), not per-workspace state, so they carry
  no attribution requirement.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Guardrails
  alias ControlKeel.Cloud.Mcp.AuditLog
  alias ControlKeel.Project.Binding

  @resource "mcp-stdio"

  @typedoc "Authorization closure shape consumed by `ControlKeel.MCP.Protocol`."
  @type authorizer :: (String.t(), map() -> :ok | {:error, term()})

  @doc """
  Builds the `:authorize` closure for a stdio server rooted at `project_root`.
  """
  @spec authorize_fun(Path.t()) :: authorizer()
  def authorize_fun(project_root) when is_binary(project_root) do
    fn tool_name, arguments -> authorize_tool_call(project_root, tool_name, arguments) end
  end

  @doc """
  Authorizes one stdio `tools/call` and audits the decision.

  Returns `:ok` or `{:error, {:forbidden, message}}`, which
  `ControlKeel.MCP.Protocol` renders as JSON-RPC error `-32001` for the agent.
  """
  @spec authorize_tool_call(Path.t(), String.t(), map()) ::
          :ok | {:error, {:forbidden, String.t()}}
  def authorize_tool_call(project_root, tool_name, arguments)
      when is_binary(project_root) and is_binary(tool_name) and is_map(arguments) do
    case Binding.read_effective(project_root) do
      {:ok, %{"workspace_id" => id}, _mode} when is_integer(id) ->
        gate_and_audit(id, tool_name, arguments)

      {:error, :not_found} ->
        gate_and_audit(nil, tool_name, arguments)

      {:error, reason} ->
        deny_and_audit(nil, tool_name, arguments, "binding:#{binding_token(reason)}")
    end
  end

  defp gate_and_audit(workspace_id, tool_name, arguments) do
    case gate(workspace_id, tool_name, arguments) do
      :ok ->
        audit_record(:allowed, workspace_id, tool_name, arguments, nil)
        :ok

      {:denied, token, message} ->
        audit_record(:denied, workspace_id, tool_name, arguments, token)
        {:error, {:forbidden, message}}
    end
  end

  defp deny_and_audit(workspace_id, tool_name, arguments, token) do
    audit_record(:denied, workspace_id, tool_name, arguments, token)

    {:error,
     {:forbidden,
      "ControlKeel could not resolve this project's workspace binding (#{token}); the tool call was denied rather than run ungoverned."}}
  end

  defp gate(workspace_id, tool_name, arguments) do
    with :ok <- tool_policy_verdict(workspace_id, tool_name),
         :ok <- guardrails_verdict(tool_name, arguments),
         do: :ok
  rescue
    error -> unavailable(tool_name, Exception.message(error))
  catch
    kind, _value -> unavailable(tool_name, inspect(kind))
  end

  defp tool_policy_verdict(workspace_id, tool_name) do
    case Accounts.check_workspace_tool_policy(workspace_id, tool_name) do
      :ok ->
        :ok

      {:error, reason} ->
        deny("policy:" <> policy_token(reason), policy_message(tool_name, reason))
    end
  end

  defp policy_message(tool_name, {:policy, :tool_not_in_workspace_allowlist}) do
    "#{tool_name} is not in this project's workspace tool allowlist."
  end

  defp policy_message(tool_name, {:policy, :tool_in_workspace_denylist}) do
    "#{tool_name} is denied by this project's workspace tool denylist."
  end

  defp policy_message(tool_name, reason) do
    "#{tool_name} is denied by this project's workspace tool policy (#{policy_token(reason)})."
  end

  defp guardrails_verdict(tool_name, arguments) do
    case Guardrails.scan(arguments, tool_name) do
      :ok ->
        :ok

      {:error, {:guardrail, pattern}} ->
        deny("guardrail:#{pattern}", "Blocked by ControlKeel guardrail #{pattern}.")

      {:error, _reason} ->
        deny("guardrail:blocked", "Blocked by a ControlKeel content guardrail.")
    end
  end

  defp unavailable(tool_name, detail) do
    deny(
      "policy:evaluation_unavailable",
      "ControlKeel could not evaluate workspace tool policy for #{tool_name} (#{detail})."
    )
  end

  defp deny(token, message), do: {:denied, token, message}

  defp policy_token({:policy, sub}) when is_atom(sub), do: Atom.to_string(sub)
  defp policy_token(reason), do: reason |> inspect() |> String.slice(0, 80)

  defp binding_token(reason), do: reason |> inspect() |> String.slice(0, 80)

  defp audit_record(outcome, workspace_id, tool_name, arguments, denial_reason) do
    AuditLog.record(outcome, %{
      workspace_id: workspace_id,
      tool_name: tool_name,
      resource: @resource,
      arguments: arguments,
      denial_reason: denial_reason
    })
  end
end
