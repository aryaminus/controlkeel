defmodule ControlKeel.MCP.ProtocolTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Protocol
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo
  alias ControlKeel.Skills.Activation

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
             "ck_finding",
             "ck_budget",
             "ck_route",
             "ck_skill_list",
             "ck_skill_load"
           ]
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
    session = session_fixture(%{budget_cents: 1_500, daily_budget_cents: 500, spent_cents: 250})
    session_id = session.id
    task = task_fixture(%{session: session, status: "in_progress", title: "Implement router"})
    finding_fixture(%{session: session, status: "blocked", category: "security"})
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
                 "budget_summary" => %{
                   "spent_cents" => 250,
                   "session_budget_cents" => 1_500,
                   "daily_budget_cents" => 500
                 },
                 "current_task" => %{"title" => "Implement router"},
                 "proof_summary" => %{"task_id" => _},
                 "memory_hits" => memory_hits,
                 "resume_packet" => %{"task_id" => _}
               }
             }
           } = response

    assert is_list(memory_hits)
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
