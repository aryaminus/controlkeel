defmodule ControlKeel.MCP.OutputSchemasTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.MCP.OutputSchemas
  alias ControlKeel.MCP.Protocol
  alias ControlKeel.MCP.ToolGroups

  describe "schema_for/1" do
    test "returns a schema for every known tool" do
      for tool_name <- ToolGroups.all_tools() do
        schema = OutputSchemas.schema_for(tool_name)

        assert is_map(schema), "Expected schema for #{tool_name} to be a map"
        assert schema["type"] == "object", "Expected #{tool_name} schema type to be object"
        assert is_map(schema["properties"]), "Expected #{tool_name} schema to have properties map"

        assert map_size(schema["properties"]) > 0,
               "Expected #{tool_name} schema properties to be non-empty"
      end
    end

    test "returns generic schema for unknown tool" do
      schema = OutputSchemas.schema_for("ck_nonexistent_tool")

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "status")
      assert Map.has_key?(schema["properties"], "data")
    end

    test "ck_validate schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_validate")
      props = schema["properties"]

      assert Map.has_key?(props, "allowed")
      assert Map.has_key?(props, "decision")
      assert Map.has_key?(props, "summary")
      assert Map.has_key?(props, "findings")
      assert Map.has_key?(props, "fix_prompts")
      assert Map.has_key?(props, "scanned_at")
      assert Map.has_key?(props, "advisory")
    end

    test "ck_context schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_context")
      props = schema["properties"]

      assert Map.has_key?(props, "session_id")
      assert Map.has_key?(props, "budget_summary")
      assert Map.has_key?(props, "active_findings")
      assert Map.has_key?(props, "proof_summary")
      assert Map.has_key?(props, "workspace_context")
      assert Map.has_key?(props, "detail_level")
    end

    test "ck_context schema matches nullable and object-shaped runtime fields" do
      props = OutputSchemas.schema_for("ck_context")["properties"]

      assert props["attach_advisory"]["type"] == ["object", "string", "null"]
      assert props["past_patterns"]["type"] == ["object", "array"]
      assert props["proof_summary"]["type"] == ["object", "null"]
      assert props["current_task"]["type"] == ["object", "null"]
      assert props["workspace_cache_key"]["type"] == ["string", "null"]
    end

    test "ck_validate schema allows nullable scanner fields" do
      props = OutputSchemas.schema_for("ck_validate")["properties"]
      finding_props = get_in(props, ["findings", "items", "properties"])

      assert props["advisory"]["type"] == ["object", "null"]
      assert props["trust_policy_advisory"]["type"] == ["string", "null"]
      assert finding_props["id"]["type"] == ["string", "null"]
      assert finding_props["location"]["type"] == ["object", "null"]
    end

    test "ck_finding schema allows nullable relationship fields" do
      props = OutputSchemas.schema_for("ck_finding")["properties"]

      assert props["extends_finding_id"]["type"] == ["integer", "null"]
      assert props["contradicts_finding_id"]["type"] == ["integer", "null"]
    end

    test "ck_review_submit and ck_review_status schemas allow nullable review_url" do
      for tool <- ~w(ck_review_submit ck_review_status) do
        props = OutputSchemas.schema_for(tool)["properties"]

        assert props["review_url"]["type"] == ["string", "null"],
               "#{tool} review_url should accept nil for stdio MCP mode"
      end
    end

    test "ck_finding schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_finding")
      props = schema["properties"]

      assert Map.has_key?(props, "finding_id")
      assert Map.has_key?(props, "status")
      assert Map.has_key?(props, "requires_human")
      assert Map.has_key?(props, "resolved_findings_count")
      assert Map.has_key?(props, "summary")
    end
  end

  describe "inject/1" do
    test "injects outputSchema into a tool definition" do
      tool_def = %{"name" => "ck_validate", "description" => "test", "inputSchema" => %{}}
      result = OutputSchemas.inject(tool_def)

      assert Map.has_key?(result, "outputSchema")
      assert result["outputSchema"]["type"] == "object"
      assert Map.has_key?(result["outputSchema"]["properties"], "allowed")
    end

    test "preserves existing keys" do
      tool_def = %{"name" => "ck_route", "description" => "test", "inputSchema" => %{}}
      result = OutputSchemas.inject(tool_def)

      assert result["name"] == "ck_route"
      assert result["description"] == "test"
      assert Map.has_key?(result, "inputSchema")
      assert Map.has_key?(result, "outputSchema")
    end
  end

  describe "tools/list output schema integration" do
    test "all tools returned by tools/list have outputSchema" do
      response =
        Protocol.handle_request(
          %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "tools/list"
          },
          tool_groups: :all
        )

      assert %{"result" => %{"tools" => tools}} = response
      assert length(tools) > 0

      for tool <- tools do
        name = tool["name"]

        assert Map.has_key?(tool, "outputSchema"),
               "Tool #{name} is missing outputSchema"

        schema = tool["outputSchema"]

        assert schema["type"] == "object",
               "Tool #{name} outputSchema type should be 'object', got: #{inspect(schema["type"])}"

        assert is_map(schema["properties"]),
               "Tool #{name} outputSchema should have properties map"

        assert map_size(schema["properties"]) > 0,
               "Tool #{name} outputSchema properties should not be empty"
      end
    end

    test "all tools have output schema definitions" do
      exposed_tools = Protocol.tool_schemas(tool_groups: :all) |> Enum.map(& &1["name"])

      assert MapSet.new(OutputSchemas.tool_names()) == MapSet.new(exposed_tools)
      assert MapSet.new(ToolGroups.all_tools()) == MapSet.new(exposed_tools)
    end
  end

  describe "declared output schema matches the real tool payload (no drift)" do
    test "ck_execute_code structuredContent keys match its declared schema" do
      assert {:ok, payload} =
               ControlKeel.MCP.Tools.CkExecuteCode.call(%{
                 "code" => "console.log(1 + 1)",
                 "language" => "javascript",
                 "dry_run" => true
               })

      declared =
        OutputSchemas.schema_for("ck_execute_code")["properties"] |> Map.keys() |> MapSet.new()

      actual = payload |> Map.keys() |> MapSet.new()

      assert MapSet.subset?(actual, declared),
             "ck_execute_code payload keys drifted from outputSchema.\n  payload: #{inspect(Enum.sort(MapSet.to_list(actual)))}\n  schema:  #{inspect(Enum.sort(MapSet.to_list(declared)))}"
    end

    test "ck_context_pack structuredContent keys match its declared schema" do
      session = session_fixture()

      assert {:ok, payload} =
               ControlKeel.MCP.Tools.CkContextPack.call(%{"session_id" => session.id})

      declared =
        OutputSchemas.schema_for("ck_context_pack")["properties"] |> Map.keys() |> MapSet.new()

      actual = payload |> Map.keys() |> MapSet.new()

      assert MapSet.subset?(actual, declared),
             "ck_context_pack payload includes keys absent from outputSchema.\n  payload: #{inspect(Enum.sort(MapSet.to_list(actual)))}\n  schema:  #{inspect(Enum.sort(MapSet.to_list(declared)))}"
    end

    test "ck_context_pack count_only response keys are declared" do
      session = session_fixture()

      assert {:ok, payload} =
               ControlKeel.MCP.Tools.CkContextPack.call(%{
                 "session_id" => session.id,
                 "count_only" => true
               })

      declared =
        OutputSchemas.schema_for("ck_context_pack")["properties"] |> Map.keys() |> MapSet.new()

      actual = payload |> Map.keys() |> MapSet.new()

      assert MapSet.subset?(actual, declared),
             "ck_context_pack count_only payload includes keys absent from outputSchema.\n  payload: #{inspect(Enum.sort(MapSet.to_list(actual)))}\n  schema:  #{inspect(Enum.sort(MapSet.to_list(declared)))}"
    end
  end

  describe "tool annotations" do
    test "inject/1 attaches read-only/destructive annotations" do
      ro = OutputSchemas.inject(%{"name" => "ck_context"})["annotations"]
      assert ro["readOnlyHint"] == true
      assert ro["destructiveHint"] == false

      wr = OutputSchemas.inject(%{"name" => "ck_finding"})["annotations"]
      assert wr["readOnlyHint"] == false

      destructive = OutputSchemas.inject(%{"name" => "ck_rollback"})["annotations"]
      assert destructive["readOnlyHint"] == false
      assert destructive["destructiveHint"] == true
    end

    test "SAFETY: no known side-effecting tool is ever advertised as read-only" do
      # Tools that mutate state, run code, write files, or spend budget. The dangerous
      # annotation error is marking one of these readOnlyHint:true, so guard it explicitly.
      known_writes = ~w(
        ck_finding ck_memory_record ck_memory_archive ck_review_submit ck_review_feedback
        ck_regression_result ck_budget ck_outcome_tracker ck_git_commit ck_rollback
        ck_delegate ck_execute_code ck_attach ck_session ck_checkpoint_create
        ck_checkpoint_restore ck_worktree_switch ck_goal
      )

      # Note: ck_validate is read-only per its description ("Read-only — no changes applied");
      # ck_session_digest has both generate (write) and latest/list (read) modes so it is
      # conservatively left unclassified, not listed here as a known writer.

      for tool <- known_writes do
        refute ControlKeel.MCP.Annotations.for_tool(tool)["readOnlyHint"],
               "#{tool} has side effects but is annotated readOnlyHint:true"
      end
    end
  end
end
