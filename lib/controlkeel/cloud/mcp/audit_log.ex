defmodule ControlKeel.Cloud.Mcp.AuditLog do
  @moduledoc """
  Persistent audit trail for hosted MCP and A2A tool dispatches.

  Logs every authorization decision (allowed or denied) so operators can answer:

    - Which tools is each workspace calling, and how often?
    - Which calls are being denied, and why?
    - Which service accounts are active?

  Argument values are never persisted — only the top-level argument keys. The
  audit log is forensics, not a data sink.

  Fail-soft: a logging failure must never break an authorized tool call. All
  writes are wrapped in rescue/catch.
  """

  require Logger

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.Mcp.ToolCall
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeel.Repo

  @max_argument_keys 16

  @doc """
  Record an authorization decision.

  `outcome` is `:allowed` or `:denied`. When denied, `reason` is a short
  human-readable token (e.g., "invalid_scope", "workspace_scope_violation").
  """
  @spec record(:allowed | :denied, map()) :: :ok
  def record(outcome, attrs) when outcome in [:allowed, :denied] and is_map(attrs) do
    do_record(outcome, attrs)
    :ok
  rescue
    error ->
      Logger.warning("Cloud.AuditLog: record failed: #{inspect(error)}")
      :ok
  catch
    kind, value ->
      Logger.warning("Cloud.AuditLog: caught #{inspect(kind)} #{inspect(value)}")
      :ok
  end

  @doc "Record a decision whose persistence is required before dispatch."
  def record_required(outcome, attrs) when outcome in [:allowed, :denied] and is_map(attrs) do
    case do_record(outcome, attrs) do
      {:ok, _row} -> :ok
      {:error, _reason} -> {:error, :audit_unavailable}
    end
  rescue
    _ -> {:error, :audit_unavailable}
  catch
    _, _ -> {:error, :audit_unavailable}
  end

  defp do_record(outcome, attrs) do
    %ToolCall{}
    |> ToolCall.changeset(%{
      workspace_id: workspace_id(attrs),
      service_account_id: service_account_id(attrs),
      resource: to_string(Map.get(attrs, :resource, "mcp")),
      tool_name: to_string(Map.get(attrs, :tool_name, "unknown")),
      outcome: Atom.to_string(outcome),
      denial_reason: maybe_to_string(Map.get(attrs, :denial_reason)),
      scopes_granted: encode_scopes(Map.get(attrs, :scopes)),
      argument_keys: encode_argument_keys(Map.get(attrs, :arguments)),
      requested_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  defp workspace_id(%{service_account: %ServiceAccount{workspace_id: id}}), do: id
  defp workspace_id(%{workspace_id: id}) when is_integer(id), do: id
  defp workspace_id(_), do: nil

  defp service_account_id(%{service_account: %ServiceAccount{id: id}}), do: id
  defp service_account_id(_), do: nil

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value) when is_binary(value), do: value
  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: inspect(value)

  defp encode_scopes(nil), do: nil
  defp encode_scopes(scopes) when is_list(scopes), do: Enum.join(scopes, ",")
  defp encode_scopes(other), do: inspect(other)

  defp encode_argument_keys(nil), do: nil

  defp encode_argument_keys(args) when is_map(args) do
    args
    |> Map.keys()
    |> Enum.take(@max_argument_keys)
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp encode_argument_keys(_), do: nil

  @doc "Total persisted calls."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(ToolCall, :count, :id)

  # --- Workspace-scoped variants (tenant-facing) ---

  @doc """
  Counts grouped by tool_name + outcome for a single workspace, descending by total.
  """
  @spec counts_by_tool(integer()) ::
          [%{tool_name: String.t(), allowed: non_neg_integer(), denied: non_neg_integer()}]
  def counts_by_tool(workspace_id) when is_integer(workspace_id) do
    ToolCall
    |> where([c], c.workspace_id == ^workspace_id)
    |> group_by([c], [c.tool_name, c.outcome])
    |> select([c], {c.tool_name, c.outcome, count(c.id)})
    |> Repo.all()
    |> group_and_format_tools()
  end

  @doc """
  Aggregate counts for a single workspace.
  """
  @spec summary(integer()) :: %{
          total: non_neg_integer(),
          allowed: non_neg_integer(),
          denied: non_neg_integer()
        }
  def summary(workspace_id) when is_integer(workspace_id) do
    rows =
      ToolCall
      |> where([c], c.workspace_id == ^workspace_id)
      |> group_by([c], c.outcome)
      |> select([c], {c.outcome, count(c.id)})
      |> Repo.all()
      |> Map.new()

    format_summary(rows)
  end

  @doc """
  Recent calls for a single workspace, newest first, capped to `:limit` (default 50).
  """
  @spec recent(integer(), keyword()) :: [ToolCall.t()]
  def recent(workspace_id, opts \\ []) when is_integer(workspace_id) do
    limit = Keyword.get(opts, :limit, 50)

    ToolCall
    |> where([c], c.workspace_id == ^workspace_id)
    |> order_by([c], desc: c.requested_at, desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # --- Global admin variants (operator dashboard only) ---

  @doc """
  Counts grouped by tool_name + outcome across ALL workspaces.

  **Admin only.** Use `counts_by_tool(workspace_id)` for tenant-facing surfaces.
  """
  @spec global_counts_by_tool() ::
          [%{tool_name: String.t(), allowed: non_neg_integer(), denied: non_neg_integer()}]
  def global_counts_by_tool do
    ToolCall
    |> group_by([c], [c.tool_name, c.outcome])
    |> select([c], {c.tool_name, c.outcome, count(c.id)})
    |> Repo.all()
    |> group_and_format_tools()
  end

  @doc """
  Aggregate counts across ALL workspaces.

  **Admin only.** Use `summary(workspace_id)` for tenant-facing surfaces.
  """
  @spec global_summary() :: %{
          total: non_neg_integer(),
          allowed: non_neg_integer(),
          denied: non_neg_integer()
        }
  def global_summary do
    rows =
      ToolCall
      |> group_by([c], c.outcome)
      |> select([c], {c.outcome, count(c.id)})
      |> Repo.all()
      |> Map.new()

    format_summary(rows)
  end

  @doc """
  Recent calls across ALL workspaces, newest first, capped to `:limit` (default 50).

  **Admin only.** Use `recent(workspace_id, opts)` for tenant-facing surfaces.
  """
  @spec global_recent(keyword()) :: [ToolCall.t()]
  def global_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ToolCall
    |> order_by([c], desc: c.requested_at, desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # --- Shared helpers ---

  defp group_and_format_tools(rows) do
    rows
    |> Enum.group_by(fn {tool, _outcome, _n} -> tool end)
    |> Enum.map(fn {tool, grouped} ->
      stats =
        Enum.reduce(grouped, %{allowed: 0, denied: 0}, fn {_tool, outcome, n}, acc ->
          case outcome do
            "allowed" -> Map.update!(acc, :allowed, &(&1 + n))
            "denied" -> Map.update!(acc, :denied, &(&1 + n))
            _ -> acc
          end
        end)

      Map.put(stats, :tool_name, tool)
    end)
    |> Enum.sort_by(&(&1.allowed + &1.denied), :desc)
  end

  defp format_summary(rows) do
    allowed = Map.get(rows, "allowed", 0)
    denied = Map.get(rows, "denied", 0)
    %{total: allowed + denied, allowed: allowed, denied: denied}
  end
end
