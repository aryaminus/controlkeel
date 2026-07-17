defmodule ControlKeelWeb.CloudSyncController do
  @moduledoc """
  Bidirectional cloud-sync HTTP surface.

  Two actions:

    * `POST /cloud/v1/sync/push` — receives a batch of envelopes from an
      enrolled workspace and upserts them via `Cloud.Sync.upsert_batch/2`.
      Atomic per batch.

    * `POST /cloud/v1/sync/pull` — returns records for a workspace whose
      `synced_at` is newer than the requester's `since` timestamp. Covers all
      append-only kinds listed in `Cloud.Sync.append_only_schemas/0`
      (finding, review, session_digest, memory_record, invocation,
      proof_bundle, session_event, task_checkpoint, rollback_snapshot).

  Auth is bearer-token, verified by `Cloud.AuthToken.verify/1`. The token's
  `workspace_id` (cloud string UUID) is resolved to a local
  `Mission.Workspace.id` via `KeyRegistry.fetch/1`. Unmapped tokens
  return 404 — the caller should re-enroll.
  """

  use ControlKeelWeb, :controller

  require Logger

  alias ControlKeel.Cloud.{AuthToken, Sync, Workspace.KeyRegistry}
  alias ControlKeel.Repo

  plug :verify_sync_token when action in [:push, :pull]
  plug :resolve_db_workspace_id when action in [:push, :pull]

  @max_batch_count 500
  @max_batch_bytes 8 * 1024 * 1024

  def push(conn, %{"records" => records, "workspace_id" => ws_id}) do
    cloud_workspace_id = conn.assigns[:sync_workspace_id]

    cond do
      ws_id != cloud_workspace_id ->
        send_error(conn, :forbidden, "workspace_id mismatch")

      length(records) > @max_batch_count ->
        send_error(conn, :bad_request, "batch too large", %{max: @max_batch_count})

      true ->
        case Sync.upsert_batch(records,
               max_batch_bytes: @max_batch_bytes,
               allowed_workspace_id: conn.assigns[:db_workspace_id],
               target_workspace_id: conn.assigns[:db_workspace_id]
             ) do
          {:ok, result} ->
            json(conn, %{
              accepted: result.total,
              inserted: result.inserted,
              updated: result.updated,
              skipped: result.skipped,
              no_change: result.no_change,
              conflicts: result.conflicts
            })

          {:error, {:batch_too_large, info}} ->
            send_error(conn, :payload_too_large, "batch too large", info)
        end
    end
  end

  def push(conn, _params) do
    send_error(conn, :bad_request, "missing records or workspace_id")
  end

  def pull(conn, %{"since" => since_iso, "workspace_id" => ws_id}) do
    cloud_workspace_id = conn.assigns[:sync_workspace_id]
    db_workspace_id = conn.assigns[:db_workspace_id]

    cond do
      ws_id != cloud_workspace_id ->
        send_error(conn, :forbidden, "workspace_id mismatch")

      true ->
        since = parse_timestamp(since_iso)
        records = collect_since(db_workspace_id, since)

        json(conn, %{records: records, total: length(records)})
    end
  end

  def pull(conn, _params) do
    send_error(conn, :bad_request, "missing since or workspace_id")
  end

  # ── Auth plug ───────────────────────────────────────────────────────

  defp verify_sync_token(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case AuthToken.verify(token) do
          {:ok, %{workspace_id: workspace_id}} ->
            assign(conn, :sync_workspace_id, workspace_id)

          {:error, reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid token", reason: to_string(reason)})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing authorization header"})
        |> halt()
    end
  end

  # ── Workspace resolution plug ──────────────────────────────────────

  defp resolve_db_workspace_id(conn, _opts) do
    case conn.assigns[:sync_workspace_id] do
      ws_id when is_binary(ws_id) ->
        case KeyRegistry.fetch(ws_id) do
          {:ok, %{mission_workspace_id: id}} when is_integer(id) ->
            assign(conn, :db_workspace_id, id)

          _ ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "workspace not enrolled on this node"})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing workspace claim"})
        |> halt()
    end
  end

  # ── Pull helpers ────────────────────────────────────────────────────

  defp collect_since(db_workspace_id, since) when is_integer(db_workspace_id) do
    import Ecto.Query

    session_ids =
      ControlKeel.Mission.Session
      |> where([s], s.workspace_id == ^db_workspace_id)
      |> select([s], s.id)
      |> Repo.all()

    if session_ids == [] do
      []
    else
      Enum.flat_map(Sync.append_only_schemas(), fn {kind, schema} ->
        schema
        |> where([r], r.session_id in ^session_ids)
        |> where([r], r.synced_at > ^since)
        |> where([r], not is_nil(r.external_id))
        |> limit(500)
        |> Repo.all()
        |> Enum.map(&Sync.serialize_record({kind, &1}))
      end)
    end
  end

  defp collect_since(_, _), do: []

  defp parse_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now() |> DateTime.add(-3600, :second)
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now() |> DateTime.add(-3600, :second)

  defp send_error(conn, status, message, extra \\ %{}) do
    body = Map.merge(%{error: message}, extra)

    conn
    |> put_status(status)
    |> json(body)
  end
end
