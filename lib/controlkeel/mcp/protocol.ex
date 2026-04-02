defmodule ControlKeel.MCP.Protocol do
  @moduledoc false

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Skills.Registry

  alias ControlKeel.MCP.Tools.{
    CkBudget,
    CkContext,
    CkDelegate,
    CkFinding,
    CkReviewFeedback,
    CkReviewStatus,
    CkReviewSubmit,
    CkRoute,
    CkSkillList,
    CkSkillLoad,
    CkValidate,
    CkCostOptimizer,
    CkDeploymentAdvisor,
    CkOutcomeTracker
  }

  @server_info %{
    "name" => "controlkeel",
    "version" => to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")
  }

  def handle_json(payload, opts \\ []) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, request} -> handle_request(request, opts)
      {:error, error} -> error_response(nil, -32700, "Parse error: #{Exception.message(error)}")
    end
  end

  def handle_request(request, opts \\ [])

  def handle_request(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}, _opts) do
    ok_response(id, %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{"tools" => %{"listChanged" => false}},
      "serverInfo" => @server_info
    })
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _opts),
    do: :no_response

  def handle_request(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, _opts) do
    ok_response(id, %{"tools" => tool_schemas()})
  end

  def handle_request(
        %{
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "id" => id,
          "params" => params
        },
        opts
      ) do
    case params do
      %{"name" => name, "arguments" => arguments} ->
        with :ok <- authorize_tool(name, arguments, opts) do
          tool_response(id, dispatch_tool(name, arguments))
        else
          {:error, {:forbidden, reason}} ->
            error_response(id, -32001, reason)

          {:error, reason} ->
            error_response(id, -32602, inspect(reason))
        end

      _other ->
        error_response(id, -32602, "tools/call requires a tool name and arguments")
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => _method, "id" => id}, _opts) do
    error_response(id, -32601, "Method not found")
  end

  def handle_request(_request, _opts) do
    error_response(nil, -32600, "Invalid Request")
  end

  def tool_schemas do
    base = [
      ck_validate_tool(),
      ck_context_tool(),
      ck_finding_tool(),
      ck_review_submit_tool(),
      ck_review_status_tool(),
      ck_review_feedback_tool(),
      ck_budget_tool(),
      ck_route_tool(),
      ck_delegate_tool(),
      ck_cost_optimizer_tool(),
      ck_deployment_advisor_tool(),
      ck_outcome_tracker_tool()
    ]

    if current_skill_names() == [] do
      base
    else
      base ++ [ck_skill_list_tool(), ck_skill_load_tool()]
    end
  end

  def dispatch_tool("ck_validate", arguments), do: CkValidate.call(arguments)
  def dispatch_tool("ck_context", arguments), do: CkContext.call(arguments)
  def dispatch_tool("ck_finding", arguments), do: CkFinding.call(arguments)
  def dispatch_tool("ck_review_submit", arguments), do: CkReviewSubmit.call(arguments)
  def dispatch_tool("ck_review_status", arguments), do: CkReviewStatus.call(arguments)
  def dispatch_tool("ck_review_feedback", arguments), do: CkReviewFeedback.call(arguments)
  def dispatch_tool("ck_budget", arguments), do: CkBudget.call(arguments)
  def dispatch_tool("ck_route", arguments), do: CkRoute.call(arguments)
  def dispatch_tool("ck_delegate", arguments), do: CkDelegate.call(arguments)
  def dispatch_tool("ck_skill_list", arguments), do: CkSkillList.call(arguments)
  def dispatch_tool("ck_skill_load", arguments), do: CkSkillLoad.call(arguments)
  def dispatch_tool("ck_cost_optimizer", arguments), do: CkCostOptimizer.call(arguments)
  def dispatch_tool("ck_deployment_advisor", arguments), do: CkDeploymentAdvisor.call(arguments)
  def dispatch_tool("ck_outcome_tracker", arguments), do: CkOutcomeTracker.call(arguments)

  def dispatch_tool(unknown, _arguments),
    do: {:error, {:invalid_arguments, "Unknown tool: #{unknown}"}}

  def ck_validate_tool do
    %{
      "name" => "ck_validate",
      "description" => "Validate proposed code, config, shell, or text content before execution.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "kind" => %{"type" => "string", "enum" => ["code", "config", "shell", "text"]},
          "domain_pack" => %{"type" => "string", "enum" => Domains.supported_packs()},
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_context_tool do
    %{
      "name" => "ck_context",
      "description" =>
        "Fetch the current mission, risk, finding, and budget context for a session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_finding_tool do
    %{
      "name" => "ck_finding",
      "description" => "Persist a governed finding and return the ruling state.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "category", "severity", "rule_id", "plain_message"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "category" => %{"type" => "string"},
          "severity" => %{"type" => "string"},
          "rule_id" => %{"type" => "string"},
          "plain_message" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "decision" => %{
            "type" => "string",
            "enum" => ["allow", "warn", "block", "escalate_to_human"]
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_review_submit_tool do
    %{
      "name" => "ck_review_submit",
      "description" =>
        "Submit a governed plan, diff, or completion packet for browser review and execution gating.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["submission_body"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "title" => %{"type" => "string"},
          "review_type" => %{"type" => "string", "enum" => ["plan", "diff", "completion"]},
          "submission_body" => %{"type" => "string"},
          "annotations" => %{"type" => "object"},
          "feedback_notes" => %{"type" => "string"},
          "submitted_by" => %{"type" => "string"},
          "metadata" => %{"type" => "object"},
          "previous_review_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_review_status_tool do
    %{
      "name" => "ck_review_status",
      "description" => "Fetch the latest status, notes, and browser URL for a submitted review.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "review_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "review_type" => %{"type" => "string", "enum" => ["plan", "diff", "completion"]}
        }
      }
    }
  end

  def ck_review_feedback_tool do
    %{
      "name" => "ck_review_feedback",
      "description" => "Approve or deny a submitted review and attach feedback or annotations.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["review_id", "decision"],
        "properties" => %{
          "review_id" => %{"type" => ["integer", "string"]},
          "decision" => %{"type" => "string", "enum" => ["approved", "denied"]},
          "feedback_notes" => %{"type" => "string"},
          "annotations" => %{"type" => "object"},
          "reviewed_by" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_budget_tool do
    %{
      "name" => "ck_budget",
      "description" =>
        "Estimate or record the cost of an agent operation against session and daily budgets.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "mode" => %{"type" => "string", "enum" => ["estimate", "commit"]},
          "estimated_cost_cents" => %{"type" => ["integer", "string"]},
          "provider" => %{"type" => "string"},
          "model" => %{"type" => "string"},
          "input_tokens" => %{"type" => ["integer", "string"]},
          "cached_input_tokens" => %{"type" => ["integer", "string"]},
          "output_tokens" => %{"type" => ["integer", "string"]},
          "source" => %{"type" => "string"},
          "tool" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  defp authorize_tool(name, arguments, opts) do
    case Keyword.get(opts, :authorize) do
      nil -> :ok
      fun when is_function(fun, 2) -> fun.(name, arguments)
      _ -> :ok
    end
  end

  defp ck_route_tool do
    %{
      "name" => "ck_route",
      "description" =>
        "Recommend the best AI agent for a given task, considering security tier, remaining budget, and task type.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["task"],
        "properties" => %{
          "task" => %{
            "type" => "string",
            "description" => "Plain-language description of the task to be performed"
          },
          "risk_tier" => %{
            "type" => "string",
            "enum" => ["low", "medium", "high", "critical"],
            "description" => "Security sensitivity of the task. Default: medium"
          },
          "budget_remaining_cents" => %{
            "type" => ["integer", "string"],
            "description" => "Remaining session budget in cents"
          },
          "allowed_agents" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "Restrict routing to these agent IDs. Omit to allow all supported agents."
          }
        }
      }
    }
  end

  defp ck_delegate_tool do
    %{
      "name" => "ck_delegate",
      "description" =>
        "Ask ControlKeel to run or hand off a governed task or session to another supported agent.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{"type" => ["integer", "string"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "agent" => %{"type" => "string"},
          "mode" => %{"type" => "string", "enum" => ["auto", "embedded", "handoff", "runtime"]},
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  defp ck_cost_optimizer_tool do
    %{
      "name" => "ck_cost_optimizer",
      "description" => "Get cost optimization suggestions or compare agent prices for a task.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["suggest", "compare"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "spending" => %{"type" => "array", "items" => %{"type" => "object"}},
          "top_provider" => %{"type" => "string"},
          "top_model" => %{"type" => "string"},
          "task_description" => %{"type" => "string"},
          "estimated_tokens" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_deployment_advisor_tool do
    %{
      "name" => "ck_deployment_advisor",
      "description" =>
        "Analyze project stack, suggest deployment platforms, and generate CI/CD/Docker files.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode", "project_root"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["analyze", "generate_files", "dns_guide"]},
          "project_root" => %{"type" => "string"},
          "dry_run" => %{"type" => "boolean"}
        }
      }
    }
  end

  defp ck_outcome_tracker_tool do
    %{
      "name" => "ck_outcome_tracker",
      "description" =>
        "Record session outcomes or get leaderboard for agents to power reinforcement learning.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["record", "get_session", "get_leaderboard"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "outcome" => %{"type" => "string"},
          "agent_id" => %{"type" => "string"},
          "task_type" => %{"type" => "string"},
          "workspace_id" => %{"type" => "string"},
          "limit" => %{"type" => "integer"},
          "window" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_skill_list_tool do
    %{
      "name" => "ck_skill_list",
      "description" =>
        "List all available AgentSkills for this project. Returns names, descriptions, and scopes. " <>
          "Call this to discover capabilities you can activate, then use ck_skill_load to load a skill's full instructions.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" => "Absolute path to the project root. Omit to use global skills only."
          },
          "target" => %{
            "type" => "string",
            "description" =>
              "Optional compatibility target filter, such as codex or claude-plugin."
          },
          "format" => %{
            "type" => "string",
            "enum" => ["json", "xml"],
            "description" =>
              "Response format. Use xml to receive an <available_skills> block for system prompt injection."
          }
        }
      }
    }
  end

  defp ck_skill_load_tool do
    names = current_skill_names()

    %{
      "name" => "ck_skill_load",
      "description" =>
        "Load the full instructions for a named AgentSkill. Returns the SKILL.md body wrapped in " <>
          "<skill_content> tags plus a list of bundled resource files. " <>
          "Call after ck_skill_list to activate a specific skill.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["name"],
        "properties" => %{
          "name" => %{
            "type" => "string",
            "description" => "The skill name as returned by ck_skill_list",
            "enum" => names
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Omit to search global skills only."
          },
          "target" => %{
            "type" => "string",
            "description" => "Optional render target such as codex, claude, copilot, or cursor."
          },
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp current_skill_names do
    Registry.names(File.cwd!(), trust_project_skills: true)
  end

  defp tool_response(id, {:ok, result}) do
    ok_response(id, %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(result)}],
      "structuredContent" => result
    })
  end

  defp tool_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  defp tool_response(id, {:error, reason}), do: error_response(id, -32000, inspect(reason))

  defp ok_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end
end
