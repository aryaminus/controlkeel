defmodule ControlKeel.Cloud.Mcp.Policy do
  @moduledoc """
  Policy gate for hosted MCP / A2A tool dispatches.

  Sits in front of the scope-based authorization in `ProtocolInterop` and
  enforces:

    - **Tool deny-list** — workspaces (or global config) can mark specific
      tools as denied. The call is rejected with `:tool_denied` before any
      scope check runs.
    - **Per-window rate limits** — limit how many times a workspace can
      successfully call a tool in a rolling window, computed from the
      `cloud_mcp_tool_calls` audit log. Rejected with `:rate_limit_exceeded`.

  Both rules are config-driven (no schema needed yet) so this slice ships
  immediately. Workspace-level overrides will plug in once the accounts model
  arrives in Phase 4.

  ## Configuration

      config :controlkeel,
        cloud_mcp_policy: %{
          deny: ["ck_delegate"],                     # global deny list
          rate_limits: [
            %{tool: "ck_execute_code", per_minute: 30},
            %{tool: "*", per_minute: 600}            # catch-all
          ]
        }

  Empty config = no enforcement. The check call is a no-op.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.Mcp.ToolCall
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeel.Repo

  @typedoc "Policy verdict."
  @type verdict ::
          :ok
          | {:error, {:policy, :tool_denied | :rate_limit_exceeded}}

  @doc """
  Evaluate the policy for one prospective dispatch.

  Returns `:ok` to allow, `{:error, {:policy, reason}}` to deny. Callers should
  call `ControlKeel.Cloud.Mcp.AuditLog.record(:denied, ...)` themselves — this
  module only computes the verdict; it does not write the audit log.
  """
  @spec check(map(), String.t(), String.t()) :: verdict()
  def check(auth_context, tool_name, _resource_id)
      when is_map(auth_context) and is_binary(tool_name) do
    policy = current_policy()

    with :ok <- check_deny_list(policy, tool_name),
         :ok <- check_rate_limit(policy, auth_context, tool_name) do
      :ok
    end
  end

  defp check_deny_list(policy, tool_name) do
    deny = Map.get(policy, :deny, [])

    if is_list(deny) and tool_name in deny do
      {:error, {:policy, :tool_denied}}
    else
      :ok
    end
  end

  defp check_rate_limit(policy, auth_context, tool_name) do
    case rate_limit_for(policy, tool_name) do
      nil ->
        :ok

      %{window_seconds: window, max: max_calls} ->
        workspace_id = workspace_id_from(auth_context)
        cutoff = DateTime.utc_now() |> DateTime.add(-window, :second)

        count = count_recent_allowed(workspace_id, tool_name, cutoff)

        if count >= max_calls do
          {:error, {:policy, :rate_limit_exceeded}}
        else
          :ok
        end
    end
  end

  defp rate_limit_for(policy, tool_name) do
    rules = Map.get(policy, :rate_limits, [])

    rule =
      Enum.find(rules, fn r ->
        match = Map.get(r, :tool) || Map.get(r, "tool")
        match == tool_name
      end) || Enum.find(rules, fn r -> Map.get(r, :tool) == "*" or Map.get(r, "tool") == "*" end)

    case rule do
      nil ->
        nil

      %{} = r ->
        per_minute = Map.get(r, :per_minute) || Map.get(r, "per_minute")
        per_hour = Map.get(r, :per_hour) || Map.get(r, "per_hour")

        cond do
          is_integer(per_minute) and per_minute > 0 -> %{window_seconds: 60, max: per_minute}
          is_integer(per_hour) and per_hour > 0 -> %{window_seconds: 3_600, max: per_hour}
          true -> nil
        end
    end
  end

  defp workspace_id_from(%{service_account: %ServiceAccount{workspace_id: id}}), do: id
  defp workspace_id_from(%{workspace_id: id}) when is_integer(id), do: id
  defp workspace_id_from(_), do: nil

  defp count_recent_allowed(nil, tool_name, cutoff) do
    ToolCall
    |> where([c], is_nil(c.workspace_id))
    |> where([c], c.tool_name == ^tool_name and c.outcome == "allowed")
    |> where([c], c.requested_at >= ^cutoff)
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  defp count_recent_allowed(workspace_id, tool_name, cutoff) do
    ToolCall
    |> where([c], c.workspace_id == ^workspace_id)
    |> where([c], c.tool_name == ^tool_name)
    |> where([c], c.outcome == "allowed")
    |> where([c], c.requested_at >= ^cutoff)
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  defp current_policy do
    case Application.get_env(:controlkeel, :cloud_mcp_policy) do
      policy when is_map(policy) -> policy
      _ -> %{}
    end
  end
end
