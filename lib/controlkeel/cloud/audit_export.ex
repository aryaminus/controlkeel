defmodule ControlKeel.Cloud.AuditExport do
  @moduledoc """
  Structured audit-bundle exporter for SOC 2 / GDPR procurement.

  Distinct from `ControlKeel.AuditExports` which renders a single session's
  audit log as JSON/CSV/PDF. This module aggregates everything a compliance
  reviewer typically asks for across a workspace or an entire org over a time
  window:

    - findings (with severity/category/decision/rule_id)
    - reviews (with submitter, decider, status, role gates)
    - review_audit_events (assignment + decision audit trail)
    - mcp_tool_calls (hosted MCP / A2A authorization decisions)
    - cloud_run_packages (cloud-agent handoff lifecycle)
    - received_telemetry_events (incoming envelopes)
    - workspace identity fingerprint (when scope includes a workspace)

  The output is a plain JSON-serialisable map. Sensitive payload bodies are
  surfaced as-is for the workspace owner; downstream signing/encryption belongs
  to a follow-on slice once the secrets-management story lands.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Accounts.Org
  alias ControlKeel.Accounts.ReviewAuditEvent
  alias ControlKeel.Cloud.McpToolCall
  alias ControlKeel.Cloud.ReceivedTelemetryEvent
  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.WorkspaceIdentity
  alias ControlKeel.Cloud.WorkspaceKey
  alias ControlKeel.Mission.{Finding, Review, Session, Workspace}
  alias ControlKeel.Repo

  @schema_version "1"

  @typedoc "Scope of the export."
  @type scope :: {:workspace, integer()} | {:org, integer()}

  @doc """
  Build an audit bundle.

  Options:

    - `:workspace_id` — scope to a single workspace
    - `:org_id`       — scope to every workspace in the org (mutually exclusive with workspace_id)
    - `:since`        — UTC `DateTime` lower bound (inclusive); defaults to 90 days ago
    - `:until`        — UTC `DateTime` upper bound (inclusive); defaults to now

  Returns `{:error, :scope_required}` if neither `:workspace_id` nor `:org_id`
  is given, or `{:error, :unknown_workspace | :unknown_org}` when the named
  scope target does not exist.
  """
  @spec build(keyword()) :: {:ok, map()} | {:error, atom()}
  def build(opts) do
    with {:ok, scope} <- normalize_scope(opts),
         {:ok, workspace_ids} <- resolve_workspace_ids(scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      until_ts = Keyword.get(opts, :until, now)
      since_ts = Keyword.get(opts, :since, DateTime.add(now, -90 * 86_400, :second))

      bundle = %{
        "schema_version" => @schema_version,
        "generated_at" => DateTime.to_iso8601(now),
        "scope" => scope_repr(scope),
        "window" => %{
          "since" => DateTime.to_iso8601(since_ts),
          "until" => DateTime.to_iso8601(until_ts)
        },
        "workspace_identity" => workspace_identity_section(scope),
        "findings" => fetch_findings(workspace_ids, since_ts, until_ts),
        "reviews" => fetch_reviews(workspace_ids, since_ts, until_ts),
        "review_audit_events" => fetch_review_audit_events(workspace_ids, since_ts, until_ts),
        "mcp_tool_calls" => fetch_mcp_tool_calls(workspace_ids, since_ts, until_ts),
        "cloud_run_packages" => fetch_run_packages(workspace_ids, since_ts, until_ts),
        "received_telemetry_events" => fetch_received_events(workspace_ids, since_ts, until_ts)
      }

      {:ok, bundle}
    end
  end

  defp normalize_scope(opts) do
    case {Keyword.get(opts, :workspace_id), Keyword.get(opts, :org_id)} do
      {nil, nil} -> {:error, :scope_required}
      {id, nil} when is_integer(id) -> {:ok, {:workspace, id}}
      {nil, id} when is_integer(id) -> {:ok, {:org, id}}
      _ -> {:error, :scope_conflict}
    end
  end

  defp resolve_workspace_ids({:workspace, workspace_id}) do
    case Repo.get(Workspace, workspace_id) do
      nil -> {:error, :unknown_workspace}
      %Workspace{id: id} -> {:ok, [id]}
    end
  end

  defp resolve_workspace_ids({:org, org_id}) do
    case Repo.get(Org, org_id) do
      nil ->
        {:error, :unknown_org}

      %Org{id: id} ->
        ids =
          Workspace
          |> where([w], w.org_id == ^id)
          |> select([w], w.id)
          |> Repo.all()

        {:ok, ids}
    end
  end

  defp scope_repr({:workspace, id}), do: %{"type" => "workspace", "id" => id}
  defp scope_repr({:org, id}), do: %{"type" => "org", "id" => id}

  defp workspace_identity_section({:workspace, _}) do
    case WorkspaceIdentity.load() do
      {:ok, identity} ->
        %{
          "workspace_id_label" => identity.workspace_id,
          "fingerprint" => identity.fingerprint,
          "algorithm" => identity.algorithm
        }

      _ ->
        nil
    end
  end

  defp workspace_identity_section(_), do: nil

  defp fetch_findings([], _since, _until), do: []

  defp fetch_findings(workspace_ids, since_ts, until_ts) do
    query =
      from f in Finding,
        join: s in Session,
        on: s.id == f.session_id,
        where: s.workspace_id in ^workspace_ids,
        where: f.inserted_at >= ^since_ts,
        where: f.inserted_at <= ^until_ts,
        order_by: [asc: f.inserted_at]

    query
    |> Repo.all()
    |> Enum.map(fn f ->
      %{
        "id" => f.id,
        "session_id" => f.session_id,
        "category" => f.category,
        "severity" => f.severity,
        "rule_id" => f.rule_id,
        "title" => f.title,
        "plain_message" => f.plain_message,
        "status" => f.status,
        "policy_snapshot" => get_in(f.metadata || %{}, ["policy_snapshot"]),
        "artifact_snapshot" => get_in(f.metadata || %{}, ["artifact_snapshot"]),
        "model_provenance" => get_in(f.metadata || %{}, ["model_provenance"]),
        "inserted_at" => iso(f.inserted_at)
      }
    end)
  end

  defp fetch_reviews([], _since, _until), do: []

  defp fetch_reviews(workspace_ids, since_ts, until_ts) do
    query =
      from r in Review,
        join: s in Session,
        on: s.id == r.session_id,
        where: s.workspace_id in ^workspace_ids,
        where: r.inserted_at >= ^since_ts,
        where: r.inserted_at <= ^until_ts,
        order_by: [asc: r.inserted_at]

    query
    |> Repo.all()
    |> Enum.map(fn r ->
      %{
        "id" => r.id,
        "title" => r.title,
        "review_type" => r.review_type,
        "status" => r.status,
        "submitted_by" => r.submitted_by,
        "reviewed_by" => r.reviewed_by,
        "assigned_user_id" => r.assigned_user_id,
        "decided_by_user_id" => r.decided_by_user_id,
        "required_role" => r.required_role,
        "session_id" => r.session_id,
        "task_id" => r.task_id,
        "policy_snapshot" => get_in(r.metadata || %{}, ["policy_snapshot"]),
        "artifact_snapshot" => get_in(r.metadata || %{}, ["artifact_snapshot"]),
        "model_provenance" => get_in(r.metadata || %{}, ["model_provenance"]),
        "responded_at" => iso(r.responded_at),
        "inserted_at" => iso(r.inserted_at)
      }
    end)
  end

  defp fetch_review_audit_events([], _since, _until), do: []

  defp fetch_review_audit_events(workspace_ids, since_ts, until_ts) do
    query =
      from e in ReviewAuditEvent,
        join: r in Review,
        on: r.id == e.review_id,
        join: s in Session,
        on: s.id == r.session_id,
        where: s.workspace_id in ^workspace_ids,
        where: e.recorded_at >= ^since_ts,
        where: e.recorded_at <= ^until_ts,
        order_by: [asc: e.recorded_at, asc: e.id]

    query
    |> Repo.all()
    |> Enum.map(fn e ->
      %{
        "id" => e.id,
        "review_id" => e.review_id,
        "event_type" => e.event_type,
        "actor_user_id" => e.actor_user_id,
        "target_user_id" => e.target_user_id,
        "required_role" => e.required_role,
        "actor_role" => e.actor_role,
        "actor_source" => e.actor_source,
        "actor_identifier" => e.actor_identifier,
        "note" => e.note,
        "recorded_at" => iso(e.recorded_at)
      }
    end)
  end

  defp fetch_mcp_tool_calls([], _since, _until), do: []

  defp fetch_mcp_tool_calls(workspace_ids, since_ts, until_ts) do
    query =
      from c in McpToolCall,
        where: c.workspace_id in ^workspace_ids,
        where: c.requested_at >= ^since_ts,
        where: c.requested_at <= ^until_ts,
        order_by: [asc: c.requested_at, asc: c.id]

    query
    |> Repo.all()
    |> Enum.map(fn c ->
      %{
        "id" => c.id,
        "workspace_id" => c.workspace_id,
        "service_account_id" => c.service_account_id,
        "resource" => c.resource,
        "tool_name" => c.tool_name,
        "outcome" => c.outcome,
        "denial_reason" => c.denial_reason,
        "scopes_granted" => c.scopes_granted,
        "argument_keys" => c.argument_keys,
        "requested_at" => iso(c.requested_at)
      }
    end)
  end

  defp fetch_run_packages([], _since, _until), do: []

  defp fetch_run_packages(workspace_ids, since_ts, until_ts) do
    query =
      from p in RunPackage,
        where: p.workspace_id in ^workspace_ids,
        where: p.inserted_at >= ^since_ts,
        where: p.inserted_at <= ^until_ts,
        order_by: [asc: p.inserted_at, asc: p.id]

    query
    |> Repo.all()
    |> Enum.map(fn p ->
      %{
        "id" => p.id,
        "workspace_id" => p.workspace_id,
        "session_id" => p.session_id,
        "task_id" => p.task_id,
        "runtime_target" => p.runtime_target,
        "status" => p.status,
        "budget_cents_allocated" => p.budget_cents_allocated,
        "scopes" => p.scopes,
        "proof_refs" => p.proof_refs,
        "result_summary" => p.result_summary,
        "error_summary" => p.error_summary,
        "dispatched_at" => iso(p.dispatched_at),
        "completed_at" => iso(p.completed_at),
        "inserted_at" => iso(p.inserted_at)
      }
    end)
  end

  defp fetch_received_events([], _since, _until), do: []

  defp fetch_received_events(workspace_ids, since_ts, until_ts) do
    # ReceivedTelemetryEvent.workspace_id is a string (cloud ws_id like "ws_abc"),
    # but workspace_ids are local integer IDs. Resolve via WorkspaceKey registry.
    cloud_ws_ids =
      from(k in WorkspaceKey,
        where: k.mission_workspace_id in ^workspace_ids,
        where: is_nil(k.revoked_at),
        select: k.workspace_id
      )
      |> Repo.all()

    case cloud_ws_ids do
      [] -> []
      ids -> query_received_events(ids, since_ts, until_ts)
    end
  end

  defp query_received_events(cloud_workspace_ids, since_ts, until_ts) do
    query =
      from e in ReceivedTelemetryEvent,
        where: e.workspace_id in ^cloud_workspace_ids,
        where: e.received_at >= ^since_ts,
        where: e.received_at <= ^until_ts,
        order_by: [asc: e.received_at, asc: e.id]

    query
    |> Repo.all()
    |> Enum.map(fn e ->
      %{
        "id" => e.id,
        "event_id" => e.event_id,
        "workspace_id" => e.workspace_id,
        "kind" => e.kind,
        "redaction_policy_version" => e.redaction_policy_version,
        "schema_version" => e.schema_version,
        "emitted_at" => iso(e.emitted_at),
        "received_at" => iso(e.received_at)
      }
    end)
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
