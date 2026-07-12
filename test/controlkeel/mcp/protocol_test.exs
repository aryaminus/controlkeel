defmodule ControlKeel.MCP.ProtocolTest do
  use ControlKeel.DataCase

  alias ControlKeel.Accounts
  alias ControlKeel.MCP.Protocol
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Project.Binding
  alias ControlKeel.Repo
  alias ControlKeel.Skills.Activation

  import ControlKeel.IntentFixtures
  import ControlKeel.MissionFixtures

  setup do
    Activation.reset()
    :ok
  end

  test "initialize succeeds" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize"
      })

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "protocolVersion" => _,
               "capabilities" => %{
                 "tools" => %{"listChanged" => false},
                 "resources" => %{"subscribe" => false, "listChanged" => false}
               },
               "serverInfo" => %{"name" => "controlkeel"}
             }
           } = response
  end

  test "tools/list returns all controlkeel tools in stable order" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    assert %{"result" => %{"tools" => tools}} = response

    assert Enum.map(tools, & &1["name"]) == [
             "ck_validate",
             "ck_execute_code",
             "ck_context",
             "ck_context_pack",
             "ck_observability",
             "ck_experience_index",
             "ck_experience_read",
             "ck_experience_search",
             "ck_trace_packet",
             "ck_failure_clusters",
             "ck_tool_health",
             "ck_skill_evolution",
             "ck_fs_ls",
             "ck_fs_read",
             "ck_fs_find",
             "ck_fs_grep",
             "ck_worktree_list",
             "ck_worktree_switch",
             "ck_checkpoint_create",
             "ck_checkpoint_restore",
             "ck_checkpoint_list",
             "ck_git_diff",
             "ck_git_commit",
             "ck_git_status",
             "ck_finding",
             "ck_review_submit",
             "ck_review_status",
             "ck_review_feedback",
             "ck_regression_result",
             "ck_memory_search",
             "ck_memory_record",
             "ck_goal",
             "ck_memory_archive",
             "ck_budget",
             "ck_route",
             "ck_delegate",
             "ck_result_peek",
             "ck_cost_optimizer",
             "ck_deployment_advisor",
             "ck_outcome_tracker",
             "ck_load_resources",
             "ck_mcp_discover",
             "ck_token_audit",
             "ck_attach",
             "ck_session_digest",
             "ck_loop",
             "ck_rollback",
             "ck_workspace_agent",
             "ck_copilot",
             "ck_external_service",
             "ck_task",
             "ck_session",
             "ck_skill_list",
             "ck_skill_load",
             "ck_skill_validate"
           ]
  end

  test "tool_schemas/1 with tool_groups: :all returns all tools bypassing env var" do
    # Simulate CK_TOOL_GROUPS=core being set
    System.put_env("CK_TOOL_GROUPS", "core")

    on_exit(fn -> System.delete_env("CK_TOOL_GROUPS") end)

    all_tools = Protocol.tool_schemas(tool_groups: :all)
    core_tools = Protocol.tool_schemas()

    assert length(all_tools) > length(core_tools)
    all_names = Enum.map(all_tools, & &1["name"])
    assert "ck_token_audit" in all_names
    assert "ck_observability" in all_names
  end

  test "tool_schemas/1 with CK_TOOL_GROUPS env var filters to requested groups" do
    System.put_env("CK_TOOL_GROUPS", "core")
    on_exit(fn -> System.delete_env("CK_TOOL_GROUPS") end)

    tools = Protocol.tool_schemas()
    names = Enum.map(tools, & &1["name"])

    assert "ck_validate" in names
    assert "ck_context" in names
    assert "ck_budget" in names
    # ck_attach is core because one-line-MCP-install users need it to wire
    # hooks/skills without leaving the agent session.
    assert "ck_attach" in names
    refute "ck_observability" in names
    refute "ck_finding" in names
  end

  test "ck_attach tool schema is exposed with the host required field" do
    tools = Protocol.tool_schemas(tool_groups: :all)
    attach = Enum.find(tools, &(&1["name"] == "ck_attach"))

    assert attach != nil
    assert attach["inputSchema"]["required"] == ["host"]
    assert get_in(attach, ["inputSchema", "properties", "host", "type"]) == "string"
    # Description must mention the one-line install path so LLMs know when to call it.
    assert attach["description"] =~ "one-line"
    assert attach["description"] =~ "host"
  end

  test "tool_schemas/1 with explicit tool_groups option overrides env var" do
    System.put_env("CK_TOOL_GROUPS", "core")
    on_exit(fn -> System.delete_env("CK_TOOL_GROUPS") end)

    tools = Protocol.tool_schemas(tool_groups: ["governance"])
    names = Enum.map(tools, & &1["name"])

    assert "ck_finding" in names
    assert "ck_review_submit" in names
    refute "ck_validate" in names
  end

  test "tool_schemas/1 with Application config tool_groups filters when env var is unset" do
    System.delete_env("CK_TOOL_GROUPS")
    Application.put_env(:controlkeel, :mcp, tool_groups: ["git"])
    on_exit(fn -> Application.delete_env(:controlkeel, :mcp) end)

    tools = Protocol.tool_schemas()
    names = Enum.map(tools, & &1["name"])

    assert "ck_git_status" in names
    assert "ck_git_diff" in names
    refute "ck_validate" in names
  end

  test "tool_schemas/1 always exposes the required skill tools even when their group is filtered out" do
    System.delete_env("CK_TOOL_GROUPS")

    # "core" deliberately excludes the "skills" group, but ck_skill_list/load/validate
    # are part of the required CK tool contract advertised by `controlkeel attach`,
    # so adaptive/group filtering must never drop them. Regression: a plain project
    # selected core+governance+git and the declared skill tools went missing.
    tools = Protocol.tool_schemas(tool_groups: ["core"])
    names = Enum.map(tools, & &1["name"])

    assert "ck_skill_list" in names
    assert "ck_skill_load" in names
    assert "ck_skill_validate" in names
    # A non-required tool from an unselected group still gets filtered out.
    refute "ck_git_status" in names
  end

  test "ck_budget schema exposes include_token_overhead and project_root parameters" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list"
      })

    assert %{"result" => %{"tools" => tools}} = response
    budget_tool = Enum.find(tools, &(&1["name"] == "ck_budget"))
    assert budget_tool != nil

    props = get_in(budget_tool, ["inputSchema", "properties"])
    assert Map.has_key?(props, "include_token_overhead")
    assert Map.has_key?(props, "project_root")
    assert props["include_token_overhead"]["type"] == "boolean"
  end

  test "tools/list schemas allow bound-project continuation for context and memory tools" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 2030,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    tools = get_in(response, ["result", "tools"])
    by_name = Map.new(tools, &{&1["name"], &1})

    assert get_in(by_name["ck_context_pack"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_observability"], ["inputSchema", "required"]) == []

    assert get_in(by_name["ck_observability"], ["inputSchema", "properties", "report", "enum"]) ==
             [
               "overview",
               "loop_status",
               "loop_diagnostics",
               "session_run",
               "timeline",
               "memory",
               "memory_quality",
               "recommendations",
               "costs",
               "compare",
               "imports",
               "trends",
               "problems",
               "evals",
               "saved_evals",
               "benchmark_drafts",
               "benchmark_scenarios",
               "benchmark_history",
               "perf_snapshot",
               "promotions",
               "regressions"
             ]

    assert get_in(by_name["ck_experience_index"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_experience_read"], ["inputSchema", "required"]) == ["artifact_type"]
    assert get_in(by_name["ck_trace_packet"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_failure_clusters"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_tool_health"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_skill_evolution"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_fs_ls"], ["inputSchema", "required"]) == []
    assert get_in(by_name["ck_fs_read"], ["inputSchema", "required"]) == ["path"]
    assert get_in(by_name["ck_fs_find"], ["inputSchema", "required"]) == ["query"]
    assert get_in(by_name["ck_fs_grep"], ["inputSchema", "required"]) == ["query"]
    assert get_in(by_name["ck_memory_search"], ["inputSchema", "required"]) == ["query"]
    assert get_in(by_name["ck_memory_record"], ["inputSchema", "required"]) == ["memory"]
    assert get_in(by_name["ck_memory_archive"], ["inputSchema", "required"]) == ["memory_id"]

    for tool_name <- [
          "ck_context_pack",
          "ck_observability",
          "ck_experience_index",
          "ck_experience_read",
          "ck_trace_packet",
          "ck_failure_clusters",
          "ck_tool_health",
          "ck_skill_evolution",
          "ck_fs_ls",
          "ck_fs_read",
          "ck_fs_find",
          "ck_fs_grep",
          "ck_memory_search",
          "ck_memory_record",
          "ck_memory_archive"
        ] do
      assert get_in(by_name[tool_name], ["inputSchema", "properties", "project_root", "type"]) ==
               "string"
    end
  end

  test "tools/call ck_observability returns read-only local reports" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "MCP observability finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.mcp_observability"
    })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2040,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_observability",
          "arguments" => %{
            "report" => "problems",
            "session_id" => session.id,
            "workspace_id" => session.workspace_id
          }
        }
      })

    assert %{"result" => %{"structuredContent" => result}} = response
    assert result.report == "problems"
    assert result.read_only == true
    assert result.mutation == "none"
    assert result.data.count >= 1
  end

  test "tools/call ck_observability exposes canonical loop status without mutation" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Loop status finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.loop_status"
    })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2041,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_observability",
          "arguments" => %{
            "report" => "loop_status",
            "session_id" => session.id,
            "workspace_id" => session.workspace_id
          }
        }
      })

    assert %{"result" => %{"structuredContent" => result}} = response
    assert result.report == "loop_status"
    assert result.read_only == true
    assert result.mutation == "none"
    assert result.data.read_only == true
    assert result.data.learning_loop.automatic_promotion == false
    assert result.data.active_problems.total_findings >= 1
  end

  test "tools/call ck_observability returns benchmark history and promotions reports" do
    session = session_fixture()

    for {report, expected_key} <- [
          {"benchmark_history", :readiness},
          {"promotions", :promotion_execution}
        ] do
      response =
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 2042,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_observability",
            "arguments" => %{
              "report" => report,
              "session_id" => session.id,
              "workspace_id" => session.workspace_id
            }
          }
        })

      assert %{"result" => %{"structuredContent" => result}} = response
      assert result.report == report
      assert result.read_only == true
      assert result.mutation == "none"
      assert Map.has_key?(result.data, expected_key)
    end
  end

  test "tools/call ck_execute_code supports dry run" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 3001,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_execute_code",
          "arguments" => %{
            "code" => "console.log(42)",
            "language" => "javascript",
            "dry_run" => true
          }
        }
      })

    assert %{"result" => %{"structuredContent" => result}} = response
    assert result["dry_run"] == true
    assert result["policy"]["sandbox_required"] == true
  end

  test "tools/call ck_execute_code blocks local sandbox" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 3002,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_execute_code",
          "arguments" => %{
            "code" => "console.log(42)",
            "sandbox" => "local"
          }
        }
      })

    # A policy block is a tool-execution outcome the model should read and recover from,
    # so it now comes back as an MCP isError result (not an opaque -32000 protocol error).
    assert %{"result" => %{"isError" => true, "content" => [%{"text" => message}]}} = response
    assert message =~ "blocked"
  end

  test "resources/list exposes skills as MCP resources" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2010,
        "method" => "resources/list"
      })

    assert %{"result" => %{"resources" => resources}} = response
    assert is_list(resources)
    assert Enum.any?(resources, &String.starts_with?(&1["uri"], "skills://"))

    governance = Enum.find(resources, &(&1["uri"] == "skills://controlkeel-governance"))
    assert governance["mimeType"] == "text/markdown"
    assert is_binary(governance["description"])
  end

  test "resources/list is empty under CK_MCP_MODE to avoid slow Registry scans" do
    prev = System.get_env("CK_MCP_MODE")
    System.put_env("CK_MCP_MODE", "1")

    on_exit(fn ->
      if prev == nil,
        do: System.delete_env("CK_MCP_MODE"),
        else: System.put_env("CK_MCP_MODE", prev)
    end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2012,
        "method" => "resources/list"
      })

    assert %{"result" => %{"resources" => []}} = response
  end

  test "tools/call waits briefly for MCP backend readiness" do
    session = session_fixture()

    original = Application.get_env(:controlkeel, :mcp_boot_gate_wait_ms)
    Application.put_env(:controlkeel, :mcp_boot_gate_wait_ms, 200)

    key = :controlkeel_mcp_backend_ready
    original_status = :persistent_term.get(key, :missing)
    :persistent_term.put(key, :booting)

    parent = self()

    releaser =
      spawn(fn ->
        Process.sleep(50)
        :persistent_term.put(key, :ready)
        send(parent, :boot_released)
      end)

    on_exit(fn ->
      if original do
        Application.put_env(:controlkeel, :mcp_boot_gate_wait_ms, original)
      else
        Application.delete_env(:controlkeel, :mcp_boot_gate_wait_ms)
      end

      case original_status do
        :missing -> :persistent_term.erase(key)
        status -> :persistent_term.put(key, status)
      end

      if Process.alive?(releaser), do: Process.exit(releaser, :kill)
    end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 991,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{"session_id" => session.id}
        }
      })

    assert_receive :boot_released
    assert %{"result" => %{"structuredContent" => payload}} = response
    assert payload["session_id"] == session.id
  end

  test "resources/read returns rendered skill content for a skills uri" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2011,
        "method" => "resources/read",
        "params" => %{"uri" => "skills://controlkeel-governance", "session_id" => 123}
      })

    assert %{"result" => %{"contents" => [content]}} = response
    assert content["uri"] == "skills://controlkeel-governance"
    assert content["mimeType"] == "text/markdown"
    assert content["text"] =~ "<skill_content"
  end

  test "tools/list exposes trust-boundary inputs for ck_validate" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 200,
        "method" => "tools/list"
      })

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_validate"))

    assert get_in(tool, ["inputSchema", "properties", "source_type", "enum"]) != nil

    assert get_in(tool, ["inputSchema", "properties", "trust_level", "enum"]) == [
             "trusted",
             "mixed",
             "untrusted"
           ]

    capability_enum =
      get_in(tool, ["inputSchema", "properties", "requested_capabilities", "items", "enum"])

    assert capability_enum != nil
    assert "file_read" in capability_enum

    assert "preflight" in get_in(tool, [
             "inputSchema",
             "properties",
             "security_workflow_phase",
             "enum"
           ])

    assert "pre_edit" in get_in(tool, [
             "inputSchema",
             "properties",
             "security_workflow_phase",
             "enum"
           ])
  end

  test "tools/list exposes experience archive inputs" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 2001,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    index_tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_experience_index"))

    read_tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_experience_read"))

    assert get_in(index_tool, ["inputSchema", "properties", "same_domain_only", "type"]) ==
             "boolean"

    assert get_in(read_tool, ["inputSchema", "properties", "artifact_type", "enum"]) == [
             "session_summary",
             "audit_log",
             "trace_packet",
             "proof_summary"
           ]
  end

  test "tools/list exposes recursive planning inputs for ck_review_submit" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 201,
        "method" => "tools/list"
      })

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_review_submit"))

    assert get_in(tool, ["inputSchema", "properties", "plan_phase", "enum"]) == [
             "ticket",
             "research_packet",
             "design_options",
             "narrowed_decision",
             "implementation_plan",
             "code_backed_plan"
           ]

    assert get_in(tool, [
             "inputSchema",
             "properties",
             "allowed_semantic_changes",
             "items",
             "type"
           ]) == "string"

    assert get_in(tool, [
             "inputSchema",
             "properties",
             "requires_reapproval_if",
             "items",
             "type"
           ]) == "string"

    assert get_in(tool, [
             "inputSchema",
             "properties",
             "harness_quality_checks",
             "items",
             "type"
           ]) == "string"

    assert get_in(tool, [
             "inputSchema",
             "properties",
             "scope_estimate",
             "properties",
             "architectural_scope",
             "type"
           ]) == "boolean"
  end

  test "tools/list exposes virtual workspace inputs for ck_fs_grep" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 202,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_fs_grep"))

    assert get_in(tool, ["inputSchema", "required"]) == ["query"]

    find_tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_fs_find"))

    assert get_in(find_tool, ["inputSchema", "required"]) == ["query"]
    assert get_in(tool, ["inputSchema", "properties", "fixed_strings", "type"]) == "boolean"
    assert get_in(tool, ["inputSchema", "properties", "ignore_case", "type"]) == "boolean"
  end

  test "tools/list exposes trace packet inputs" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 2022,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_trace_packet"))

    assert get_in(tool, ["inputSchema", "required"]) == []

    assert get_in(tool, ["inputSchema", "properties", "events_limit", "type"]) == [
             "integer",
             "string"
           ]
  end

  test "tools/list exposes failure cluster inputs" do
    response =
      Protocol.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 2024,
          "method" => "tools/list"
        },
        tool_groups: :all
      )

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_failure_clusters"))

    assert get_in(tool, ["inputSchema", "required"]) == []
    assert get_in(tool, ["inputSchema", "properties", "same_domain_only", "type"]) == "boolean"
  end

  test "tools/list constrains ck_skill_load names to the bound project catalog" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-protocol-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, ".agents/skills/project-skill"))

    File.write!(
      Path.join(tmp_dir, ".agents/skills/project-skill/SKILL.md"),
      """
      ---
      name: project-skill
      description: Project local operator skill.
      ---

      # Project skill
      """
    )

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => 1,
          "session_id" => 1,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        tmp_dir
      )

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(
          %{
            "jsonrpc" => "2.0",
            "id" => 32,
            "method" => "tools/list"
          },
          tool_groups: :all
        )
      end)

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_skill_load"))

    assert "project-skill" in get_in(tool, ["inputSchema", "properties", "name", "enum"])
  end

  test "tools/call ck_validate returns normalized validation output" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_validate",
          "arguments" => %{
            "content" =>
              ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
            "path" => "user_query.js",
            "kind" => "code"
          }
        }
      })

    assert %{
             "result" => %{
               "content" => [%{"type" => "text", "text" => content}],
               "structuredContent" => %{
                 "allowed" => false,
                 "decision" => "block",
                 "findings" => findings,
                 "summary" => summary,
                 "scanned_at" => scanned_at
               }
             }
           } = response

    assert content =~ "Structured result returned in structuredContent"
    refute String.starts_with?(String.trim(content), "{")
    assert is_list(findings)
    assert Enum.any?(findings, &(&1["rule_id"] == "security.sql_injection"))
    assert summary =~ "Blocked"
    assert scanned_at =~ "T"
  end

  test "tools/call virtual workspace tools browse the bound project root" do
    session = session_fixture()

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-vfs-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "docs"))
    File.write!(Path.join(tmp_dir, "README.md"), "# Trial\n\nOAuth lives here.\n")
    File.write!(Path.join(tmp_dir, "docs/guide.md"), "Guide\n\nOAuth config lives here too.\n")

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        tmp_dir
      )

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    ls_response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 203,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_fs_ls",
            "arguments" => %{"path" => "."}
          }
        })
      end)

    assert get_in(ls_response, ["result", "structuredContent", "tool"]) == "ls"

    assert Enum.any?(
             get_in(ls_response, ["result", "structuredContent", "entries"]),
             &(&1["path"] == "README.md")
           )

    read_response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 204,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_fs_read",
            "arguments" => %{"path" => "README.md"}
          }
        })
      end)

    assert get_in(read_response, ["result", "structuredContent", "tool"]) == "cat"

    assert get_in(read_response, ["result", "structuredContent", "content"]) =~
             "OAuth lives here."

    grep_response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 205,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_fs_grep",
            "arguments" => %{"query" => "OAuth"}
          }
        })
      end)

    assert get_in(grep_response, ["result", "structuredContent", "tool"]) == "grep"
    assert get_in(grep_response, ["result", "structuredContent", "count"]) >= 2

    find_response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 206,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_fs_find",
            "arguments" => %{"query" => "guide"}
          }
        })
      end)

    assert get_in(find_response, ["result", "structuredContent", "tool"]) == "find"

    assert Enum.any?(
             get_in(find_response, ["result", "structuredContent", "matches"]),
             &(&1["path"] == "docs/guide.md")
           )
  end

  test "tools/call virtual workspace tools reject path escapes" do
    session = session_fixture()

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-vfs-escape-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "README.md"), "# Trial\n")

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        tmp_dir
      )

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    response =
      File.cd!(tmp_dir, fn ->
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 207,
          "method" => "tools/call",
          "params" => %{
            "name" => "ck_fs_read",
            "arguments" => %{"session_id" => session.id, "path" => "../README.md"}
          }
        })
      end)

    assert get_in(response, ["error", "code"]) == -32602
    assert get_in(response, ["error", "message"]) =~ "Path escapes the bound project root"
  end

  test "tools/call ck_validate accepts a direct domain pack override" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 31,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_validate",
          "arguments" => %{
            "content" => "def rank(candidate), do: reject(candidate.age > 50)",
            "path" => "lib/hr/ranker.ex",
            "kind" => "code",
            "domain_pack" => "hr"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "decision"]) == "block"

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "findings"]),
             &(&1["rule_id"] == "hr.discriminatory_criteria")
           )
  end

  test "tools/call ck_context ignores non-numeric task slugs" do
    session = session_fixture()

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 404,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => "amp-neo-integration"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "session_id"]) == session.id
    refute Map.has_key?(response, "error")
  end

  test "tools/call ck_context_pack ignores non-numeric task slugs" do
    session = session_fixture()
    _task = task_fixture(%{session: session, status: "in_progress", title: "Active work"})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 405,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context_pack",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => "amp-neo-integration",
            "top_k" => 1
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "session_id"]) == session.id
    refute Map.has_key?(response, "error")
  end

  test "tools/call ck_context returns mission context" do
    session =
      session_fixture(%{
        budget_cents: 1_500,
        daily_budget_cents: 500,
        spent_cents: 250,
        execution_brief:
          execution_brief_fixture(
            compiler: %{"interview_answers" => %{"constraints" => "Approval before deploy"}}
          )
          |> ControlKeel.Intent.to_brief_map()
      })

    session_id = session.id
    task = task_fixture(%{session: session, status: "in_progress", title: "Implement router"})

    finding_fixture(%{
      session: session,
      status: "blocked",
      category: "security",
      metadata: %{
        "finding_family" => "vulnerability_case",
        "affected_component" => "router",
        "evidence_type" => "source",
        "exploitability_status" => "reproduced",
        "patch_status" => "drafted",
        "disclosure_status" => "triaged",
        "maintainer_scope" => "first_party",
        "cwe_ids" => ["CWE-601"]
      }
    })

    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{"session_id" => session.id}
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "session_id" => ^session_id,
                 "session_title" => _,
                 "risk_tier" => _,
                 "compliance_profile" => _,
                 "active_findings" => %{"count" => 1, "blocked" => 1},
                 "security_case_summary" => %{
                   "case_count" => 1,
                   "unresolved" => 1,
                   "patch_status" => %{"drafted" => 1},
                   "disclosure_status" => %{"triaged" => 1}
                 },
                 "autonomy_profile" => %{"mode" => autonomy_mode},
                 "outcome_profile" => %{"goal_type" => goal_type},
                 "improvement_loop" => %{
                   "loop" => ["run", "observe", "evaluate", "improve", "rerun"]
                 },
                 "budget_summary" => %{
                   "spent_cents" => 250,
                   "session_budget_cents" => 1_500,
                   "daily_budget_cents" => 500
                 },
                 "boundary_summary" => %{
                   "risk_tier" => "critical",
                   "constraints" => ["Approval before deploy"]
                 },
                 "current_task" => %{"title" => "Implement router"},
                 "proof_summary" => %{"task_id" => _},
                 "planning_context" => %{"review_gate" => %{}},
                 "task_augmentation" => %{
                   "available" => true,
                   "augmented_brief" => augmented_brief,
                   "search_terms" => search_terms
                 },
                 "memory_hits" => memory_hits,
                 "resume_packet" => %{"task_id" => _, "workspace_context" => %{}},
                 "workspace_context" => %{
                   "cache_key" => workspace_cache_key,
                   "orientation" => %{"recent_commits" => recent_commits},
                   "design_drift" => %{"summary" => design_drift_summary}
                 },
                 "workspace_cache_key" => workspace_cache_key,
                 "context_reacquisition" => %{
                   "recent_commits" => reacquisition_commits,
                   "active_assumptions" => active_assumptions,
                   "design_drift_summary" => design_drift_summary,
                   "high_risk_design_drift" => high_risk_design_drift
                 },
                 "instruction_hierarchy" => %{
                   "trusted_sources" => %{"authority" => trusted_sources},
                   "untrusted_sources" => %{"authority" => untrusted_sources}
                 },
                 "recent_events" => recent_events,
                 "transcript_summary" => %{"total_events" => total_events}
               }
             }
           } = response

    payload = get_in(response, ["result", "structuredContent"])
    assert payload["detail_level"] == "compact"
    assert payload["detail_hint"] =~ "detail_level: full"

    full_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 41,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{"session_id" => session.id, "detail_level" => "full"}
        }
      })

    assert get_in(full_response, ["result", "structuredContent", "detail_level"]) == "full"
    refute Map.has_key?(get_in(full_response, ["result", "structuredContent"]), "detail_hint")

    assert is_list(memory_hits)
    assert is_binary(augmented_brief)
    assert is_list(search_terms)
    assert autonomy_mode in ["supervised_execute", "guarded_autonomy", "long_running_autonomy"]
    assert goal_type in ["delivery", "kpi"]
    assert is_list(recent_events)
    assert total_events >= 1
    assert is_list(recent_commits)
    assert is_list(reacquisition_commits)
    assert is_list(active_assumptions)
    assert is_boolean(high_risk_design_drift)
    assert is_binary(design_drift_summary)
    assert "controlkeel" in trusted_sources
    assert "issue" in untrusted_sources
  end

  test "tools/call ck_context prefers governed runtime project root over caller cwd" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-ck-context-#{System.unique_integer([:positive])}")

    project_root = Path.join(tmp_dir, "project")
    other_root = Path.join(tmp_dir, "other")
    File.mkdir_p!(project_root)
    File.mkdir_p!(other_root)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    session = session_fixture()
    task_fixture(%{session: session, status: "in_progress"})

    assert {:ok, _session} =
             Mission.attach_session_runtime_context(session.id, %{"project_root" => project_root})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 401,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{"session_id" => session.id, "project_root" => other_root}
        }
      })

    assert get_in(response, ["result", "structuredContent", "project_root"]) == project_root
    assert get_in(response, ["result", "structuredContent", "provider_status", "source"]) != nil
  end

  test "tools/call ck_context_pack returns a factual context bundle with citations" do
    session =
      session_fixture(%{
        budget_cents: 1_500,
        daily_budget_cents: 500,
        spent_cents: 250,
        execution_brief:
          execution_brief_fixture(
            compiler: %{"interview_answers" => %{"constraints" => "Approval before deploy"}}
          )
          |> ControlKeel.Intent.to_brief_map()
      })

    task = task_fixture(%{session: session, status: "in_progress", title: "Implement router"})

    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    record_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 901,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_record",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "memory" => "Router rollout needs approval evidence and explicit route constraints.",
            "record_type" => "decision",
            "tags" => ["router", "approval"]
          }
        }
      })

    memory_id = get_in(record_response, ["result", "structuredContent", "memory_id"])
    assert is_integer(memory_id)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 902,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context_pack",
          "arguments" => %{"session_id" => session.id, "task_id" => task.id, "top_k" => 3}
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "session_id" => session_id,
                 "task_id" => response_task_id,
                 "query" => query,
                 "factual_only" => true,
                 "context_pack" => %{
                   "task" => %{"title" => "Implement router"},
                   "proof" => %{"proof_id" => proof_id},
                   "resume" => %{"task_status" => "in_progress"},
                   "memory" => memory_rows,
                   "citations" => citations
                 }
               }
             }
           } = response

    assert session_id == session.id
    assert response_task_id == task.id
    assert is_integer(proof_id)
    assert is_binary(query)
    assert Enum.any?(memory_rows, &(&1["id"] == memory_id))
    assert Enum.any?(citations, &(&1["kind"] == "proof"))
    assert Enum.any?(citations, &(&1["kind"] == "resume_packet"))
    assert Enum.any?(citations, &(&1["kind"] == "memory" and &1["memory_id"] == memory_id))
  end

  test "tools/call carries continuity across controlled host binding changes" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-protocol-portability-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture(%{budget_cents: 1_500, daily_budget_cents: 1_000, spent_cents: 100})
    task = task_fixture(%{session: session, status: "in_progress", title: "Portable task"})

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "opencode",
                 "attached_agents" => %{"opencode" => %{"scope" => "project"}}
               },
               tmp_dir
             )

    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)
    assert {:ok, pause_result} = Mission.pause_task(task.id, "test-host-a")
    assert pause_result.resume_packet["task_id"] == task.id
    assert {:ok, resume_result} = Mission.resume_task(task.id, "test-host-b")
    assert resume_result.resume_packet["session_id"] == session.id

    review_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 903,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "review_type" => "plan",
            "plan_phase" => "implementation_plan",
            "submission_body" => "Validate portable continuation across host bindings.",
            "submitted_by" => "test-host-a"
          }
        }
      })

    assert get_in(review_response, ["result", "structuredContent", "status"]) in [
             "pending",
             "approved"
           ]

    memory_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 904,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_record",
          "arguments" => %{
            "project_root" => tmp_dir,
            "task_id" => task.id,
            "memory" => "Portable continuity checkpoint from host A.",
            "record_type" => "checkpoint"
          }
        }
      })

    memory_id = get_in(memory_response, ["result", "structuredContent", "memory_id"])
    assert is_integer(memory_id)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "codex-cli",
                 "attached_agents" => %{"codex-cli" => %{"scope" => "project"}}
               },
               tmp_dir
             )

    context_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 905,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context",
          "arguments" => %{"session_id" => "current", "project_root" => tmp_dir}
        }
      })

    context = get_in(context_response, ["result", "structuredContent"])
    assert context["session_id"] == session.id
    assert context["current_task"]["id"] == task.id
    assert context["proof_summary"]["task_id"] == task.id
    assert context["resume_packet"]["task_id"] == task.id
    assert context["budget_summary"]["session_budget_cents"] == 1_500
    assert get_in(context, ["planning_context", "review_gate", "latest_review_id"])

    pack_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 906,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_context_pack",
          "arguments" => %{
            "project_root" => tmp_dir,
            "query" => "portable continuity checkpoint",
            "top_k" => 5
          }
        }
      })

    pack = get_in(pack_response, ["result", "structuredContent", "context_pack"])
    assert Enum.any?(pack["memory"], &(&1["id"] == memory_id))
    assert Enum.any?(pack["citations"], &(&1["kind"] == "proof"))
    assert Enum.any?(pack["citations"], &(&1["kind"] == "resume_packet"))

    budget_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 907,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_budget",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "mode" => "estimate",
            "estimated_cost_cents" => 1,
            "tool" => "portability-test"
          }
        }
      })

    assert get_in(budget_response, ["result", "structuredContent", "recorded"]) == false
    assert get_in(budget_response, ["result", "structuredContent", "estimated_cost_cents"]) >= 0
  end

  test "tools/call ck_review_submit returns plan refinement quality" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "task_id" => task.id,
            "review_type" => "plan",
            "plan_phase" => "implementation_plan",
            "research_summary" => "Reviewed existing Mission review gates and proof bundles.",
            "codebase_findings" => ["Plan metadata can extend current review storage."],
            "alignment_context" => [
              "PM wants non-code alignment context to travel with the review packet."
            ],
            "options_considered" => ["Extend review metadata", "Create planner subsystem"],
            "selected_option" => "Extend review metadata",
            "rejected_options" => ["Create planner subsystem"],
            "implementation_steps" => [
              "Normalize plan refinement",
              "Check plan continuity in proof bundles"
            ],
            "validation_plan" => ["mix test", "mix precommit"],
            "agent_spec_id" => "code reviewer v1",
            "task_spec_id" => "plan review v1",
            "agent_role" => "code reviewer",
            "task_scope" => "Review implementation plans before execution",
            "allowed_actions" => ["submit_review"],
            "prohibited_actions" => ["bypass_review_gate"],
            "robustness_requirements" => ["paraphrases"],
            "promotion_gates" => ["held-out benchmark evidence passes"],
            "allowed_semantic_changes" => ["Extend review metadata"],
            "forbidden_semantic_changes" => ["Change execution gating"],
            "invariant_boundaries" => ["Review approval remains required"],
            "requires_reapproval_if" => ["Planner semantics change"],
            "harness_quality_checks" => ["Proof metadata is preserved"],
            "submission_body" => "Recursive implementation plan"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "plan_phase"]) ==
             "implementation_plan"

    assert get_in(response, ["result", "structuredContent", "plan_quality", "ready"]) == true

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "alignment_context"
           ]) !=
             []

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "agent_spec_id"
           ]) == "code reviewer v1"

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "task_spec_id"
           ]) == "plan review v1"

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "allowed_actions"
           ]) == ["submit_review"]

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "allowed_semantic_changes"
           ]) == ["Extend review metadata"]

    assert get_in(response, [
             "result",
             "structuredContent",
             "plan_refinement",
             "requires_reapproval_if"
           ]) == ["Planner semantics change"]

    assert is_list(get_in(response, ["result", "structuredContent", "grill_questions"]))
  end

  test "tools/call ck_trace_packet returns failure patterns and eval candidates" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done"})

    _finding =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task.id}
      })

    assert {:ok, _invocation} =
             Mission.record_regression_result(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "engine" => "passmark",
               "flow_name" => "checkout flow",
               "outcome" => "failed",
               "summary" => "Checkout never completes",
               "external_run_id" => "run-123"
             })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2023,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_trace_packet",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "events_limit" => 10
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "trace_summary", "findings"]) == 1

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "failure_patterns"]),
             &(&1["code"] == "security.sql_injection")
           )

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "eval_candidates"]),
             &(&1["suggested_check_type"] in ["deterministic_rule", "regression_replay"])
           )
  end

  test "tools/call ck_trace_packet resolves the active bound session from project_root" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done"})

    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-trace-packet-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "codex",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_301,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_trace_packet",
          "arguments" => %{
            "project_root" => tmp_dir,
            "task_id" => task.id,
            "events_limit" => 5
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "session_id"]) == session.id
  end

  test "tools/call ck_experience_index lists prior-run artifacts" do
    workspace = workspace_fixture()

    session_a =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    session_b =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    _task_a = task_fixture(%{session: session_a, status: "done"})
    _task_b = task_fixture(%{session: session_b, status: "done"})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 20231,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_experience_index",
          "arguments" => %{
            "session_id" => session_a.id,
            "session_limit" => 5
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "sessions_analyzed"]) == 2

    entry =
      get_in(response, ["result", "structuredContent", "sessions"])
      |> Enum.find(&(&1["session_id"] == session_a.id))

    assert Enum.any?(entry["artifacts"], &(&1["artifact_type"] == "session_summary"))
    assert Enum.any?(entry["artifacts"], &(&1["artifact_type"] == "audit_log"))
  end

  test "tools/call ck_experience_index resolves the active bound session from project_root" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-experience-index-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => workspace.id,
                 "session_id" => session.id,
                 "agent" => "codex",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_311,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_experience_index",
          "arguments" => %{
            "project_root" => tmp_dir,
            "session_limit" => 1
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "source_session_id"]) == session.id
  end

  test "tools/call ck_experience_read returns a prior trace packet" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task = task_fixture(%{session: session, status: "done"})

    _finding =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task.id}
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 20232,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_experience_read",
          "arguments" => %{
            "session_id" => session.id,
            "source_session_id" => session.id,
            "task_id" => task.id,
            "artifact_type" => "trace_packet"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "artifact_type"]) == "trace_packet"

    assert get_in(response, ["result", "structuredContent", "structured_content", "task_id"]) ==
             task.id

    assert Enum.any?(
             get_in(response, [
               "result",
               "structuredContent",
               "structured_content",
               "failure_patterns"
             ]),
             &(&1["code"] == "security.sql_injection")
           )
  end

  test "tools/call ck_experience_read resolves the active bound session from project_root" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task = task_fixture(%{session: session, status: "done"})

    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-experience-read-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => workspace.id,
                 "session_id" => session.id,
                 "agent" => "codex",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_321,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_experience_read",
          "arguments" => %{
            "project_root" => tmp_dir,
            "source_session_id" => session.id,
            "task_id" => task.id,
            "artifact_type" => "trace_packet"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "source_session_id"]) == session.id
    assert get_in(response, ["result", "structuredContent", "target_session_id"]) == session.id
  end

  test "tools/call ck_failure_clusters groups recurring failure modes across recent sessions" do
    workspace = workspace_fixture()

    session_a =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    session_b =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task_a = task_fixture(%{session: session_a, status: "done"})
    task_b = task_fixture(%{session: session_b, status: "done"})

    _finding_a =
      finding_fixture(%{
        session: session_a,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task_a.id}
      })

    _finding_b =
      finding_fixture(%{
        session: session_b,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected again.",
        metadata: %{"task_id" => task_b.id}
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2025,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_failure_clusters",
          "arguments" => %{
            "session_id" => session_a.id,
            "session_limit" => 5
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "cluster_count"]) >= 1

    sql_cluster =
      get_in(response, ["result", "structuredContent", "clusters"])
      |> Enum.find(&(&1["code"] == "security.sql_injection"))

    assert sql_cluster["count"] == 2
    assert sql_cluster["session_count"] == 2

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "eval_candidates"]),
             &(&1["cluster_code"] == "security.sql_injection")
           )
  end

  test "tools/call ck_failure_clusters resolves the active bound session from project_root" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    _task = task_fixture(%{session: session, status: "done"})

    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-failure-clusters-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => workspace.id,
                 "session_id" => session.id,
                 "agent" => "codex",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_510,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_failure_clusters",
          "arguments" => %{
            "project_root" => tmp_dir,
            "session_limit" => 1
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "source_session_id"]) == session.id
  end

  test "tools/call ck_skill_evolution returns a consolidated skill draft from traces" do
    workspace = workspace_fixture()

    session_a =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    session_b =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task_a = task_fixture(%{session: session_a, status: "done"})
    task_b = task_fixture(%{session: session_b, status: "done"})

    _finding_a =
      finding_fixture(%{
        session: session_a,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task_a.id}
      })

    _finding_b =
      finding_fixture(%{
        session: session_b,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected again.",
        metadata: %{"task_id" => task_b.id}
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2026,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session_a.id,
            "session_limit" => 5,
            "current_skill_name" => "secure-sql-review",
            "current_skill_content" => """
            ## Avoid
            - Avoid raw SQL concatenation and other string-built query paths.
            """
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "sessions_analyzed"]) == 2

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "anti_patterns"]),
             &(&1["code"] == "security.sql_injection")
           )

    refute Enum.any?(
             get_in(response, ["result", "structuredContent", "guidance", "avoid"]),
             &String.contains?(&1, "raw SQL concatenation")
           )

    assert get_in(response, ["result", "structuredContent", "suggested_skill_document"]) =~
             "name: secure-sql-review"
  end

  test "tools/call ck_skill_evolution resolves the active bound session from project_root" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    _task = task_fixture(%{session: session, status: "done"})

    tmp_dir =
      Path.join(System.tmp_dir!(), "ck-skill-evolution-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => workspace.id,
                 "session_id" => session.id,
                 "agent" => "codex",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_610,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "project_root" => tmp_dir,
            "session_limit" => 1,
            "current_skill_name" => "trace-evolved-skill"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "source_session_id"]) == session.id
  end

  test "tools/call ck_skill_evolution validate_only returns a Self-Harness verdict" do
    workspace = workspace_fixture()

    session_a =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    session_b =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task_a = task_fixture(%{session: session_a, status: "done"})
    task_b = task_fixture(%{session: session_b, status: "done"})

    _finding_a =
      finding_fixture(%{
        session: session_a,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task_a.id}
      })

    _finding_b =
      finding_fixture(%{
        session: session_b,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected again.",
        metadata: %{"task_id" => task_b.id}
      })

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-skill-evolution-validate-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_611,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session_a.id,
            "session_limit" => 5,
            "validate_only" => true,
            "current_skill_name" => "secure-sql-review",
            "project_root" => tmp_dir
          }
        }
      })

    verdict = get_in(response, ["result", "structuredContent"])

    assert Map.has_key?(verdict, "accepted")
    assert Map.has_key?(verdict["checks"], "static")
    assert Map.has_key?(verdict["checks"], "held_in")
    assert Map.has_key?(verdict["checks"], "held_out")
    assert Map.has_key?(verdict["checks"], "regression")
    assert is_integer(verdict["held_in_cluster_count"])
    assert is_integer(verdict["held_out_cluster_count"])
    # No file should be written in validate-only mode.
    refute File.exists?(
             Path.join([tmp_dir, ".agents", "skills", "secure-sql-review", "SKILL.md"])
           )
  end

  test "tools/call ck_skill_evolution regression check fails when catch rate drops below baseline" do
    workspace = workspace_fixture()

    # No domain_pack: the full vibe_failures_v1 suite runs, where the
    # deterministic `controlkeel_validate` subject scores below 100%.
    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{}
      })

    task = task_fixture(%{session: session, status: "done"})

    _finding =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task.id}
      })

    # Seed a completed baseline run with a catch rate above what the
    # deterministic subject achieves on the full suite, so the new run
    # registers as a regression.
    suite = ControlKeel.Benchmark.get_suite_by_slug("vibe_failures_v1")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    baseline =
      %ControlKeel.Benchmark.Run{}
      |> ControlKeel.Benchmark.Run.changeset(%{
        suite_id: suite.id,
        status: "completed",
        baseline_subject: "controlkeel_validate",
        subjects: ["controlkeel_validate"],
        started_at: now,
        finished_at: now,
        total_scenarios: 10,
        caught_count: 10,
        blocked_count: 10,
        catch_rate: 100.0
      })
      |> Repo.insert!()

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-skill-evolution-regression-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_612,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session.id,
            "session_limit" => 5,
            "validate_only" => true,
            "current_skill_name" => "secure-sql-review",
            "project_root" => tmp_dir
          }
        }
      })

    verdict = get_in(response, ["result", "structuredContent"])
    regression = verdict["checks"]["regression"]

    assert regression["passed"] == false
    assert regression["baseline_catch_rate"] == 100.0
    assert is_number(regression["catch_rate"])
    assert regression["catch_rate"] < 100.0
    assert regression["run_id"] != baseline.id
    assert verdict["accepted"] == false
    assert Enum.any?(verdict["notes"], &String.contains?(&1, "dropped below baseline"))
  end

  test "tools/call ck_skill_evolution regression check passes against an equal-or-lower baseline" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task = task_fixture(%{session: session, status: "done"})

    _finding =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task.id}
      })

    suite = ControlKeel.Benchmark.get_suite_by_slug("vibe_failures_v1")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    _baseline =
      %ControlKeel.Benchmark.Run{}
      |> ControlKeel.Benchmark.Run.changeset(%{
        suite_id: suite.id,
        status: "completed",
        baseline_subject: "controlkeel_validate",
        subjects: ["controlkeel_validate"],
        started_at: now,
        finished_at: now,
        total_scenarios: 10,
        caught_count: 0,
        blocked_count: 0,
        catch_rate: 0.0
      })
      |> Repo.insert!()

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-skill-evolution-regression-pass-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_613,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session.id,
            "session_limit" => 5,
            "validate_only" => true,
            "current_skill_name" => "secure-sql-review",
            "project_root" => tmp_dir
          }
        }
      })

    verdict = get_in(response, ["result", "structuredContent"])
    regression = verdict["checks"]["regression"]

    assert regression["passed"] == true
    assert regression["baseline_catch_rate"] == 0.0
    assert regression["catch_rate"] >= 0.0
  end

  test "tools/call ck_skill_evolution install writes the skill only when validation passes" do
    workspace = workspace_fixture()

    session_a =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    session_b =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    task_a = task_fixture(%{session: session_a, status: "done"})
    task_b = task_fixture(%{session: session_b, status: "done"})

    _finding_a =
      finding_fixture(%{
        session: session_a,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => task_a.id}
      })

    _finding_b =
      finding_fixture(%{
        session: session_b,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected again.",
        metadata: %{"task_id" => task_b.id}
      })

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-skill-evolution-install-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_612,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session_a.id,
            "session_limit" => 5,
            "install" => true,
            "current_skill_name" => "secure-sql-review",
            "project_root" => tmp_dir
          }
        }
      })

    result = get_in(response, ["result", "structuredContent"])

    skill_path = Path.join([tmp_dir, ".agents", "skills", "secure-sql-review", "SKILL.md"])

    if result["applied"] do
      assert File.exists?(skill_path)
      assert result["validation"]["accepted"] == true
      assert result["path"] == skill_path
    else
      # If validation rejected the edit, no file should be written and an error
      # should be surfaced rather than a partial write.
      refute File.exists?(skill_path)
      assert get_in(response, ["error"]) != nil or result["validation"]["accepted"] == false
    end
  end

  test "tools/call ck_skill_evolution install preserves previous skill as .bak" do
    workspace = workspace_fixture()

    session =
      session_fixture(%{
        workspace: workspace,
        execution_brief: %{"domain_pack" => "software"}
      })

    _task = task_fixture(%{session: session, status: "done"})

    _finding =
      finding_fixture(%{
        session: session,
        status: "blocked",
        rule_id: "security.sql_injection",
        title: "SQL injection risk",
        plain_message: "Unsafe SQL concatenation was detected.",
        metadata: %{"task_id" => session.id}
      })

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-skill-evolution-backup-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    skill_dir = Path.join([tmp_dir, ".agents", "skills", "secure-sql-review"])
    File.mkdir_p!(skill_dir)

    original_path = Path.join(skill_dir, "SKILL.md")
    original_content = "---\nname: secure-sql-review\ndescription: Old version.\n---\n# Old\n"
    File.write!(original_path, original_content)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202_613,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_evolution",
          "arguments" => %{
            "session_id" => session.id,
            "session_limit" => 1,
            "install" => true,
            "current_skill_name" => "secure-sql-review",
            "project_root" => tmp_dir
          }
        }
      })

    result = get_in(response, ["result", "structuredContent"])

    if result["applied"] do
      assert File.exists?(original_path)
      assert result["backup_path"] != nil
      assert File.exists?(result["backup_path"])
      assert File.read!(result["backup_path"]) == original_content
      # New content should differ from the original.
      refute File.read!(original_path) == original_content
    end
  end

  test "tools/call ck_review_submit returns grill questions for weak planning packets" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued"})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2021,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "task_id" => task.id,
            "review_type" => "plan",
            "plan_phase" => "design_options",
            "submission_body" => "Rough draft only"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "plan_quality", "status"]) in [
             "weak",
             "moderate"
           ]

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "grill_questions"]),
             &String.contains?(&1, "viable approaches")
           )
  end

  test "tools/call ck_finding persists a governed finding" do
    session = session_fixture()

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_finding",
          "arguments" => %{
            "session_id" => session.id,
            "category" => "security",
            "severity" => "high",
            "rule_id" => "security.review.required",
            "plain_message" => "Manual approval is required before rollout.",
            "decision" => "escalate_to_human"
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "finding_id" => finding_id,
                 "status" => "escalated",
                 "requires_human" => true
               }
             }
           } = response

    assert Mission.get_finding!(finding_id).status == "escalated"
  end

  test "tools/call ck_finding with allow auto-resolves matching unresolved findings" do
    session = session_fixture()

    blocked_one =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "critical",
        rule_id: "security.workflow.live_target_ambiguity",
        status: "blocked"
      })

    blocked_two =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "critical",
        rule_id: "security.workflow.live_target_ambiguity",
        status: "blocked"
      })

    escalated_same_rule =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "critical",
        rule_id: "security.workflow.live_target_ambiguity",
        status: "escalated"
      })

    _different_rule =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "critical",
        rule_id: "security.workflow.access_mode_reproduction",
        status: "blocked"
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 205,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_finding",
          "arguments" => %{
            "session_id" => session.id,
            "category" => "security",
            "severity" => "critical",
            "rule_id" => "security.workflow.live_target_ambiguity",
            "plain_message" => "No live-target repro was executed in this task.",
            "decision" => "allow"
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "finding_id" => finding_id,
                 "status" => "approved",
                 "requires_human" => false,
                 "resolved_findings_count" => 2,
                 "resolved_finding_ids" => resolved_ids
               }
             }
           } = response

    assert Enum.sort(resolved_ids) == Enum.sort([blocked_one.id, blocked_two.id])
    refute escalated_same_rule.id in resolved_ids
    assert Mission.get_finding!(blocked_one.id).status == "approved"
    assert Mission.get_finding!(blocked_two.id).status == "approved"
    assert Mission.get_finding!(escalated_same_rule.id).status == "escalated"
    assert Mission.get_finding!(finding_id).status == "approved"
  end

  test "tools/call ck_finding mode=resolve disposes a single finding by id" do
    session = session_fixture()

    blocked =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "high",
        rule_id: "security.workflow.single_resolve",
        status: "blocked"
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 210,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_finding",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "resolve",
            "finding_id" => blocked.id
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "mode" => "resolve",
                 "finding_id" => fid,
                 "status" => "approved",
                 "disposed_count" => 1
               }
             }
           } = response

    assert fid == blocked.id
    assert Mission.get_finding!(blocked.id).status == "approved"
  end

  test "tools/call ck_finding mode=dismiss bulk-disposes active findings by status filter" do
    session = session_fixture()

    one =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "high",
        rule_id: "security.workflow.stale_one",
        status: "blocked"
      })

    two =
      finding_fixture(%{
        session: session,
        category: "security",
        severity: "medium",
        rule_id: "security.workflow.stale_two",
        status: "blocked"
      })

    open_one =
      finding_fixture(%{
        session: session,
        category: "quality",
        severity: "low",
        rule_id: "quality.style.spacing",
        status: "open"
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 211,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_finding",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "dismiss",
            "status" => "blocked",
            "reason" => "stale: pre-governance run"
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "mode" => "dismiss",
                 "disposed_count" => 2,
                 "disposed_finding_ids" => ids
               }
             }
           } = response

    assert Enum.sort(ids) == Enum.sort([one.id, two.id])
    assert Mission.get_finding!(one.id).status == "rejected"
    assert Mission.get_finding!(two.id).status == "rejected"
    # finding in a different status is left untouched by the status-scoped filter
    assert Mission.get_finding!(open_one.id).status == "open"
  end

  test "tools/call keeps ck_execute_code outcomes inside result instead of protocol error" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 777,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_execute_code",
          "arguments" => %{
            "code" => "console.log(1)",
            "language" => "javascript",
            "sandbox" => "docker",
            "dry_run" => false
          }
        }
      })

    refute Map.has_key?(response, "error")

    case response do
      %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} ->
        assert is_binary(text)

      %{"result" => %{"structuredContent" => %{"exit_status" => _}}} ->
        :ok

      other ->
        flunk("unexpected tools/call response: #{inspect(other)}")
    end
  end

  test "tools/call ck_regression_result records external regression evidence" do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done"})

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 206,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_regression_result",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "engine" => "bug0",
            "flow_name" => "login flow",
            "outcome" => "failed",
            "summary" => "SSO redirect never returns",
            "external_run_id" => "run-123",
            "evidence" => %{"video_url" => "https://example.test/login.mp4"}
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "recorded" => true,
                 "session_id" => session_id,
                 "task_id" => task_id,
                 "engine" => "bug0",
                 "flow_name" => "login flow",
                 "outcome" => "failed"
               }
             }
           } = response

    assert session_id == session.id
    assert task_id == task.id

    assert {:ok, bundle} = Mission.proof_bundle(task.id)
    assert bundle["test_outcomes"]["engines"]["bug0"] == 1
    assert bundle["deploy_ready"] == false
  end

  test "tools/call ck_memory_record and ck_memory_search expose explicit typed memory" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    record_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 207,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_record",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "memory" => "Prefer explicit decision records before major API changes.",
            "record_type" => "decision",
            "tags" => ["architecture", "decision"]
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "recorded" => true,
                 "memory_id" => memory_id,
                 "record_type" => "decision"
               }
             }
           } = record_response

    search_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 208,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_search",
          "arguments" => %{
            "session_id" => session.id,
            "query" => "major API changes",
            "record_type" => "decision",
            "top_k" => 3
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "count" => count,
                 "records" => records,
                 "semantic_available" => semantic_available
               }
             }
           } = search_response

    assert count >= 1
    assert semantic_available in [true, false]
    assert Enum.any?(records, &(&1["id"] == memory_id))
  end

  test "tools/call ck_memory_record accepts object-shaped memory payloads" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    record_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2071,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_record",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "memory" => %{
              "content" => "Carry session continuity decisions across runtimes.",
              "record_type" => "decision",
              "tags" => ["continuity", "memory"],
              "metadata" => %{"origin" => "compat-test"}
            }
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "recorded" => true,
                 "record_type" => "decision"
               }
             }
           } = record_response

    search_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2072,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_search",
          "arguments" => %{
            "session_id" => session.id,
            "query" => "continuity decisions",
            "record_type" => "decision",
            "top_k" => 3
          }
        }
      })

    records = get_in(search_response, ["result", "structuredContent", "records"])

    assert Enum.any?(records, fn record ->
             [record["body"], record["summary"], record["title"]]
             |> Enum.filter(&is_binary/1)
             |> Enum.any?(&String.contains?(&1, "Carry session continuity decisions"))
           end)
  end

  test "tools/call ck_goal records, lists, and updates persistent governed goals" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    record_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2081,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_goal",
          "arguments" => %{
            "session_id" => session.id,
            "task_id" => task.id,
            "mode" => "record",
            "goal" => "Keep governed MCP context explicit and citable.",
            "horizon" => "task",
            "tags" => ["context", "memory"]
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "recorded" => true,
                 "goal_id" => goal_id,
                 "status" => "active",
                 "horizon" => "task"
               }
             }
           } = record_response

    list_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2082,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_goal",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "list",
            "status" => "active"
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "count" => active_count,
                 "goals" => goals
               }
             }
           } = list_response

    assert active_count >= 1
    assert Enum.any?(goals, &(&1["id"] == goal_id and &1["status"] == "active"))

    update_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2083,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_goal",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "update_status",
            "goal_id" => goal_id,
            "status" => "completed",
            "progress_note" => "Added the explicit goal surface."
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "updated" => true,
                 "goal_id" => ^goal_id,
                 "status" => "completed",
                 "progress_note" => "Added the explicit goal surface."
               }
             }
           } = update_response

    record = Memory.get_record(goal_id)
    assert record.record_type == "goal"
    assert get_in(record.metadata, ["goal_status"]) == "completed"

    completed_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2084,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_goal",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "list",
            "status" => "completed"
          }
        }
      })

    assert Enum.any?(
             get_in(completed_response, ["result", "structuredContent", "goals"]),
             &(&1["id"] == goal_id and &1["status"] == "completed")
           )
  end

  test "tools/call ck_memory_archive archives an existing memory record" do
    session = session_fixture()

    record =
      memory_record_fixture(%{
        session: session,
        title: "Archive me",
        summary: "Superseded guidance"
      })

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 209,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_memory_archive",
          "arguments" => %{
            "session_id" => session.id,
            "memory_id" => record.id
          }
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "archived" => true,
                 "memory_id" => archived_id
               }
             }
           } = response

    assert archived_id == record.id
    assert ControlKeel.Memory.get_record!(record.id).archived_at != nil
  end

  test "review tools tolerate missing endpoint persistent term" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    submit_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 701,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "task_id" => task.id,
            "submission_body" => "Plan from MCP"
          }
        }
      })

    review_id = get_in(submit_response, ["result", "structuredContent", "review_id"])
    assert is_integer(review_id)

    key = {Phoenix.Endpoint, ControlKeelWeb.Endpoint}
    original = :persistent_term.get(key, :missing)
    :persistent_term.erase(key)

    on_exit(fn ->
      case original do
        :missing -> :ok
        value -> :persistent_term.put(key, value)
      end
    end)

    status_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 702,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_status",
          "arguments" => %{"review_id" => review_id}
        }
      })

    assert get_in(status_response, ["result", "structuredContent", "status"]) == "pending"
    assert get_in(status_response, ["result", "structuredContent", "browser_url"]) == nil

    feedback_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 703,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_feedback",
          "arguments" => %{
            "review_id" => review_id,
            "decision" => "approved",
            "feedback_notes" => "Proceed"
          }
        }
      })

    assert get_in(feedback_response, ["result", "structuredContent", "status"]) == "approved"
    assert get_in(feedback_response, ["result", "structuredContent", "browser_url"]) == nil
  end

  test "ck_review_status falls back to CLI when review_id is not in local mission db" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-review-fallback-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    fake_bin = write_fake_controlkeel_cli(tmp_dir)
    expected_root = Path.join(tmp_dir, "expected-root")
    File.mkdir_p!(expected_root)

    previous_bin = System.get_env("CONTROLKEEL_BIN")
    previous_project_root = System.get_env("CONTROLKEEL_PROJECT_ROOT")
    System.put_env("CONTROLKEEL_BIN", fake_bin)
    System.put_env("CONTROLKEEL_PROJECT_ROOT", expected_root)

    on_exit(fn ->
      if previous_bin,
        do: System.put_env("CONTROLKEEL_BIN", previous_bin),
        else: System.delete_env("CONTROLKEEL_BIN")

      if previous_project_root,
        do: System.put_env("CONTROLKEEL_PROJECT_ROOT", previous_project_root),
        else: System.delete_env("CONTROLKEEL_PROJECT_ROOT")

      File.rm_rf!(tmp_dir)
    end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 804,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_status",
          "arguments" => %{"review_id" => 999_901}
        }
      })

    assert get_in(response, ["result", "structuredContent", "review_id"]) == 999_901
    assert get_in(response, ["result", "structuredContent", "status"]) == "pending"
    assert get_in(response, ["result", "structuredContent", "browser_url"]) =~ "/reviews/999901"
  end

  test "ck_review_feedback falls back to CLI when review_id is not in local mission db" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-review-fallback-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    fake_bin = write_fake_controlkeel_cli(tmp_dir)
    expected_root = Path.join(tmp_dir, "expected-root")
    File.mkdir_p!(expected_root)

    previous_bin = System.get_env("CONTROLKEEL_BIN")
    previous_project_root = System.get_env("CONTROLKEEL_PROJECT_ROOT")
    System.put_env("CONTROLKEEL_BIN", fake_bin)
    System.put_env("CONTROLKEEL_PROJECT_ROOT", expected_root)

    on_exit(fn ->
      if previous_bin,
        do: System.put_env("CONTROLKEEL_BIN", previous_bin),
        else: System.delete_env("CONTROLKEEL_BIN")

      if previous_project_root,
        do: System.put_env("CONTROLKEEL_PROJECT_ROOT", previous_project_root),
        else: System.delete_env("CONTROLKEEL_PROJECT_ROOT")

      File.rm_rf!(tmp_dir)
    end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 805,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_feedback",
          "arguments" => %{
            "review_id" => 999_902,
            "decision" => "approved",
            "feedback_notes" => "Proceed",
            "reviewed_by" => "mcp-test",
            "annotations" => %{"source" => "fallback"}
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "review_id"]) == 999_902
    assert get_in(response, ["result", "structuredContent", "status"]) == "approved"
    assert get_in(response, ["result", "structuredContent", "feedback_notes"]) == "Proceed"
    assert get_in(response, ["result", "structuredContent", "browser_url"]) =~ "/reviews/999902"
  end

  test "ck_review_status fallback tries MIX_ENV variants" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-review-fallback-mixenv-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    fake_bin = write_fake_controlkeel_cli_mixenv(tmp_dir)
    expected_root = Path.join(tmp_dir, "expected-root")
    File.mkdir_p!(expected_root)

    previous_bin = System.get_env("CONTROLKEEL_BIN")
    previous_project_root = System.get_env("CONTROLKEEL_PROJECT_ROOT")
    previous_mix_env = System.get_env("MIX_ENV")

    System.put_env("CONTROLKEEL_BIN", fake_bin)
    System.put_env("CONTROLKEEL_PROJECT_ROOT", expected_root)
    System.put_env("MIX_ENV", "dev")

    on_exit(fn ->
      if previous_bin,
        do: System.put_env("CONTROLKEEL_BIN", previous_bin),
        else: System.delete_env("CONTROLKEEL_BIN")

      if previous_project_root,
        do: System.put_env("CONTROLKEEL_PROJECT_ROOT", previous_project_root),
        else: System.delete_env("CONTROLKEEL_PROJECT_ROOT")

      if previous_mix_env,
        do: System.put_env("MIX_ENV", previous_mix_env),
        else: System.delete_env("MIX_ENV")

      File.rm_rf!(tmp_dir)
    end)

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 806,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_status",
          "arguments" => %{"review_id" => 999_911}
        }
      })

    assert get_in(response, ["result", "structuredContent", "review_id"]) == 999_911
    assert get_in(response, ["result", "structuredContent", "status"]) == "approved"
    assert get_in(response, ["result", "structuredContent", "browser_url"]) =~ "/reviews/999911"
  end

  test "review tools submit, inspect, and respond to plan reviews" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    submit_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 77,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "task_id" => task.id,
            "submission_body" => "Plan from MCP"
          }
        }
      })

    review_id = get_in(submit_response, ["result", "structuredContent", "review_id"])
    assert is_integer(review_id)

    status_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 78,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_status",
          "arguments" => %{"review_id" => review_id}
        }
      })

    assert get_in(status_response, ["result", "structuredContent", "status"]) == "pending"

    feedback_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 79,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_feedback",
          "arguments" => %{
            "review_id" => review_id,
            "decision" => "approved",
            "feedback_notes" => "Proceed"
          }
        }
      })

    assert get_in(feedback_response, ["result", "structuredContent", "status"]) == "approved"

    [event] = Accounts.review_audit_events(review_id)
    assert event.event_type == "approved"
    assert event.actor_source == "mcp"
    assert event.actor_identifier == "mcp"
    assert event.note == "Proceed"

    denied_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 80,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_feedback",
          "arguments" => %{
            "review_id" => review_id,
            "decision" => "denied",
            "feedback_notes" => "Revise the plan"
          }
        }
      })

    assert get_in(denied_response, ["result", "structuredContent", "status"]) == "denied"

    status_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 81,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_status",
          "arguments" => %{"review_id" => review_id}
        }
      })

    assert get_in(status_response, ["result", "structuredContent", "agent_feedback"]) =~
             "YOUR PLAN WAS NOT APPROVED"
  end

  test "tools/call ck_review_submit supports session-scoped plan submissions without task_id" do
    session = session_fixture()

    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 82,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_review_submit",
          "arguments" => %{
            "session_id" => session.id,
            "review_type" => "plan",
            "submission_body" => "Session-scoped plan without task id"
          }
        }
      })

    assert is_integer(get_in(response, ["result", "structuredContent", "review_id"]))
    assert get_in(response, ["result", "structuredContent", "status"]) == "pending"
    assert get_in(response, ["result", "structuredContent", "session_id"]) == session.id
    assert get_in(response, ["result", "structuredContent", "task_id"]) == nil
  end

  test "tools/call ck_budget estimates and commits invocation cost" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 800, spent_cents: 100})

    estimate_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_budget",
          "arguments" => %{
            "session_id" => session.id,
            "provider" => "openai",
            "model" => "o4-mini",
            "input_tokens" => 100_000,
            "output_tokens" => 50_000
          }
        }
      })

    assert get_in(estimate_response, ["result", "structuredContent", "decision"]) in [
             "allow",
             "warn"
           ]

    assert get_in(estimate_response, ["result", "structuredContent", "recorded"]) == false

    commit_response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_budget",
          "arguments" => %{
            "session_id" => session.id,
            "mode" => "commit",
            "estimated_cost_cents" => 120
          }
        }
      })

    assert get_in(commit_response, ["result", "structuredContent", "recorded"]) == true
    assert Repo.aggregate(Invocation, :count, :id) == 1
    assert Mission.get_session!(session.id).spent_cents == 220
  end

  test "invalid payload returns a structured json-rpc error" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_validate",
          "arguments" => %{"content" => "", "kind" => "code"}
        }
      })

    assert %{
             "jsonrpc" => "2.0",
             "id" => 8,
             "error" => %{"code" => -32602, "message" => message}
           } = response

    assert message =~ "`content` is required"
  end

  test "tools/call ck_skill_list returns compatibility metadata and diagnostics" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 61,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_list",
          "arguments" => %{"format" => "xml", "target" => "codex"}
        }
      })

    assert %{
             "result" => %{
               "structuredContent" => %{
                 "skills" => skills,
                 "total" => total,
                 "prompt_block" => prompt_block,
                 "trusted_project_skills" => false
               }
             }
           } = response

    assert total == length(skills)
    assert total > 0
    assert prompt_block =~ "<available_skills>"

    governance = Enum.find(skills, &(&1["name"] == "controlkeel-governance"))
    assert "codex" in governance["compatibility_targets"]
    assert is_list(governance["required_mcp_tools"])
    assert is_map(governance["install_state"])
  end

  test "tools/call ck_skill_load dedupes repeated activations" do
    first =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 62,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_load",
          "arguments" => %{"name" => "controlkeel-governance", "session_id" => 123}
        }
      })

    second =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 63,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_skill_load",
          "arguments" => %{"name" => "controlkeel-governance", "session_id" => 123}
        }
      })

    assert get_in(first, ["result", "structuredContent", "activation"]) == "new"
    assert get_in(second, ["result", "structuredContent", "activation"]) == "duplicate"
    assert get_in(first, ["result", "structuredContent", "content"]) =~ "<skill_content"
    assert is_list(get_in(first, ["result", "structuredContent", "resources"]))
  end

  test "tools/call ck_load_resources loads skill resources for tool-only clients" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 64,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_load_resources",
          "arguments" => %{
            "uris" => ["skills://controlkeel-governance"],
            "session_id" => 123
          }
        }
      })

    assert %{"result" => %{"structuredContent" => %{"resources" => [resource], "total" => 1}}} =
             response

    assert resource["uri"] == "skills://controlkeel-governance"
    assert resource["text"] =~ "<skill_content"
    assert is_list(resource["resources"])
  end

  test "tools/call ck_load_resources loads multiple skill resources in order" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 65,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_load_resources",
          "arguments" => %{
            "uris" => ["skills://controlkeel-governance", "skills://investigate"],
            "session_id" => 123
          }
        }
      })

    assert %{"result" => %{"structuredContent" => %{"resources" => resources, "total" => 2}}} =
             response

    assert Enum.map(resources, & &1["uri"]) == [
             "skills://controlkeel-governance",
             "skills://investigate"
           ]

    assert Enum.all?(resources, &String.contains?(&1["text"], "<skill_content"))
    assert Enum.all?(resources, &is_list(&1["resources"]))
  end

  defp write_fake_controlkeel_cli_mixenv(tmp_dir) do
    script_path = Path.join(tmp_dir, "local-controlkeel-mixenv.sh")

    File.write!(
      script_path,
      """
      #!/bin/sh
      expected_root="$CONTROLKEEL_PROJECT_ROOT"

      if [ -z "$expected_root" ]; then
        expected_root="$CK_PROJECT_ROOT"
      fi

      if [ -z "$expected_root" ]; then
        expected_root="$(pwd)"
      fi

      expected_root="$(cd "$expected_root" 2>/dev/null && pwd -P || printf '%s' "$expected_root")"
      cwd="$(pwd -P)"

      if [ "$cwd" != "$expected_root" ]; then
        echo "unexpected cwd: $cwd expected: $expected_root" >&2
        exit 9
      fi

      if [ "$1" = "review" ] && [ "$2" = "plan" ] && [ "$3" = "wait" ]; then
        if [ "${MIX_ENV:-}" = "prod" ]; then
          echo '{"message":"wait","browser_url":"https://example.test/reviews/999911","review":{"id":999911,"title":"MIX_ENV fallback plan","status":"approved","review_type":"plan","session_id":10,"task_id":20,"feedback_notes":"from-prod","annotations":{}}}'
          exit 0
        fi

        echo "controlled failure in non-prod mix env" >&2
        exit 2
      fi

      echo "unsupported args" >&2
      exit 2
      """
    )

    File.chmod!(script_path, 0o755)
    script_path
  end

  defp write_fake_controlkeel_cli(tmp_dir) do
    script_path = Path.join(tmp_dir, "local-controlkeel.sh")

    File.write!(
      script_path,
      """
      #!/bin/sh
      expected_root="$CONTROLKEEL_PROJECT_ROOT"

      if [ -z "$expected_root" ]; then
        expected_root="$CK_PROJECT_ROOT"
      fi

      if [ -z "$expected_root" ]; then
        expected_root="$(pwd)"
      fi

      expected_root="$(cd "$expected_root" 2>/dev/null && pwd -P || printf '%s' "$expected_root")"
      cwd="$(pwd -P)"

      if [ "$cwd" != "$expected_root" ]; then
        echo "unexpected cwd: $cwd expected: $expected_root" >&2
        exit 9
      fi

      if [ "$1" = "review" ] && [ "$2" = "plan" ] && [ "$3" = "wait" ]; then
        echo "preface: waiting on review" >&2
        echo '{"message":"timeout","timed_out":true,"status":"pending","browser_url":"https://example.test/reviews/999901","review":{"id":999901,"title":"CLI fallback plan","status":"pending","review_type":"plan","session_id":10,"task_id":20,"feedback_notes":null,"annotations":{}}}'
        exit 1
      fi

      if [ "$1" = "review" ] && [ "$2" = "plan" ] && [ "$3" = "respond" ]; then
        echo "preface: applying review response" >&2
        echo '{"message":"responded","browser_url":"https://example.test/reviews/999902","review":{"id":999902,"title":"CLI fallback plan","status":"approved","review_type":"plan","session_id":10,"task_id":20,"feedback_notes":"Proceed","annotations":{"source":"fallback"}},"agent_feedback":null}'
        exit 0
      fi

      echo "unsupported args" >&2
      exit 2
      """
    )

    File.chmod!(script_path, 0o755)
    script_path
  end
end
