defmodule ControlKeel.MCP.ToolGroupsTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.ToolGroups

  describe "groups/0" do
    test "returns all 8 group names" do
      groups = ToolGroups.groups()

      assert length(groups) == 8
      assert "core" in groups
      assert "governance" in groups
      assert "observability" in groups
      assert "skills" in groups
      assert "filesystem" in groups
      assert "git" in groups
      assert "checkpoints" in groups
      assert "worktrees" in groups
    end
  end

  describe "all_tools/0" do
    test "returns all tools" do
      tools = ToolGroups.all_tools()
      assert length(tools) == 54
    end

    test "includes the 7 previously missing tools" do
      tools = ToolGroups.all_tools()

      assert "ck_attach" in tools
      assert "ck_session_digest" in tools
      assert "ck_copilot" in tools
      assert "ck_external_service" in tools
      assert "ck_result_peek" in tools
      assert "ck_rollback" in tools
      assert "ck_workspace_agent" in tools
      assert "ck_task" in tools
      assert "ck_session" in tools
    end
  end

  describe "tool_to_group_map/0" do
    test "every tool has exactly one group" do
      frequencies = ToolGroups.all_tools() |> Enum.frequencies()
      map = ToolGroups.tool_to_group_map()

      assert Enum.all?(frequencies, fn {_tool, count} -> count == 1 end)
      assert map_size(map) == 54

      all_tools = ToolGroups.all_tools()
      assert MapSet.new(Map.keys(map)) == MapSet.new(all_tools)
    end
  end

  describe "tools_for_group/1" do
    test "returns tools for known groups" do
      assert length(ToolGroups.tools_for_group("core")) == 9
      assert length(ToolGroups.tools_for_group("governance")) == 21
      assert length(ToolGroups.tools_for_group("observability")) == 8
      assert length(ToolGroups.tools_for_group("skills")) == 4
      assert length(ToolGroups.tools_for_group("filesystem")) == 4
      assert length(ToolGroups.tools_for_group("git")) == 3
      assert length(ToolGroups.tools_for_group("checkpoints")) == 3
      assert length(ToolGroups.tools_for_group("worktrees")) == 2
    end

    test "returns empty list for unknown group" do
      assert ToolGroups.tools_for_group("nonexistent") == []
    end
  end

  describe "parity with Protocol and ToolGroupTracker" do
    test "Protocol.tool_groups/0 matches ToolGroups.groups/0" do
      protocol_groups = ControlKeel.MCP.Protocol.tool_groups() |> Enum.sort()
      shared_groups = ToolGroups.groups() |> Enum.sort()
      assert protocol_groups == shared_groups
    end

    test "tool group filtering in protocol uses same tool set" do
      all_from_protocol =
        ControlKeel.MCP.Protocol.tool_schemas(tool_groups: :all)
        |> Enum.map(& &1["name"])
        |> MapSet.new()

      all_from_groups = ToolGroups.all_tools() |> MapSet.new()

      assert all_from_groups == all_from_protocol
    end
  end
end
