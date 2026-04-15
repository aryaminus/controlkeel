defmodule ControlKeel.MCP.Protocol do
  @moduledoc false

  alias ControlKeel.Intent.Domains
  alias ControlKeel.SecurityWorkflow
  alias ControlKeel.Skills.Registry
  alias ControlKeel.TrustBoundary

  alias ControlKeel.MCP.Tools.{
    CkBudget,
    CkContext,
    CkDelegate,
    CkExperienceIndex,
    CkExperienceRead,
    CkFsFind,
    CkFsGrep,
    CkFsLs,
    CkFsRead,
    CkFailureClusters,
    CkFinding,
    CkLoadResources,
    CkMemoryArchive,
    CkMemoryRecord,
    CkMemorySearch,
    CkSkillEvolution,
    CkReviewFeedback,
    CkRegressionResult,
    CkReviewStatus,
    CkReviewSubmit,
    CkRoute,
    CkTracePacket,
    CkSkillList,
    CkSkillLoad,
    CkValidate,
    CkCostOptimizer,
    CkDeploymentAdvisor,
    CkOutcomeTracker
  }

  @server_info %{
    "name" => "controlkeel",
    "version" => to_string(Application.spec(:controlkeel, :vsn) || "0.2.0")
  }

  def handle_json(payload, opts \\ []) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, request} -> handle_request(request, opts)
      {:error, error} -> error_response(nil, -32700, "Parse error: #{Exception.message(error)}")
    end
  end

  def handle_request(request, opts \\ [])

  def handle_request(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id} = req, _opts) do
    requested = get_in(req, ["params", "protocolVersion"])
    negotiated = negotiate_mcp_protocol_version(requested)

    ok_response(id, %{
      "protocolVersion" => negotiated,
      "capabilities" => %{
        "tools" => %{"listChanged" => false},
        "resources" => %{"subscribe" => false, "listChanged" => false}
      },
      "serverInfo" => @server_info
    })
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _opts),
    do: :no_response

  def handle_request(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, opts) do
    ok_response(id, %{"tools" => tool_schemas(opts)})
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "resources/list", "id" => id}, opts) do
    ok_response(id, %{"resources" => resource_schemas(opts)})
  end

  def handle_request(
        %{"jsonrpc" => "2.0", "method" => "resources/read", "id" => id, "params" => params},
        _opts
      ) do
    case mcp_stdio_boot_gate(id) do
      :ok ->
        case params do
          %{"uri" => uri} ->
            resource_response(id, load_resource(uri, params))

          _ ->
            error_response(id, -32602, "resources/read requires a resource uri")
        end

      {:error, response} ->
        response
    end
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
    case mcp_stdio_boot_gate(id) do
      :ok ->
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

      {:error, response} ->
        response
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => _method, "id" => id}, _opts) do
    error_response(id, -32601, "Method not found")
  end

  def handle_request(_request, _opts) do
    error_response(nil, -32600, "Invalid Request")
  end

  def tool_schemas(opts \\ []) do
    base = [
      ck_validate_tool(),
      ck_context_tool(),
      ck_experience_index_tool(),
      ck_experience_read_tool(),
      ck_trace_packet_tool(),
      ck_failure_clusters_tool(),
      ck_skill_evolution_tool(),
      ck_fs_ls_tool(),
      ck_fs_read_tool(),
      ck_fs_find_tool(),
      ck_fs_grep_tool(),
      ck_finding_tool(),
      ck_review_submit_tool(),
      ck_review_status_tool(),
      ck_review_feedback_tool(),
      ck_regression_result_tool(),
      ck_memory_search_tool(),
      ck_memory_record_tool(),
      ck_memory_archive_tool(),
      ck_budget_tool(),
      ck_route_tool(),
      ck_delegate_tool(),
      ck_cost_optimizer_tool(),
      ck_deployment_advisor_tool(),
      ck_outcome_tracker_tool(),
      ck_load_resources_tool()
    ]

    # Always expose ck_skill_list / ck_skill_load. Do not call Registry here: a full
    # catalog walk (every agent skill dir under $HOME) can take 10–30s and blocks this
    # process while Cursor expects tools/list under a ~20s connect budget.
    tools = base ++ [ck_skill_list_tool(), ck_skill_load_tool()]

    case Keyword.get(opts, :tool_names) do
      names when is_list(names) -> Enum.filter(tools, &(&1["name"] in names))
      _ -> tools
    end
  end

  def dispatch_tool("ck_validate", arguments), do: CkValidate.call(arguments)
  def dispatch_tool("ck_context", arguments), do: CkContext.call(arguments)
  def dispatch_tool("ck_experience_index", arguments), do: CkExperienceIndex.call(arguments)
  def dispatch_tool("ck_experience_read", arguments), do: CkExperienceRead.call(arguments)
  def dispatch_tool("ck_trace_packet", arguments), do: CkTracePacket.call(arguments)
  def dispatch_tool("ck_failure_clusters", arguments), do: CkFailureClusters.call(arguments)
  def dispatch_tool("ck_skill_evolution", arguments), do: CkSkillEvolution.call(arguments)
  def dispatch_tool("ck_fs_ls", arguments), do: CkFsLs.call(arguments)
  def dispatch_tool("ck_fs_read", arguments), do: CkFsRead.call(arguments)
  def dispatch_tool("ck_fs_find", arguments), do: CkFsFind.call(arguments)
  def dispatch_tool("ck_fs_grep", arguments), do: CkFsGrep.call(arguments)
  def dispatch_tool("ck_finding", arguments), do: CkFinding.call(arguments)
  def dispatch_tool("ck_review_submit", arguments), do: CkReviewSubmit.call(arguments)
  def dispatch_tool("ck_review_status", arguments), do: CkReviewStatus.call(arguments)
  def dispatch_tool("ck_review_feedback", arguments), do: CkReviewFeedback.call(arguments)
  def dispatch_tool("ck_regression_result", arguments), do: CkRegressionResult.call(arguments)
  def dispatch_tool("ck_memory_search", arguments), do: CkMemorySearch.call(arguments)
  def dispatch_tool("ck_memory_record", arguments), do: CkMemoryRecord.call(arguments)
  def dispatch_tool("ck_memory_archive", arguments), do: CkMemoryArchive.call(arguments)
  def dispatch_tool("ck_budget", arguments), do: CkBudget.call(arguments)
  def dispatch_tool("ck_route", arguments), do: CkRoute.call(arguments)
  def dispatch_tool("ck_delegate", arguments), do: CkDelegate.call(arguments)
  def dispatch_tool("ck_skill_list", arguments), do: CkSkillList.call(arguments)
  def dispatch_tool("ck_skill_load", arguments), do: CkSkillLoad.call(arguments)
  def dispatch_tool("ck_load_resources", arguments), do: CkLoadResources.call(arguments)
  def dispatch_tool("ck_cost_optimizer", arguments), do: CkCostOptimizer.call(arguments)
  def dispatch_tool("ck_deployment_advisor", arguments), do: CkDeploymentAdvisor.call(arguments)
  def dispatch_tool("ck_outcome_tracker", arguments), do: CkOutcomeTracker.call(arguments)

  def dispatch_tool(unknown, _arguments),
    do: {:error, {:invalid_arguments, "Unknown tool: #{unknown}"}}

  def ck_validate_tool do
    %{
      "name" => "ck_validate",
      "description" =>
        "Validate proposed code, config, shell, or text content before execution, including trust-boundary checks for untrusted instructions and high-impact actions.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "kind" => %{"type" => "string", "enum" => ["code", "config", "shell", "text"]},
          "domain_pack" => %{"type" => "string", "enum" => Domains.supported_packs()},
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "source_type" => %{"type" => "string", "enum" => TrustBoundary.source_types()},
          "trust_level" => %{"type" => "string", "enum" => TrustBoundary.trust_levels()},
          "intended_use" => %{"type" => "string", "enum" => TrustBoundary.intended_uses()},
          "security_workflow_phase" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.phases()
          },
          "artifact_type" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.artifact_types()
          },
          "target_scope" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.target_scopes()
          },
          "requested_capabilities" => %{
            "type" => "array",
            "items" => %{"type" => "string", "enum" => TrustBoundary.capabilities()}
          }
        }
      }
    }
  end

  def ck_context_tool do
    %{
      "name" => "ck_context",
      "description" =>
        "Fetch current mission state, governed findings, budget, proof summary, planning context, workspace snapshot, reacquisition/drift signals, recent transcript events, resume context, and ControlKeel instruction hierarchy for a session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_experience_index_tool do
    %{
      "name" => "ck_experience_index",
      "description" =>
        "List recent prior sessions in the same workspace and the read-only experience artifacts available for each run.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "session_limit" => %{"type" => ["integer", "string"]},
          "same_domain_only" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_experience_read_tool do
    %{
      "name" => "ck_experience_read",
      "description" =>
        "Read one prior-run artifact such as a session summary, audit log, trace packet, or proof summary from the workspace experience archive.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "artifact_type"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "source_session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "artifact_type" => %{
            "type" => "string",
            "enum" => ["session_summary", "audit_log", "trace_packet", "proof_summary"]
          }
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

  def ck_trace_packet_tool do
    %{
      "name" => "ck_trace_packet",
      "description" =>
        "Export a structured session or task trace packet with failure patterns and eval candidates for trace-centered improvement loops.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "events_limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_failure_clusters_tool do
    %{
      "name" => "ck_failure_clusters",
      "description" =>
        "Cluster recurring failure modes across recent session traces in the same workspace and return reusable eval candidates.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "session_limit" => %{"type" => ["integer", "string"]},
          "same_domain_only" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_skill_evolution_tool do
    %{
      "name" => "ck_skill_evolution",
      "description" =>
        "Synthesize a deduplicated skill-evolution packet from recent traces and recurring failure clusters, including anti-patterns, reinforced practices, and a ready-to-merge skill draft.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "session_limit" => %{"type" => ["integer", "string"]},
          "same_domain_only" => %{"type" => "boolean"},
          "current_skill_name" => %{"type" => "string"},
          "current_skill_content" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_fs_ls_tool do
    %{
      "name" => "ck_fs_ls",
      "description" =>
        "List files and directories inside the bound project root through a read-only virtual workspace surface.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "path" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_fs_read_tool do
    %{
      "name" => "ck_fs_read",
      "description" =>
        "Read a file from the bound project root through the read-only virtual workspace without using a sandbox.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "path"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "path" => %{"type" => "string"},
          "start_line" => %{"type" => ["integer", "string"]},
          "max_lines" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_find_tool do
    %{
      "name" => "ck_fs_find",
      "description" =>
        "Find files or directories by path fragment inside the bound project root through the read-only virtual workspace.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "path" => %{"type" => "string"},
          "query" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_grep_tool do
    %{
      "name" => "ck_fs_grep",
      "description" =>
        "Search file contents inside the bound project root through the read-only virtual workspace using grep-style semantics.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "path" => %{"type" => "string"},
          "query" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]},
          "ignore_case" => %{"type" => "boolean"},
          "fixed_strings" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_review_submit_tool do
    %{
      "name" => "ck_review_submit",
      "description" =>
        "Submit a governed plan, diff, or completion packet for browser review and execution gating, including recursive plan-refinement metadata for larger tasks.",
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
          "previous_review_id" => %{"type" => ["integer", "string"]},
          "plan_phase" => %{
            "type" => "string",
            "enum" => [
              "ticket",
              "research_packet",
              "design_options",
              "narrowed_decision",
              "implementation_plan",
              "code_backed_plan"
            ]
          },
          "research_summary" => %{"type" => "string"},
          "codebase_findings" => %{"type" => "array", "items" => %{"type" => "string"}},
          "prior_art_summary" => %{"type" => "string"},
          "options_considered" => %{"type" => "array", "items" => %{"type" => "string"}},
          "selected_option" => %{"type" => "string"},
          "rejected_options" => %{"type" => "array", "items" => %{"type" => "string"}},
          "implementation_steps" => %{"type" => "array", "items" => %{"type" => "string"}},
          "validation_plan" => %{"type" => "array", "items" => %{"type" => "string"}},
          "code_snippets" => %{"type" => "array", "items" => %{"type" => "string"}},
          "scope_estimate" => %{
            "type" => "object",
            "properties" => %{
              "files_touched_estimate" => %{"type" => ["integer", "string"]},
              "diff_size_estimate" => %{"type" => ["integer", "string"]},
              "architectural_scope" => %{"type" => "boolean"}
            }
          }
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

  def ck_regression_result_tool do
    %{
      "name" => "ck_regression_result",
      "description" =>
        "Record external regression-test evidence from systems such as Bug0 or Passmark so proof bundles and release readiness can account for it.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "engine", "flow_name", "outcome"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "engine" => %{"type" => "string"},
          "flow_name" => %{"type" => "string"},
          "outcome" => %{
            "type" => "string",
            "enum" => ["passed", "failed", "flaky", "skipped"]
          },
          "summary" => %{"type" => "string"},
          "environment" => %{"type" => "string"},
          "commit_sha" => %{"type" => "string"},
          "external_run_id" => %{"type" => "string"},
          "evidence" => %{"type" => "object"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_search_tool do
    %{
      "name" => "ck_memory_search",
      "description" =>
        "Search governed typed memory for the current session so agents can recover prior decisions, findings, and proof context explicitly.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "query" => %{"type" => "string"},
          "record_type" => %{"type" => "string", "enum" => ControlKeel.Memory.record_types()},
          "top_k" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_memory_record_tool do
    %{
      "name" => "ck_memory_record",
      "description" =>
        "Record a governed memory note or decision for the current session so future agents can explicitly retrieve it.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "memory"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "memory" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "summary" => %{"type" => "string"},
          "body" => %{"type" => "string"},
          "record_type" => %{"type" => "string", "enum" => ControlKeel.Memory.record_types()},
          "tags" => %{
            "oneOf" => [
              %{"type" => "array", "items" => %{"type" => "string"}},
              %{"type" => "string"}
            ]
          },
          "source_type" => %{"type" => "string"},
          "source_id" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_archive_tool do
    %{
      "name" => "ck_memory_archive",
      "description" =>
        "Archive a memory record when it is stale, superseded, or no longer safe to surface to future agents.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "memory_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "memory_id" => %{"type" => ["integer", "string"]}
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
          "workspace_id" => %{"type" => ["integer", "string"]},
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
    names = skill_names_for_ck_skill_load_enum()

    name_schema =
      %{
        "type" => "string",
        "description" =>
          "The skill name as returned by ck_skill_list. In MCP stdio mode, call ck_skill_list first; " <>
            "the enum is omitted so this handshake stays fast."
      }
      |> maybe_put_json_schema_enum(names)

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
          "name" => name_schema,
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

  defp ck_load_resources_tool do
    %{
      "name" => "ck_load_resources",
      "description" =>
        "Fallback for clients that do not support MCP resources. Load one or more CK resource URIs such as skills://<name>.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["uris"],
        "properties" => %{
          "uris" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Resource URIs to load, for example skills://controlkeel-governance"
          },
          "project_root" => %{"type" => "string"},
          "target" => %{"type" => "string"},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp current_skill_names do
    Registry.names(stdio_project_root(), trust_project_skills: true)
  end

  defp current_skills do
    Registry.catalog(stdio_project_root(), trust_project_skills: true)
  end

  defp stdio_project_root do
    case System.get_env("CK_PROJECT_ROOT") do
      v when is_binary(v) and v != "" ->
        v |> String.trim() |> Path.expand()

      _ ->
        File.cwd!()
    end
  end

  defp resource_schemas(_opts) do
    if mcp_stdio_mode?() do
      # Same Registry.catalog walk as tools/list — defer discovery to ck_skill_list /
      # ck_load_resources so resources/list stays instant under CK_MCP_MODE.
      []
    else
      Enum.map(current_skills(), fn skill ->
        %{
          "uri" => "skills://#{skill.name}",
          "name" => skill.name,
          "title" => skill.name,
          "description" => skill.description,
          "mimeType" => "text/markdown"
        }
      end)
    end
  end

  defp mcp_stdio_mode? do
    System.get_env("CK_MCP_MODE") in ~w(1 true TRUE yes YES)
  end

  defp skill_names_for_ck_skill_load_enum do
    if mcp_stdio_mode?() do
      []
    else
      current_skill_names()
    end
  end

  defp maybe_put_json_schema_enum(schema, []), do: schema

  defp maybe_put_json_schema_enum(schema, names) when is_list(names) do
    Map.put(schema, "enum", names)
  end

  defp load_resource(uri, params) do
    CkLoadResources.load_resource_uri(
      uri,
      Map.get(params, "project_root"),
      Map.get(params, "target"),
      Map.get(params, "session_id")
    )
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

  defp resource_response(id, {:ok, result}) do
    ok_response(id, %{
      "contents" => [
        %{
          "uri" => result["uri"],
          "mimeType" => result["mimeType"],
          "text" => result["text"]
        }
      ]
    })
  end

  defp resource_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  defp resource_response(id, {:error, reason}), do: error_response(id, -32000, inspect(reason))

  defp negotiate_mcp_protocol_version(v) when is_binary(v) and v != "" do
    if v in supported_mcp_protocol_versions(), do: v, else: default_mcp_protocol_version()
  end

  defp negotiate_mcp_protocol_version(_), do: default_mcp_protocol_version()

  defp supported_mcp_protocol_versions, do: ~w(2024-11-05 2025-03-26 2025-06-18)

  defp default_mcp_protocol_version, do: "2024-11-05"

  defp mcp_stdio_boot_gate(id) do
    case ControlKeel.Application.mcp_backend_boot_status() do
      :ready ->
        :ok

      :booting ->
        {:error,
         error_response(
           id,
           -32002,
           "ControlKeel backend is still starting (Repo and services); retry shortly."
         )}

      {:failed, reason} ->
        {:error,
         error_response(
           id,
           -32003,
           "ControlKeel failed to boot: #{inspect(reason)}"
         )}

      _ ->
        :ok
    end
  end

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
