defmodule ControlKeel.MCP.ToolGroups do
  @moduledoc """
  Single source of truth for the MCP tool-to-group mapping.

  All modules that need to know which tools belong to which group must
  reference this module instead of maintaining their own copies.
  """

  @tool_groups %{
    "core" => [
      "ck_validate",
      "ck_context",
      "ck_context_pack",
      "ck_execute_code",
      "ck_budget",
      "ck_route",
      "ck_mcp_discover",
      "ck_token_audit",
      "ck_attach"
    ],
    "governance" => [
      "ck_review_submit",
      "ck_review_status",
      "ck_review_feedback",
      "ck_regression_result",
      "ck_finding",
      "ck_goal",
      "ck_memory_record",
      "ck_memory_search",
      "ck_memory_archive",
      "ck_delegate",
      "ck_result_peek",
      "ck_cost_optimizer",
      "ck_deployment_advisor",
      "ck_outcome_tracker",
      "ck_session_digest",
      "ck_loop",
      "ck_rollback",
      "ck_workspace_agent",
      "ck_copilot",
      "ck_external_service",
      "ck_task",
      "ck_session"
    ],
    "observability" => [
      "ck_observability",
      "ck_experience_index",
      "ck_experience_read",
      "ck_experience_search",
      "ck_trace_packet",
      "ck_failure_clusters",
      "ck_tool_health",
      "ck_skill_evolution"
    ],
    "skills" => [
      "ck_skill_list",
      "ck_skill_load",
      "ck_skill_validate",
      "ck_load_resources"
    ],
    "filesystem" => [
      "ck_fs_ls",
      "ck_fs_read",
      "ck_fs_find",
      "ck_fs_grep"
    ],
    "git" => [
      "ck_git_status",
      "ck_git_diff",
      "ck_git_commit"
    ],
    "checkpoints" => [
      "ck_checkpoint_create",
      "ck_checkpoint_restore",
      "ck_checkpoint_list"
    ],
    "worktrees" => [
      "ck_worktree_list",
      "ck_worktree_switch"
    ]
  }

  @doc "Returns the full group => tools map."
  def tool_groups_map, do: @tool_groups

  @doc "Returns the list of group names."
  def groups, do: Map.keys(@tool_groups)

  @doc "Returns the list of tool names for a given group, or empty list."
  def tools_for_group(group) when is_binary(group) do
    Map.get(@tool_groups, group, [])
  end

  @doc "Returns the inverse mapping: %{tool_name => group_name}."
  def tool_to_group_map do
    @tool_groups
    |> Enum.flat_map(fn {group, tools} ->
      Enum.map(tools, fn tool -> {tool, group} end)
    end)
    |> Map.new()
  end

  @doc "Returns the flat list of all tool names."
  def all_tools do
    @tool_groups
    |> Map.values()
    |> List.flatten()
  end
end
