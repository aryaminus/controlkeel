defmodule ControlKeel.Mission.FindingOps do
  @moduledoc """
  Finding disposition operations extracted from the `Mission` context.

  Owns the approve / reject / escalate / bulk-disposition surface and the
  atomic status+audit Multi that guarantees every disposition leaves an
  append-only `FindingAuditEvent` trail. `Mission` delegates to this module,
  so all existing `Mission.*` call sites keep working.

  Read paths (`get_finding/1`, `list_findings_for_session/1`) and the
  memory/event emitters stay in `Mission`; this module calls back into them.
  """

  import Ecto.Query, only: [where: 3, order_by: 3]

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Finding
  alias ControlKeel.Mission.FindingAuditEvent
  alias ControlKeel.Repo
  alias ControlKeel.Repo.Retry, as: RepoRetry
  alias Ecto.Multi

  @disposition_actions ~w(resolve dismiss escalate)
  @disposition_statuses ~w(open blocked escalated)

  def disposition_actions, do: @disposition_actions

  def approve_finding(finding_or_id, opts \\ [])

  def approve_finding(%Finding{} = finding, opts) when is_list(opts) do
    metadata =
      Map.merge(finding.metadata || %{}, %{
        "approved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding_with_audit(
           finding,
           %{status: "approved", metadata: metadata},
           :approved,
           opts
         ) do
      {:ok, updated} ->
        Mission.emit_finding_event(:approved, updated)
        Mission.record_finding_memory(:approved, updated)
        Mission.emit_platform_finding_event("finding.approved", updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def approve_finding(id, opts) when is_integer(id) and is_list(opts) do
    case Mission.get_finding(id) do
      nil -> {:error, :not_found}
      finding -> approve_finding(finding, opts)
    end
  end

  def reject_finding(finding_or_id, reason \\ nil, opts \\ [])

  def reject_finding(%Finding{} = finding, reason, opts) when is_list(opts) do
    metadata =
      finding.metadata
      |> Kernel.||(%{})
      |> Map.merge(%{
        "rejected_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })
      |> maybe_put_metadata("rejection_reason", reason)

    case update_finding_with_audit(
           finding,
           %{status: "rejected", metadata: metadata},
           :rejected,
           Keyword.put(opts, :reason, reason)
         ) do
      {:ok, updated} ->
        Mission.emit_finding_event(:rejected, updated)
        Mission.record_finding_memory(:rejected, updated)
        Mission.emit_platform_finding_event("finding.rejected", updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def reject_finding(id, reason, opts) when is_integer(id) and is_list(opts) do
    case Mission.get_finding(id) do
      nil -> {:error, :not_found}
      finding -> reject_finding(finding, reason, opts)
    end
  end

  def escalate_finding(finding_or_id, opts \\ [])

  def escalate_finding(%Finding{} = finding, opts) when is_list(opts) do
    metadata =
      Map.merge(finding.metadata || %{}, %{
        "escalated_at" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    case update_finding_with_audit(
           finding,
           %{status: "escalated", metadata: metadata},
           :escalated,
           opts
         ) do
      {:ok, updated} ->
        Mission.emit_finding_event(:escalated, updated)
        Mission.record_finding_memory(:escalated, updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def escalate_finding(id, opts) when is_integer(id) and is_list(opts) do
    case Mission.get_finding(id) do
      nil -> {:error, :not_found}
      finding -> escalate_finding(finding, opts)
    end
  end

  @doc """
  Disposition a single finding via a high-level action so agents (and bulk paths) can
  resolve the findings they create instead of only filing compensating records:

    * `"resolve"`  -> approved
    * `"dismiss"`  -> rejected (records `opts[:reason]`)
    * `"escalate"` -> escalated

  Accepts a `%Finding{}` or an integer id. Returns `{:ok, finding}` / `{:error, reason}`.
  """
  def dispose_finding(action, finding_or_id, opts \\ [])

  def dispose_finding(action, %Finding{} = finding, opts),
    do: do_dispose_finding(action, finding, opts)

  def dispose_finding(action, id, opts) when is_integer(id) do
    case Mission.get_finding(id) do
      nil -> {:error, :not_found}
      finding -> do_dispose_finding(action, finding, opts)
    end
  end

  @doc """
  Bulk-disposition findings in a session matching a filter map.

  Filter keys: `:rule_id`, `:category`, `:statuses` (defaults to the active set
  `~w(open blocked escalated)`), and `:reason` (recorded when dismissing). Only findings
  currently in the matched statuses are touched, so the operation is idempotent. Returns
  `{:ok, %{count: n, ids: [finding_id]}}`.
  """
  def dispose_session_findings(session_id, filter, action)
      when is_integer(session_id) and action in @disposition_actions do
    reason = Map.get(filter, :reason)
    disposition_opts = Map.get(filter, :disposition_opts, [])

    ids =
      session_id
      |> Mission.list_findings_for_session()
      |> Enum.filter(&matches_disposition_filter?(&1, filter))
      |> Enum.reduce([], fn finding, acc ->
        case do_dispose_finding(action, finding, Keyword.put(disposition_opts, :reason, reason)) do
          {:ok, updated} -> [updated.id | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, %{count: length(ids), ids: ids}}
  end

  def dispose_session_findings(_session_id, _filter, _action), do: {:error, :invalid_action}

  @doc """
  Bulk-disposition a list of finding ids via a single action (`resolve`,
  `dismiss`, or `escalate`). Dismissals record `opts[:reason]` on the finding
  metadata and audit event. Only findings currently in an active status
  (`open`, `blocked`, `escalated`) are touched, so the operation is idempotent.
  Returns `{:ok, %{count: n, ids: [finding_id]}}`.
  """
  def dispose_findings(ids, action, opts \\ []) when is_list(ids) do
    if action in @disposition_actions do
      disposition_opts = Keyword.put(opts, :reason, opts[:reason] && to_string(opts[:reason]))

      ids =
        Enum.reduce(ids, [], fn id, acc ->
          with %Finding{status: status} <- Mission.get_finding(id),
               true <- status in @disposition_statuses,
               {:ok, updated} <- do_dispose_finding(action, id, disposition_opts) do
            [updated.id | acc]
          else
            _ -> acc
          end
        end)
        |> Enum.reverse()

      {:ok, %{count: length(ids), ids: ids}}
    else
      {:error, :invalid_action}
    end
  end

  @doc "List append-only audit events for a finding, oldest first."
  @spec finding_audit_events(integer()) :: [FindingAuditEvent.t()]
  def finding_audit_events(finding_id) when is_integer(finding_id) do
    FindingAuditEvent
    |> where([event], event.finding_id == ^finding_id)
    |> order_by([event], asc: event.recorded_at, asc: event.id)
    |> Repo.all()
  end

  # ─── Privates ────────────────────────────────────────────────────────────────

  defp do_dispose_finding("resolve", finding, opts), do: approve_finding(finding, opts)

  defp do_dispose_finding("dismiss", finding, opts),
    do: reject_finding(finding, Keyword.get(opts, :reason), opts)

  defp do_dispose_finding("escalate", finding, opts), do: escalate_finding(finding, opts)
  defp do_dispose_finding(_action, _finding, _opts), do: {:error, :invalid_action}

  defp matches_disposition_filter?(finding, filter) do
    statuses = Map.get(filter, :statuses) || ~w(open blocked escalated)

    finding.status in statuses and
      disposition_filter_match?(finding.rule_id, Map.get(filter, :rule_id)) and
      disposition_filter_match?(finding.category, Map.get(filter, :category))
  end

  defp disposition_filter_match?(_value, nil), do: true
  defp disposition_filter_match?(value, expected), do: value == expected

  # Atomically persist a finding status change and its append-only audit event.
  # Mirrors the review-decision Multi in respond_review so the lineage guarantee
  # holds even under a failed audit insert: the status update and the audit row
  # commit together or roll back together (no status change without a trail).
  defp update_finding_with_audit(finding, attrs, event_type, opts) do
    Multi.new()
    |> Multi.update(:finding, Finding.changeset(finding, attrs))
    |> Multi.insert(:finding_audit_event, fn %{finding: updated} ->
      FindingAuditEvent.changeset(
        %FindingAuditEvent{},
        finding_audit_attrs(event_type, finding, updated, opts)
      )
    end)
    |> RepoRetry.transaction_with_busy_retry()
    |> case do
      {:ok, %{finding: updated}} -> {:ok, updated}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp finding_audit_attrs(event_type, previous, updated, opts) do
    actor_source = Keyword.get(opts, :actor_source) || "unknown"

    %{
      finding_id: updated.id,
      event_type: Atom.to_string(event_type),
      previous_status: previous.status,
      new_status: updated.status,
      reason: Keyword.get(opts, :reason),
      actor_user_id: Keyword.get(opts, :actor_user_id),
      actor_source: actor_source,
      actor_identifier: Keyword.get(opts, :actor_identifier) || actor_source,
      recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
