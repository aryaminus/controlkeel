defmodule ControlKeel.MCP.ProtocolTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Protocol
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.ProjectBinding
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
               "capabilities" => %{"tools" => %{"listChanged" => false}},
               "serverInfo" => %{"name" => "controlkeel"}
             }
           } = response
  end

  test "tools/list returns all controlkeel tools in stable order" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list"
      })

    assert %{"result" => %{"tools" => tools}} = response

    assert Enum.map(tools, & &1["name"]) == [
             "ck_validate",
             "ck_context",
             "ck_experience_index",
             "ck_experience_read",
             "ck_trace_packet",
             "ck_failure_clusters",
             "ck_skill_evolution",
             "ck_fs_ls",
             "ck_fs_read",
             "ck_fs_find",
             "ck_fs_grep",
             "ck_finding",
             "ck_review_submit",
             "ck_review_status",
             "ck_review_feedback",
             "ck_regression_result",
             "ck_memory_search",
             "ck_memory_record",
             "ck_memory_archive",
             "ck_budget",
             "ck_route",
             "ck_delegate",
             "ck_cost_optimizer",
             "ck_deployment_advisor",
             "ck_outcome_tracker",
             "ck_skill_list",
             "ck_skill_load"
           ]
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

    assert get_in(tool, ["inputSchema", "properties", "requested_capabilities", "items", "enum"]) !=
             nil
  end

  test "tools/list exposes experience archive inputs" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2001,
        "method" => "tools/list"
      })

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
             "scope_estimate",
             "properties",
             "architectural_scope",
             "type"
           ]) == "boolean"
  end

  test "tools/list exposes virtual workspace inputs for ck_fs_grep" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 202,
        "method" => "tools/list"
      })

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_fs_grep"))

    assert get_in(tool, ["inputSchema", "required"]) == ["session_id", "query"]
    assert get_in(tool, ["inputSchema", "properties", "fixed_strings", "type"]) == "boolean"
    assert get_in(tool, ["inputSchema", "properties", "ignore_case", "type"]) == "boolean"
  end

  test "tools/list exposes trace packet inputs" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2022,
        "method" => "tools/list"
      })

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_trace_packet"))

    assert get_in(tool, ["inputSchema", "required"]) == ["session_id"]

    assert get_in(tool, ["inputSchema", "properties", "events_limit", "type"]) == [
             "integer",
             "string"
           ]
  end

  test "tools/list exposes failure cluster inputs" do
    response =
      Protocol.handle_request(%{
        "jsonrpc" => "2.0",
        "id" => 2024,
        "method" => "tools/list"
      })

    tool =
      response
      |> get_in(["result", "tools"])
      |> Enum.find(&(&1["name"] == "ck_failure_clusters"))

    assert get_in(tool, ["inputSchema", "required"]) == ["session_id"]
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
      ProjectBinding.write(
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
        Protocol.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 32,
          "method" => "tools/list"
        })
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

    assert is_binary(content)
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
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n\nOAuth lives here.\n")
    File.write!(Path.join(tmp_dir, "docs/guide.md"), "Guide\n\nOAuth config lives here too.\n")

    {:ok, _binding} =
      ProjectBinding.write(
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
            "arguments" => %{"session_id" => session.id, "path" => "."}
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
            "arguments" => %{"session_id" => session.id, "path" => "README.md"}
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
            "arguments" => %{"session_id" => session.id, "query" => "OAuth"}
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
            "arguments" => %{"session_id" => session.id, "query" => "guide"}
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
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n")

    {:ok, _binding} =
      ProjectBinding.write(
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

    assert is_list(memory_hits)
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
            "options_considered" => ["Extend review metadata", "Create planner subsystem"],
            "selected_option" => "Extend review metadata",
            "rejected_options" => ["Create planner subsystem"],
            "implementation_steps" => [
              "Normalize plan refinement",
              "Check plan continuity in proof bundles"
            ],
            "validation_plan" => ["mix test", "mix precommit"],
            "submission_body" => "Recursive implementation plan"
          }
        }
      })

    assert get_in(response, ["result", "structuredContent", "plan_phase"]) ==
             "implementation_plan"

    assert get_in(response, ["result", "structuredContent", "plan_quality", "ready"]) == true
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
            "model" => "gpt-5.4-mini",
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
end
