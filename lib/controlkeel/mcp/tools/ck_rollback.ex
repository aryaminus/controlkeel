defmodule ControlKeel.MCP.Tools.CkRollback do
  @moduledoc false

  alias ControlKeel.Governance.RollbackExecutor
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Rollback operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    with {:ok, session} <- Arguments.fetch_session(arguments) do
      id = session.id
      mode = Map.get(arguments, "mode", "status")
      project_root = session_project_root(session, arguments)

      case mode do
        "checkpoint" ->
          task_id = Arguments.parse_integer(arguments["task_id"])

          case task_id do
            nil ->
              {:error, {:invalid_arguments, "`task_id` is required for checkpoint mode"}}

            tid ->
              with :ok <- Arguments.validate_task(tid, id) do
                case RollbackExecutor.checkpoint(id, tid, project_root: project_root) do
                  {:ok, snapshot} -> {:ok, format_snapshot(snapshot)}
                  {:error, reason} -> {:error, reason}
                end
              end
          end

        "execute" ->
          task_id = Arguments.parse_integer(arguments["task_id"])
          reason = Map.get(arguments, "reason", "Operator-initiated rollback")

          case task_id do
            nil ->
              {:error, {:invalid_arguments, "`task_id` is required for execute mode"}}

            tid ->
              with :ok <- Arguments.validate_task(tid, id) do
                case RollbackExecutor.execute(id, tid, project_root: project_root, reason: reason) do
                  {:ok, snapshot} -> {:ok, format_snapshot(snapshot)}
                  {:error, reason} -> {:error, reason}
                end
              end
          end

        "status" ->
          task_id = Arguments.parse_integer(arguments["task_id"])

          case task_id do
            nil ->
              {:error, {:invalid_arguments, "`task_id` is required for status mode"}}

            tid ->
              with :ok <- Arguments.validate_task(tid, id) do
                case RollbackExecutor.status(id, tid) do
                  nil -> {:ok, %{"message" => "No snapshot found"}}
                  snapshot -> {:ok, format_snapshot(snapshot)}
                end
              end
          end

        "list" ->
          snapshots = RollbackExecutor.list(id)

          {:ok,
           %{
             "snapshots" => Enum.map(snapshots, &format_snapshot/1),
             "count" => length(snapshots)
           }}

        _ ->
          {:error, {:invalid_arguments, "mode must be checkpoint, execute, status, or list"}}
      end
    end
  end

  defp format_snapshot(snapshot) do
    %{
      "id" => snapshot.id,
      "session_id" => snapshot.session_id,
      "task_id" => snapshot.task_id,
      "commit_sha_before" => snapshot.commit_sha_before,
      "commit_sha_after" => snapshot.commit_sha_after,
      "status" => snapshot.status,
      "rollback_method" => snapshot.rollback_method,
      "rolled_back_at" => snapshot.rolled_back_at,
      "rolled_back_by" => snapshot.rolled_back_by,
      "finding_id" => snapshot.finding_id
    }
  end

  # Session runtime_context wins over the explicit arg, which wins over cwd —
  # same precedence as ck_worktree_switch, so one MCP server across repos
  # still operates on the session's own checkout.
  defp session_project_root(session, arguments) do
    runtime_root = get_in(session.metadata || %{}, ["runtime_context", "project_root"])

    cond do
      is_binary(runtime_root) and runtime_root != "" ->
        Path.expand(runtime_root)

      is_binary(arguments["project_root"]) and arguments["project_root"] != "" ->
        Path.expand(arguments["project_root"])

      true ->
        File.cwd!()
    end
  end
end
