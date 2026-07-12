defmodule ControlKeel.MCP.Protocol do
  @moduledoc false
  require Logger

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Governance.SecurityWorkflow
  alias ControlKeel.Skills.Registry
  alias ControlKeel.Governance.TrustBoundary

  alias ControlKeel.MCP.OutputSchemas
  alias ControlKeel.MCP.ToolGroups

  alias ControlKeel.MCP.Tools.{
    CkBudget,
    CkContext,
    CkContextPack,
    CkCopilot,
    CkExecuteCode,
    CkDelegate,
    CkExperienceIndex,
    CkExperienceRead,
    CkExperienceSearch,
    CkFsFind,
    CkFsGrep,
    CkFsLs,
    CkFsRead,
    CkFailureClusters,
    CkFinding,
    CkGoal,
    CkLoadResources,
    CkLoop,
    CkMemoryArchive,
    CkMemoryRecord,
    CkMemorySearch,
    CkMcpDiscover,
    CkObservability,
    CkSkillEvolution,
    CkReviewFeedback,
    CkRegressionResult,
    CkReviewStatus,
    CkReviewSubmit,
    CkRoute,
    CkTracePacket,
    CkSkillList,
    CkSkillLoad,
    CkSkillValidate,
    CkValidate,
    CkCostOptimizer,
    CkDeploymentAdvisor,
    CkOutcomeTracker,
    CkRollback,
    CkSessionDigest,
    CkTokenAudit,
    CkToolHealth,
    CkWorktreeList,
    CkWorktreeSwitch,
    CkExternalService,
    CkWorkspaceAgent,
    CkCheckpointCreate,
    CkCheckpointRestore,
    CkCheckpointList,
    CkResultPeek,
    CkGitDiff,
    CkGitCommit,
    CkGitStatus
  }

  defp server_info do
    %{
      "name" => "controlkeel",
      "version" => ControlKeel.CLI.version()
    }
  end

  def handle_json(payload, opts \\ []) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, []} ->
        error_response(nil, -32600, "Invalid Request")

      {:ok, requests} when is_list(requests) ->
        json_rpc_batch_responses(requests, opts)

      {:ok, request} when is_map(request) ->
        handle_request(request, opts)

      {:ok, _} ->
        error_response(nil, -32600, "Invalid Request")

      {:error, error} ->
        error_response(nil, -32700, "Parse error: #{Exception.message(error)}")
    end
  end

  # JSON-RPC 2.0 batch + MCP: clients MAY batch; servers MUST accept batches.
  # A lone Array was previously routed to handle_request/2 and fell through to
  # "Invalid Request" with id null, which breaks Cursor's handshake (20s timeout).
  defp json_rpc_batch_responses(requests, opts) when is_list(requests) do
    responses =
      Enum.flat_map(requests, fn
        %{"jsonrpc" => "2.0"} = req ->
          if json_rpc_notification?(req) do
            _ = handle_request(req, opts)
            []
          else
            [handle_request(req, opts)]
          end

        _not_object ->
          [error_response(nil, -32600, "Invalid Request")]
      end)

    case responses do
      [] -> :no_response
      list when is_list(list) -> list
    end
  end

  defp json_rpc_notification?(req) when is_map(req), do: not Map.has_key?(req, "id")

  def handle_request(request, opts \\ [])

  def handle_request(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id} = req, _opts) do
    try do
      requested = get_in(req, ["params", "protocolVersion"])
      negotiated = negotiate_mcp_protocol_version(requested)

      ok_response(id, %{
        "protocolVersion" => negotiated,
        "capabilities" => %{
          "tools" => %{"listChanged" => false},
          "resources" => %{"subscribe" => false, "listChanged" => false}
        },
        "serverInfo" => server_info()
      })
    rescue
      e ->
        Logger.error("MCP initialize failed: #{Exception.message(e)}")
        # Return a basic successful response even if something fails
        ok_response(id, %{
          "protocolVersion" => default_mcp_protocol_version(),
          "capabilities" => %{
            "tools" => %{"listChanged" => false},
            "resources" => %{"subscribe" => false, "listChanged" => false}
          },
          "serverInfo" => server_info()
        })
    catch
      :exit, e ->
        Logger.error("MCP initialize exited: #{inspect(e)}")

        ok_response(id, %{
          "protocolVersion" => default_mcp_protocol_version(),
          "capabilities" => %{
            "tools" => %{"listChanged" => false},
            "resources" => %{"subscribe" => false, "listChanged" => false}
          },
          "serverInfo" => server_info()
        })

      :throw, e ->
        Logger.error("MCP initialize threw: #{inspect(e)}")

        ok_response(id, %{
          "protocolVersion" => default_mcp_protocol_version(),
          "capabilities" => %{
            "tools" => %{"listChanged" => false},
            "resources" => %{"subscribe" => false, "listChanged" => false}
          },
          "serverInfo" => server_info()
        })
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _opts),
    do: :no_response

  def handle_request(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, opts) do
    try do
      ok_response(id, %{"tools" => tool_schemas(opts)})
    rescue
      e ->
        Logger.error("MCP tools/list failed: #{Exception.message(e)}")
        # Return core tools as a safe fallback
        ok_response(id, %{
          "tools" =>
            OutputSchemas.inject_all([
              ck_validate_tool(),
              ck_context_tool(),
              ck_finding_tool(),
              ck_memory_search_tool(),
              ck_memory_record_tool(),
              ck_budget_tool()
            ])
        })
    catch
      :exit, e ->
        Logger.error("MCP tools/list exited: #{inspect(e)}")

        ok_response(id, %{
          "tools" =>
            OutputSchemas.inject_all([
              ck_validate_tool(),
              ck_context_tool(),
              ck_finding_tool(),
              ck_memory_search_tool(),
              ck_memory_record_tool(),
              ck_budget_tool()
            ])
        })

      :throw, e ->
        Logger.error("MCP tools/list threw: #{inspect(e)}")

        ok_response(id, %{
          "tools" =>
            OutputSchemas.inject_all([
              ck_validate_tool(),
              ck_context_tool(),
              ck_finding_tool(),
              ck_memory_search_tool(),
              ck_memory_record_tool(),
              ck_budget_tool()
            ])
        })
    end
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

  @tool_groups ToolGroups.tool_groups_map()

  # Tools that must survive adaptive tool-group filtering because they are part of
  # the required CK tool contract surfaced by `controlkeel attach`. Kept in sync
  # with the `base ++ [...]` skill tools appended in tool_schemas/1.
  @always_exposed_tools ["ck_skill_list", "ck_skill_load", "ck_skill_validate"]

  def tool_schemas(opts \\ []) do
    try do
      base = [
        ck_validate_tool(),
        ck_execute_code_tool(),
        ck_context_tool(),
        ck_context_pack_tool(),
        ck_observability_tool(),
        ck_experience_index_tool(),
        ck_experience_read_tool(),
        ck_experience_search_tool(),
        ck_trace_packet_tool(),
        ck_failure_clusters_tool(),
        ck_tool_health_tool(),
        ck_skill_evolution_tool(),
        ck_fs_ls_tool(),
        ck_fs_read_tool(),
        ck_fs_find_tool(),
        ck_fs_grep_tool(),
        ck_worktree_list_tool(),
        ck_worktree_switch_tool(),
        ck_checkpoint_create_tool(),
        ck_checkpoint_restore_tool(),
        ck_checkpoint_list_tool(),
        ck_git_diff_tool(),
        ck_git_commit_tool(),
        ck_git_status_tool(),
        ck_finding_tool(),
        ck_review_submit_tool(),
        ck_review_status_tool(),
        ck_review_feedback_tool(),
        ck_regression_result_tool(),
        ck_memory_search_tool(),
        ck_memory_record_tool(),
        ck_goal_tool(),
        ck_memory_archive_tool(),
        ck_budget_tool(),
        ck_route_tool(),
        ck_delegate_tool(),
        ck_result_peek_tool(),
        ck_cost_optimizer_tool(),
        ck_deployment_advisor_tool(),
        ck_outcome_tracker_tool(),
        ck_load_resources_tool(),
        ck_mcp_discover_tool(),
        ck_token_audit_tool(),
        ck_attach_tool(),
        ck_session_digest_tool(),
        ck_loop_tool(),
        ck_rollback_tool(),
        ck_workspace_agent_tool(),
        ck_copilot_tool(),
        ck_external_service_tool(),
        ck_task_tool(),
        ck_session_tool()
      ]

      # Always expose ck_skill_list / ck_skill_load / ck_skill_validate. Do not call Registry here: a full
      # catalog walk (every agent skill dir under $HOME) can take 10–30s and blocks this
      # process while Cursor expects tools/list under a ~20s connect budget.
      tools =
        OutputSchemas.inject_all(
          base ++ [ck_skill_list_tool(), ck_skill_load_tool(), ck_skill_validate_tool()]
        )

      # Apply tool_names filtering (takes precedence over tool_groups and adaptive mode)
      # This is used by hosted mode for security - explicit tool whitelisting
      filtered_tools =
        case Keyword.get(opts, :tool_names) do
          names when is_list(names) ->
            Enum.filter(tools, &(&1["name"] in names))

          _ ->
            # Apply tool group filtering — opts take precedence over env var.
            # :all in opts means "force all tools, bypass env var" (used by audit/measurement callers).
            # When opts does not specify tool_groups, fall back to env var / app config.
            # NEW: Check for per-project adaptive preferences and enable auto-expansion
            project_root = Keyword.get(opts, :project_root)
            adaptive_mode = Keyword.get(opts, :adaptive, true)

            effective_groups =
              case Keyword.fetch(opts, :tool_groups) do
                {:ok, :all} ->
                  :all

                {:ok, groups} ->
                  groups

                :error ->
                  if adaptive_mode && project_root do
                    adaptive_tool_groups(project_root)
                  else
                    env_tool_groups() || :all
                  end
              end

            case effective_groups do
              :all ->
                tools

              groups when is_list(groups) ->
                # The skill tools are part of the required CK tool contract that
                # `controlkeel attach` advertises (ck_skill_list / ck_skill_load /
                # ck_skill_validate). Adaptive group selection must never drop them,
                # otherwise a plain project (no mix.exs/package.json/AGENTS.md) gets
                # core+governance+git only and the declared "Required CK tools" go
                # missing from tools/list. Union them back so the "always expose"
                # intent above holds regardless of which groups are selected.
                allowed_tool_names =
                  groups
                  |> Enum.flat_map(fn group -> Map.get(@tool_groups, group, []) end)
                  |> Enum.concat(@always_exposed_tools)
                  |> MapSet.new()

                filtered = Enum.filter(tools, &(&1["name"] in allowed_tool_names))

                if adaptive_mode && project_root do
                  log_tool_group_decision(project_root, groups, length(tools), length(filtered))
                end

                filtered

              _ ->
                tools
            end
        end

      filtered_tools
    rescue
      e ->
        # If anything fails during tool schema generation, log it and return a safe fallback
        Logger.error("MCP tool schema generation failed: #{Exception.message(e)}")

        OutputSchemas.inject_all([
          ck_validate_tool(),
          ck_context_tool(),
          ck_finding_tool(),
          ck_memory_search_tool(),
          ck_memory_record_tool(),
          ck_budget_tool()
        ])
    catch
      :exit, e ->
        Logger.error("MCP tool schema generation exited: #{inspect(e)}")

        OutputSchemas.inject_all([
          ck_validate_tool(),
          ck_context_tool(),
          ck_finding_tool(),
          ck_memory_search_tool(),
          ck_memory_record_tool(),
          ck_budget_tool()
        ])

      :throw, e ->
        Logger.error("MCP tool schema generation threw: #{inspect(e)}")

        OutputSchemas.inject_all([
          ck_validate_tool(),
          ck_context_tool(),
          ck_finding_tool(),
          ck_memory_search_tool(),
          ck_memory_record_tool(),
          ck_budget_tool()
        ])
    end
  end

  def dispatch_tool(tool_name, arguments) do
    # Track usage for adaptive learning
    project_root = stdio_project_root()
    track_tool_usage(project_root, tool_name)

    # Call the actual tool implementation
    do_dispatch_tool(tool_name, arguments)
  end

  defp do_dispatch_tool("ck_validate", arguments), do: CkValidate.call(arguments)
  defp do_dispatch_tool("ck_execute_code", arguments), do: CkExecuteCode.call(arguments)
  defp do_dispatch_tool("ck_context", arguments), do: CkContext.call(arguments)
  defp do_dispatch_tool("ck_context_pack", arguments), do: CkContextPack.call(arguments)
  defp do_dispatch_tool("ck_observability", arguments), do: CkObservability.call(arguments)
  defp do_dispatch_tool("ck_experience_index", arguments), do: CkExperienceIndex.call(arguments)
  defp do_dispatch_tool("ck_experience_read", arguments), do: CkExperienceRead.call(arguments)
  defp do_dispatch_tool("ck_experience_search", arguments), do: CkExperienceSearch.call(arguments)
  defp do_dispatch_tool("ck_trace_packet", arguments), do: CkTracePacket.call(arguments)
  defp do_dispatch_tool("ck_failure_clusters", arguments), do: CkFailureClusters.call(arguments)
  defp do_dispatch_tool("ck_tool_health", arguments), do: CkToolHealth.call(arguments)
  defp do_dispatch_tool("ck_skill_evolution", arguments), do: CkSkillEvolution.call(arguments)
  defp do_dispatch_tool("ck_fs_ls", arguments), do: CkFsLs.call(arguments)
  defp do_dispatch_tool("ck_fs_read", arguments), do: CkFsRead.call(arguments)
  defp do_dispatch_tool("ck_fs_find", arguments), do: CkFsFind.call(arguments)
  defp do_dispatch_tool("ck_fs_grep", arguments), do: CkFsGrep.call(arguments)
  defp do_dispatch_tool("ck_worktree_list", arguments), do: CkWorktreeList.call(arguments)
  defp do_dispatch_tool("ck_worktree_switch", arguments), do: CkWorktreeSwitch.call(arguments)
  defp do_dispatch_tool("ck_checkpoint_create", arguments), do: CkCheckpointCreate.call(arguments)

  defp do_dispatch_tool("ck_checkpoint_restore", arguments),
    do: CkCheckpointRestore.call(arguments)

  defp do_dispatch_tool("ck_checkpoint_list", arguments), do: CkCheckpointList.call(arguments)
  defp do_dispatch_tool("ck_result_peek", arguments), do: CkResultPeek.call(arguments)
  defp do_dispatch_tool("ck_git_diff", arguments), do: CkGitDiff.call(arguments)
  defp do_dispatch_tool("ck_git_commit", arguments), do: CkGitCommit.call(arguments)
  defp do_dispatch_tool("ck_git_status", arguments), do: CkGitStatus.call(arguments)
  defp do_dispatch_tool("ck_finding", arguments), do: CkFinding.call(arguments)
  defp do_dispatch_tool("ck_review_submit", arguments), do: CkReviewSubmit.call(arguments)
  defp do_dispatch_tool("ck_review_status", arguments), do: CkReviewStatus.call(arguments)
  defp do_dispatch_tool("ck_review_feedback", arguments), do: CkReviewFeedback.call(arguments)
  defp do_dispatch_tool("ck_regression_result", arguments), do: CkRegressionResult.call(arguments)
  defp do_dispatch_tool("ck_memory_search", arguments), do: CkMemorySearch.call(arguments)
  defp do_dispatch_tool("ck_memory_record", arguments), do: CkMemoryRecord.call(arguments)
  defp do_dispatch_tool("ck_goal", arguments), do: CkGoal.call(arguments)
  defp do_dispatch_tool("ck_memory_archive", arguments), do: CkMemoryArchive.call(arguments)
  defp do_dispatch_tool("ck_budget", arguments), do: CkBudget.call(arguments)
  defp do_dispatch_tool("ck_route", arguments), do: CkRoute.call(arguments)
  defp do_dispatch_tool("ck_delegate", arguments), do: CkDelegate.call(arguments)
  defp do_dispatch_tool("ck_skill_list", arguments), do: CkSkillList.call(arguments)
  defp do_dispatch_tool("ck_skill_load", arguments), do: CkSkillLoad.call(arguments)
  defp do_dispatch_tool("ck_skill_validate", arguments), do: CkSkillValidate.call(arguments)
  defp do_dispatch_tool("ck_load_resources", arguments), do: CkLoadResources.call(arguments)
  defp do_dispatch_tool("ck_mcp_discover", arguments), do: CkMcpDiscover.call(arguments)
  defp do_dispatch_tool("ck_cost_optimizer", arguments), do: CkCostOptimizer.call(arguments)

  defp do_dispatch_tool("ck_deployment_advisor", arguments),
    do: CkDeploymentAdvisor.call(arguments)

  defp do_dispatch_tool("ck_outcome_tracker", arguments), do: CkOutcomeTracker.call(arguments)
  defp do_dispatch_tool("ck_token_audit", arguments), do: CkTokenAudit.call(arguments)

  defp do_dispatch_tool("ck_attach", arguments),
    do: ControlKeel.MCP.Tools.CkAttach.call(arguments)

  defp do_dispatch_tool("ck_session_digest", arguments), do: CkSessionDigest.call(arguments)
  defp do_dispatch_tool("ck_loop", arguments), do: CkLoop.call(arguments)
  defp do_dispatch_tool("ck_rollback", arguments), do: CkRollback.call(arguments)
  defp do_dispatch_tool("ck_workspace_agent", arguments), do: CkWorkspaceAgent.call(arguments)
  defp do_dispatch_tool("ck_copilot", arguments), do: CkCopilot.call(arguments)
  defp do_dispatch_tool("ck_external_service", arguments), do: CkExternalService.call(arguments)
  defp do_dispatch_tool("ck_task", arguments), do: ControlKeel.MCP.Tools.CkTask.call(arguments)

  defp do_dispatch_tool("ck_session", arguments),
    do: ControlKeel.MCP.Tools.CkSession.call(arguments)

  defp do_dispatch_tool(unknown, _arguments),
    do: {:error, {:invalid_arguments, "Unknown tool: #{unknown}"}}

  defp track_tool_usage(project_root, tool_name) do
    # Track usage asynchronously to avoid blocking tool calls
    Task.start(fn ->
      ControlKeel.MCP.ToolGroupTracker.track_tool_usage(project_root, tool_name)
    end)
  end

  def tool_groups, do: ToolGroups.groups()

  def ck_validate_tool do
    %{
      "name" => "ck_validate",
      "description" =>
        "Validate proposed code, config, shell commands, or text against CK policy before execution. Read-only — no changes are applied to the project. Returns a validation result with any policy violations as findings. " <>
          "content is required. kind classifies the artifact (code/config/shell/text) for policy routing. " <>
          "source_type identifies the content's origin (developer, tool_output, human_review, issue, pull_request, web) for trust-boundary checks; untrusted sources receive stricter scrutiny. " <>
          "domain_pack applies a domain-specific policy pack (e.g., hipaa, owasp). " <>
          "requested_capabilities declares what the content needs (network, filesystem, shell, deploy) so the trust boundary can evaluate the request. " <>
          "Call ck_validate before writing files, running shell commands, or executing generated code. If validation returns blocked findings, do not proceed — use ck_finding to record them.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{
            "type" => "string",
            "description" =>
              "The content to validate or process: source code, config text, shell command, or freeform text."
          },
          "path" => %{
            "type" => "string",
            "description" => "File or directory path relative to the project root."
          },
          "kind" => %{
            "type" => "string",
            "enum" => ["code", "config", "shell", "text"],
            "description" => "Artifact kind classification for validation routing."
          },
          "domain_pack" => %{
            "type" => "string",
            "enum" => Domains.supported_packs(),
            "description" => "Domain-specific policy pack to apply during validation."
          },
          "policy_packs" => %{
            "type" => "array",
            "items" => %{"type" => "string", "enum" => ["ai_tools"]},
            "description" =>
              "Additional explicit policy packs to apply. Currently supports ai_tools for AI tool configuration review."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "source_type" => %{
            "type" => "string",
            "enum" => TrustBoundary.source_types(),
            "description" =>
              "Origin category of the record (e.g., developer, tool_output, human_review)."
          },
          "trust_level" => %{"type" => "string", "enum" => TrustBoundary.trust_levels()},
          "intended_use" => %{
            "type" => "string",
            "enum" => TrustBoundary.intended_uses(),
            "description" => "How the validated content will be used after validation."
          },
          "security_workflow_phase" => %{
            "type" => "string",
            "enum" => CkValidate.workflow_phase_values(),
            "description" =>
              "Canonical workflow phase. Compatibility aliases such as `preflight`, `analysis`, and `pre_edit` are accepted and normalized."
          },
          "artifact_type" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.artifact_types() ++ ["instruction", "text"],
            "description" =>
              "Canonical artifact type. Compatibility aliases `instruction` and `text` are accepted and normalized to `source`."
          },
          "target_scope" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.target_scopes(),
            "description" => "Deployment scope of the artifact being validated."
          },
          "requested_capabilities" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => TrustBoundary.capabilities(),
              "description" =>
                "Capabilities the content intends to exercise, used for trust-boundary checks."
            }
          }
        }
      }
    }
  end

  def ck_execute_code_tool do
    %{
      "name" => "ck_execute_code",
      "description" =>
        "Execute generated code only inside a configured non-local sandbox. Defaults to Docker, denies network/filesystem/secrets/shell/deploy, validates source first, and supports dry_run for planning.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["code"],
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Generated source code to validate and execute in the sandbox."
          },
          "language" => %{
            "type" => "string",
            "enum" => ["javascript", "python"],
            "description" => "Runtime language. Defaults to javascript."
          },
          "sandbox" => %{
            "type" => "string",
            "enum" => ["docker"],
            "description" =>
              "Execution sandbox. Local host execution is intentionally unsupported."
          },
          "dry_run" => %{
            "type" => "boolean",
            "description" =>
              "When true, validate and plan without executing the actual operation."
          },
          "timeout_ms" => %{
            "type" => ["integer", "string"],
            "description" => "Timeout in milliseconds."
          },
          "max_output_bytes" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum size in bytes for captured output."
          },
          "risk_tier" => %{
            "type" => "string",
            "enum" => ["low", "medium", "moderate", "high", "critical"],
            "description" => "Security sensitivity of the task. Default: medium."
          },
          "requested_capabilities" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => [
                "read_api",
                "write_api",
                "network",
                "filesystem",
                "secrets",
                "shell",
                "deploy"
              ]
            }
          },
          "network_allowlist" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "description" => "List of hostnames or URLs the sandbox is permitted to access."
            }
          },
          "allowed_env_vars" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "description" => "Host environment variable names to expose inside the sandbox."
            },
            "description" =>
              "List of environment variable names to expose from the host environment into the sandbox. Explicit env vars take precedence over host env vars. If empty, no host environment variables are exposed."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_context_tool do
    %{
      "name" => "ck_context",
      "description" =>
        "Fetch the full governed session state: mission, budget, active findings, proof summary, planning context, workspace snapshot, drift signals, recent transcript events, resume packet, and ControlKeel instruction hierarchy. Read-only. " <>
          "detail_level compact (default) returns a token-efficient summary; use full only when raw workspace, resume, or transcript payloads are required. " <>
          "session_id defaults to the active bound session; pass project_root to resolve it automatically. " <>
          "Call ck_context at the start of every task to reacquire state. " <>
          "Prefer ck_context_pack when you need a focused, citation-enriched bundle for a specific retrieval query rather than the full session snapshot.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "detail_level" => %{
            "type" => "string",
            "enum" => ["compact", "full"],
            "description" =>
              "Use compact by default to reduce token usage; request full only when raw workspace/resume/transcript payloads are needed."
          }
        }
      }
    }
  end

  def ck_context_pack_tool do
    %{
      "name" => "ck_context_pack",
      "description" =>
        "Build a compact, citation-enriched context bundle for the current session and task by combining task facts, proof state, resume highlights, and ranked memory excerpts. Read-only. " <>
          "query is an optional retrieval query; when omitted, ControlKeel synthesizes one from the current task title and session context. " <>
          "top_k controls how many memory hits to include (default 5). detail_level compact (default) keeps the bundle token-efficient. " <>
          "Prefer ck_context_pack over ck_context when you need a focused, query-driven bundle for a specific sub-task rather than the full session snapshot. " <>
          "Use ck_context at the start of a session for full mission state; use ck_context_pack mid-task to fetch targeted prior knowledge.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "query" => %{
            "type" => "string",
            "description" =>
              "Optional explicit retrieval query. When omitted, ControlKeel synthesizes one from the current task and session."
          },
          "top_k" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of top-ranked results to return."
          },
          "detail_level" => %{"type" => "string", "enum" => ["compact", "full"]}
        }
      }
    }
  end

  def ck_observability_tool do
    %{
      "name" => "ck_observability",
      "description" =>
        "Read local observability reports for sessions, loop status, problems, memory, costs, trends, evals, generated benchmarks, history, and advisory promotion candidates. Read-only: no benchmark execution, draft approval, materialization, or promotion mutation.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "report" => %{
            "type" => "string",
            "enum" => CkObservability.reports(),
            "description" => "Report to return; defaults to overview."
          },
          "surface" => %{
            "type" => "string",
            "enum" => CkObservability.reports(),
            "description" => "Compatibility alias for report."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "workspace_id" => %{
            "type" => ["integer", "string"],
            "description" => "Workspace identifier for cross-session scope."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of results to return."
          },
          "days" => %{
            "type" => ["integer", "string"],
            "description" => "Number of days to look back for trend analysis."
          },
          "stale_days" => %{
            "type" => ["integer", "string"],
            "description" => "Threshold in days for marking entries as stale."
          },
          "by" => %{"type" => "string", "enum" => ["model", "tool", "source", "provider"]}
        }
      }
    }
  end

  def ck_experience_index_tool do
    %{
      "name" => "ck_experience_index",
      "description" =>
        "List recent prior sessions in the same workspace and the read-only experience artifacts available for each run. " <>
          "Pass `query` for freeform keyword search across session titles, task titles, and finding descriptions — " <>
          "useful for questions like 'has this deployment pattern caused a blocked finding before?'",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "session_limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of sessions to analyze."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "same_domain_only" => %{
            "type" => "boolean",
            "description" => "When true, restrict results to sessions in the same domain."
          },
          "query" => %{
            "type" => "string",
            "description" =>
              "Freeform keyword filter applied to session title, task titles, and finding descriptions. " <>
                "All tokens must match (AND logic). Omit to return all recent sessions."
          }
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
        "required" => ["artifact_type"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "source_session_id" => %{
            "type" => ["integer", "string"],
            "description" => "Session ID of the prior run to read artifacts from."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "artifact_type" => %{
            "type" => "string",
            "enum" => ["session_summary", "audit_log", "trace_packet", "proof_summary"]
          }
        }
      }
    }
  end

  def ck_experience_search_tool do
    %{
      "name" => "ck_experience_search",
      "description" =>
        "Freeform full-text search across findings and tasks within the current workspace. Returns ranked results with citations. Useful for questions like 'has this deployment pattern caused a blocked finding before?' or 'what did we do about the SQL performance issue?'",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "query" => %{
            "type" => "string",
            "description" =>
              "Freeform search query. Supports natural language and keyword search."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of results to return. Defaults to 10, maximum 20."
          }
        }
      }
    }
  end

  def ck_finding_tool do
    %{
      "name" => "ck_finding",
      "description" =>
        "Record or disposition a governed finding. mode=create (default) persists a finding with a ruling decision (allow, warn, block, escalate_to_human); findings are the durable audit trail in ControlKeel. " <>
          "mode=resolve|dismiss|escalate disposition EXISTING findings so the agent that created them can also clear them: pass `finding_id` for a single finding, or `rule_id`/`category`/`status` to bulk-disposition all matching active findings in the session (resolve->approved, dismiss->rejected, escalate->escalated). " <>
          "Write operation. For create, required fields are session_id, category, severity, rule_id, plain_message; decision defaults to warn, use allow for an approved exception (which also auto-resolves matching open/blocked findings). " <>
          "Returns finding_id + status for create, or disposed_count + disposed_finding_ids for disposition. " <>
          "Use ck_finding to record and clear policy findings; use ck_memory_record for general knowledge not tied to a policy rule.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "category" => %{
            "type" => "string",
            "description" => "Finding category (e.g., security, compliance, performance)."
          },
          "severity" => %{
            "type" => "string",
            "description" => "Severity level (e.g., critical, high, medium, low)."
          },
          "rule_id" => %{
            "type" => "string",
            "description" => "Policy rule identifier that triggered this finding."
          },
          "plain_message" => %{
            "type" => "string",
            "description" => "Human-readable finding description."
          },
          "title" => %{
            "type" => "string",
            "description" => "Human-readable title for display and search."
          },
          "decision" => %{
            "type" => "string",
            "enum" => ["allow", "warn", "block", "escalate_to_human"],
            "description" => "Governance decision: allow, warn, block, or escalate to human."
          },
          "metadata" => %{"type" => "object"},
          "mode" => %{
            "type" => "string",
            "enum" => ["create", "resolve", "dismiss", "escalate"],
            "description" =>
              "create (default) records a finding. resolve/dismiss/escalate disposition existing findings, by `finding_id` (single) or `rule_id`/`category`/`status` (bulk)."
          },
          "finding_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Target finding id for single disposition (resolve/dismiss/escalate modes)."
          },
          "status" => %{
            "type" => "string",
            "description" =>
              "Bulk disposition filter: only findings currently in this status are dispositioned (e.g. blocked, open, escalated)."
          },
          "reason" => %{
            "type" => "string",
            "description" => "Reason recorded on the finding(s) when dismissing."
          }
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
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
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
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "session_limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of sessions to analyze."
          },
          "same_domain_only" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_tool_health_tool do
    %{
      "name" => "ck_tool_health",
      "description" =>
        "Analyze governance coverage across recent sessions in the workspace — which CK governance tools (ck_validate, ck_review_submit, ck_budget, ck_memory_record, ck_goal) are load-bearing, active, low-usage, or unused — and return actionable recommendations for gaps.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "session_limit" => %{
            "type" => ["integer", "string"],
            "description" => "Number of recent sessions to analyze. Defaults to 10."
          }
        }
      }
    }
  end

  def ck_skill_evolution_tool do
    %{
      "name" => "ck_skill_evolution",
      "description" =>
        "Synthesize a deduplicated skill-evolution packet from recent traces and recurring failure clusters, including anti-patterns, reinforced practices, and a ready-to-merge skill draft. Set validate_only=true to run the Self-Harness validation stage (held-in/held-out + regression) without writing. Set install=true to validate and then materialize the draft into .agents/skills/<name>/SKILL.md under project_root, preserving the previous file as .bak.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem. Required for install mode."
          },
          "session_limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of sessions to analyze."
          },
          "same_domain_only" => %{
            "type" => "boolean",
            "description" => "When true, restrict results to sessions in the same domain."
          },
          "current_skill_name" => %{
            "type" => "string",
            "description" => "Name of the existing skill to compare against for evolution."
          },
          "current_skill_content" => %{"type" => "string"},
          "validate_only" => %{
            "type" => "boolean",
            "description" =>
              "When true, run the Self-Harness validation stage (static, held-in, held-out, regression) and return the verdict without writing any files."
          },
          "install" => %{
            "type" => "boolean",
            "description" =>
              "When true, validate the packet and, only if accepted, write the suggested skill document to .agents/skills/<name>/SKILL.md under project_root. The previous file is preserved as <path>.bak for rollback. Requires project_root."
          }
        }
      }
    }
  end

  def ck_fs_ls_tool do
    %{
      "name" => "ck_fs_ls",
      "description" =>
        "List files and directories inside the bound project root. Read-only — no files are modified. " <>
          "path is a relative directory path to list; omit to list the project root. " <>
          "Use ck_fs_ls to browse directory structure. Use ck_fs_find to locate files by name fragment. Use ck_fs_read to read a specific file. Use ck_fs_grep to search file contents.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "path" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_fs_read_tool do
    %{
      "name" => "ck_fs_read",
      "description" =>
        "Read a file from the bound project root. Read-only — no files are modified or created. " <>
          "path is required and must be relative to the project root (e.g., lib/my_module.ex). " <>
          "start_line (1-indexed) and max_lines enable windowed reads for large files. Omit both to read the entire file. " <>
          "Use ck_fs_read to inspect a file at a known path. Use ck_fs_find to locate a file by name fragment. Use ck_fs_grep to search inside files by content pattern. Use ck_fs_ls to list directory contents.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["path"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "path" => %{
            "type" => "string",
            "description" => "File or directory path relative to the project root."
          },
          "start_line" => %{
            "type" => ["integer", "string"],
            "description" => "1-indexed starting line number for partial file reads."
          },
          "max_lines" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_find_tool do
    %{
      "name" => "ck_fs_find",
      "description" =>
        "Find files or directories whose path contains a given fragment, searching within the bound project root. Read-only — no files are modified. " <>
          "query is the path fragment or glob pattern to match against file and directory names. " <>
          "path scopes the search to a subdirectory (relative to project root); omit to search the entire project. " <>
          "limit caps the number of results (default 50). " <>
          "Use ck_fs_find to locate files by name or path. Use ck_fs_grep to search by file content. Use ck_fs_read to read a file at a known path.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "path" => %{
            "type" => "string",
            "description" => "File or directory path relative to the project root."
          },
          "query" => %{
            "type" => "string",
            "description" => "Search query string for filtering or full-text search."
          },
          "limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_grep_tool do
    %{
      "name" => "ck_fs_grep",
      "description" =>
        "Search file contents inside the bound project root using grep-style pattern matching. Read-only — no files are modified. " <>
          "query uses fixed-string search by default; set fixed_strings: false to treat it as a regex. " <>
          "Scope the search with path (a relative directory or glob); omit to search the entire project. " <>
          "Returns matching lines with file path and line numbers. limit caps results (default 50). " <>
          "Use ck_fs_grep to find code patterns or strings inside files. Use ck_fs_find to locate files by name fragment. Use ck_fs_read to read a specific file by path.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "path" => %{
            "type" => "string",
            "description" => "File or directory path relative to the project root."
          },
          "query" => %{
            "type" => "string",
            "description" => "Search query string for filtering or full-text search."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of results to return."
          },
          "ignore_case" => %{
            "type" => "boolean",
            "description" => "When true, perform case-insensitive matching."
          },
          "fixed_strings" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_worktree_list_tool do
    %{
      "name" => "ck_worktree_list",
      "description" =>
        "List all git worktrees in the current repository with their branch, HEAD, and status information.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_worktree_switch_tool do
    %{
      "name" => "ck_worktree_switch",
      "description" =>
        "Switch the current session to a different git worktree and update session metadata accordingly.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["worktree_path"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "worktree_path" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_checkpoint_create_tool do
    %{
      "name" => "ck_checkpoint_create",
      "description" =>
        "Create a workspace checkpoint capturing git state, workspace context, and metadata for migration or rollback.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["task_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "type" => %{
            "type" => "string",
            "enum" => ["workspace_snapshot", "git_state", "dependency_state", "task_milestone"],
            "description" => "Type classification for the operation."
          },
          "summary" => %{
            "type" => "string",
            "description" => "Brief human-readable summary of the record."
          },
          "created_by" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_checkpoint_restore_tool do
    %{
      "name" => "ck_checkpoint_restore",
      "description" =>
        "Restore session state from a previous checkpoint, updating session metadata with checkpoint information.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["checkpoint_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "checkpoint_id" => %{
            "type" => ["integer", "string"],
            "description" => "Unique identifier of the checkpoint to restore."
          },
          "strict" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_checkpoint_list_tool do
    %{
      "name" => "ck_checkpoint_list",
      "description" => "List all checkpoints for a session, optionally filtered by type.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "type" => %{
            "type" => "string",
            "enum" => ["workspace_snapshot", "git_state", "dependency_state", "task_milestone"],
            "description" => "Type classification for the operation."
          },
          "limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_diff_tool do
    %{
      "name" => "ck_git_diff",
      "description" =>
        "Generate a git diff and run CK validation on the resulting diff. Read-only — no commits are created. " <>
          "base_ref and head_ref are git refs (branch names, commit SHAs, or tags); omit both or pass empty strings to diff the working tree against HEAD. " <>
          "Returns the diff text and any CK validation findings raised against it. " <>
          "Use ck_git_diff to review changes before committing or submitting a review. Use ck_git_status for a summary without the full diff. Use ck_git_commit to create the commit after reviewing.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "base_ref" => %{
            "type" => "string",
            "description" => "Base git ref (commit, branch, or tag) for the diff."
          },
          "head_ref" => %{
            "type" => "string",
            "description" => "Head git ref (commit, branch, or tag) for the diff."
          },
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_commit_tool do
    %{
      "name" => "ck_git_commit",
      "description" =>
        "Validate a commit message against CK governance policy and execute git commit if validation passes and no findings are blocked. " <>
          "Write operation — creates a git commit in the repository when validation succeeds. " <>
          "Returns validation result, any blocked findings, and the commit SHA on success. " <>
          "If blocked findings exist, the commit is not created and the findings are returned for remediation. " <>
          "Use ck_git_status first to confirm governance state, then ck_git_commit to create the commit. " <>
          "Does not push to remote — use git push separately after commit.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["message"],
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "message" => %{"type" => "string", "description" => "Commit message text."},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_status_tool do
    %{
      "name" => "ck_git_status",
      "description" =>
        "Get git working tree status correlated with CK governance findings for the current session. Returns staged, unstaged, and untracked files alongside any blocked or open findings from ck_validate or ck_review_submit. Read-only and side-effect free — no findings are created or modified. Use before ck_git_commit to verify governance state. Prefer ck_git_diff when you need the actual diff content; prefer ck_git_commit when ready to commit.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_review_submit_tool do
    %{
      "name" => "ck_review_submit",
      "description" =>
        "Submit a governed plan, diff, or completion packet for human review and execution gating. Write operation — creates a review record and returns a review_id and browser URL. " <>
          "review_type controls what is being submitted: plan (before implementation), diff (before merging), or completion (task done). " <>
          "submission_body is the full content: plan text, diff, or completion description. " <>
          "For iterative plan refinement, pass previous_review_id and plan_phase (ticket → research_packet → design_options → narrowed_decision → implementation_plan → code_backed_plan). " <>
          "The plan-quality scorer evaluates structured fields, not just submission_body — populate research_summary, options_considered, selected_option, rejected_options, implementation_steps, validation_plan, code_snippets, alignment_context, consulted_roles, codebase_findings, prior_art_summary, agent_spec_id, task_spec_id, agent_role, task_scope, out_of_scope, business_rules, domain_terms, allowed_actions, prohibited_actions, robustness_requirements, linked_policy_packs, linked_benchmark_suites, promotion_gates, allowed_semantic_changes, forbidden_semantic_changes, invariant_boundaries, requires_reapproval_if, harness_quality_checks, and scope_estimate for a strong score. " <>
          "Returns review_id, status (pending), and a URL where the human reviewer can approve or deny. " <>
          "After submission, poll ck_review_status until the decision is approved or denied before proceeding. " <>
          "Use ck_review_feedback (human-facing) to record a decision on an existing review.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["submission_body"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "title" => %{
            "type" => "string",
            "description" => "Human-readable title for display and search."
          },
          "review_type" => %{
            "type" => "string",
            "enum" => ["plan", "diff", "completion"],
            "description" =>
              "Type of review being submitted or queried (plan, diff, or completion)."
          },
          "submission_body" => %{
            "type" => "string",
            "description" =>
              "Full submission content: plan text, diff, or completion description."
          },
          "annotations" => %{
            "type" => "object",
            "description" => "Structured key-value annotations for machine-readable metadata."
          },
          "feedback_notes" => %{
            "type" => "string",
            "description" => "Freeform feedback notes from the reviewer."
          },
          "submitted_by" => %{
            "type" => "string",
            "description" => "Identity of the submitter for audit trail."
          },
          "metadata" => %{
            "type" => "object",
            "description" => "Arbitrary key-value metadata for extensibility and audit context."
          },
          "previous_review_id" => %{
            "type" => ["integer", "string"],
            "description" => "Reference to a prior review for iterative refinement."
          },
          "plan_phase" => %{
            "type" => "string",
            "enum" => [
              "ticket",
              "research_packet",
              "design_options",
              "narrowed_decision",
              "implementation_plan",
              "code_backed_plan"
            ],
            "description" => "Current phase of plan refinement."
          },
          "research_summary" => %{
            "type" => "string",
            "description" => "Summary of research performed before this submission."
          },
          "codebase_findings" => %{"type" => "array", "items" => %{"type" => "string"}},
          "prior_art_summary" => %{
            "type" => "string",
            "description" => "Summary of prior attempts or related work."
          },
          "alignment_context" => %{"type" => "array", "items" => %{"type" => "string"}},
          "consulted_roles" => %{"type" => "array", "items" => %{"type" => "string"}},
          "options_considered" => %{"type" => "array", "items" => %{"type" => "string"}},
          "selected_option" => %{
            "type" => "string",
            "description" => "The chosen approach with rationale."
          },
          "rejected_options" => %{"type" => "array", "items" => %{"type" => "string"}},
          "implementation_steps" => %{"type" => "array", "items" => %{"type" => "string"}},
          "validation_plan" => %{"type" => "array", "items" => %{"type" => "string"}},
          "code_snippets" => %{"type" => "array", "items" => %{"type" => "string"}},
          "agent_spec_id" => %{
            "type" => "string",
            "description" =>
              "Stable identifier for the agent role or task contract this plan is implementing."
          },
          "task_spec_id" => %{
            "type" => "string",
            "description" =>
              "Stable identifier for the task-level behavior contract this plan is implementing."
          },
          "agent_role" => %{
            "type" => "string",
            "description" =>
              "Reviewed role label such as support agent, code reviewer, deployment agent, or sales assistant."
          },
          "task_scope" => %{
            "type" => "string",
            "description" => "What the agent or task is expected to accomplish under this plan."
          },
          "out_of_scope" => %{"type" => "array", "items" => %{"type" => "string"}},
          "business_rules" => %{"type" => "array", "items" => %{"type" => "string"}},
          "domain_terms" => %{"type" => "array", "items" => %{"type" => "string"}},
          "persona_or_actor_context" => %{
            "type" => "string",
            "description" =>
              "User role, customer tier, permission state, or operating context relevant to behavior."
          },
          "allowed_actions" => %{"type" => "array", "items" => %{"type" => "string"}},
          "prohibited_actions" => %{"type" => "array", "items" => %{"type" => "string"}},
          "robustness_requirements" => %{"type" => "array", "items" => %{"type" => "string"}},
          "linked_policy_packs" => %{"type" => "array", "items" => %{"type" => "string"}},
          "linked_benchmark_suites" => %{"type" => "array", "items" => %{"type" => "string"}},
          "promotion_gates" => %{"type" => "array", "items" => %{"type" => "string"}},
          "allowed_semantic_changes" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Semantic behavior changes explicitly approved for this plan."
          },
          "forbidden_semantic_changes" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "Semantic behavior changes the agent must not introduce without a new review."
          },
          "invariant_boundaries" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "System invariants and boundaries that must remain true during execution."
          },
          "requires_reapproval_if" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Conditions that require human re-approval before continuing."
          },
          "harness_quality_checks" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "Agent-harness quality checks such as context hygiene, proof completeness, rollback safety, and compaction fidelity."
          },
          "scope_estimate" => %{
            "type" => "object",
            "properties" => %{
              "files_touched_estimate" => %{
                "type" => ["integer", "string"],
                "description" => "Estimated scope of the change."
              },
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
      "description" =>
        "Fetch the latest decision status (pending/approved/denied), reviewer notes, and browser review URL for a previously submitted review. Read-only. " <>
          "Provide review_id (returned by ck_review_submit) for a specific review, or task_id to get the latest review for that task. " <>
          "review_type (plan/diff/completion) filters when task_id is used without review_id. " <>
          "Poll this after ck_review_submit to check whether a human has approved or denied the submission before proceeding with execution.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "review_id" => %{
            "type" => ["integer", "string"],
            "description" => "Unique identifier of the review to query or act on."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "review_type" => %{"type" => "string", "enum" => ["plan", "diff", "completion"]}
        }
      }
    }
  end

  def ck_review_feedback_tool do
    %{
      "name" => "ck_review_feedback",
      "description" =>
        "Approve or deny a submitted review and attach feedback notes or structured annotations. Write operation — updates the review record and unblocks or halts the execution gate. " <>
          "review_id (required) is the ID returned by ck_review_submit. decision must be approved or denied. " <>
          "feedback_notes is freeform text for the reviewer's rationale. annotations is a key-value object for machine-readable metadata. " <>
          "This tool is human-facing: agents call ck_review_submit to create a review, then a human (or authorized agent) calls ck_review_feedback to record the decision. " <>
          "After approval, the submitting agent can proceed with execution; after denial, the plan should be revised and resubmitted.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["review_id", "decision"],
        "properties" => %{
          "review_id" => %{
            "type" => ["integer", "string"],
            "description" => "Unique identifier of the review to query or act on."
          },
          "decision" => %{
            "type" => "string",
            "enum" => ["approved", "denied"],
            "description" => "Governance decision: allow, warn, block, or escalate to human."
          },
          "feedback_notes" => %{
            "type" => "string",
            "description" => "Freeform feedback notes from the reviewer."
          },
          "annotations" => %{
            "type" => "object",
            "description" => "Structured key-value annotations for machine-readable metadata."
          },
          "reviewed_by" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_regression_result_tool do
    %{
      "name" => "ck_regression_result",
      "description" =>
        "Record external regression-test evidence from CI/CD systems (Bug0, Passmark, custom runners) so proof bundles and release-readiness checks account for external validation. " <>
          "Write operation — creates a DB record. Returns the recorded result ID. " <>
          "Required: session_id, engine (name of the test system), flow_name (test suite or flow identifier), outcome (passed/failed/flaky/skipped). " <>
          "Optional: commit_sha to link results to a specific revision, environment (ci/staging/production), external_run_id for cross-referencing the originating system, evidence for a structured payload. " <>
          "Use after an external test run to close the proof loop before calling ck_review_submit for a completion review. " <>
          "Retrieve past results with ck_memory_search using record_type: regression.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "engine", "flow_name", "outcome"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "engine" => %{
            "type" => "string",
            "description" => "Name of the external regression test engine (e.g., Bug0, Passmark)."
          },
          "flow_name" => %{
            "type" => "string",
            "description" => "Name of the regression test flow or test suite."
          },
          "outcome" => %{
            "type" => "string",
            "enum" => ["passed", "failed", "flaky", "skipped"],
            "description" => "Result classification of the operation."
          },
          "summary" => %{
            "type" => "string",
            "description" => "Brief human-readable summary of the record."
          },
          "environment" => %{
            "type" => "string",
            "description" => "Execution environment label (e.g., production, staging, ci)."
          },
          "commit_sha" => %{
            "type" => "string",
            "description" => "Git commit SHA associated with the test run."
          },
          "external_run_id" => %{
            "type" => "string",
            "description" => "External system run identifier for cross-referencing."
          },
          "evidence" => %{
            "type" => "object",
            "description" => "Structured evidence payload from the external system."
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_search_tool do
    %{
      "name" => "ck_memory_search",
      "description" =>
        "Search governed typed memory for the current session to recover prior decisions, findings, proofs, and domain knowledge. Read-only. " <>
          "query is a freeform text search applied across record titles, bodies, and tags. " <>
          "record_type filters by type (decision, finding, proof, goal, brief, checkpoint); omit to search all types. " <>
          "top_k limits the number of ranked results (default 10). source_type and source_id filter by origin. " <>
          "Returns ranked records with citations and scores. " <>
          "Use ck_memory_search to retrieve what was recorded in prior steps or sessions. Use ck_memory_record to write new records. Use ck_experience_search for full-text search across findings and tasks workspace-wide.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "query" => %{
            "type" => "string",
            "description" => "Search query string for filtering or full-text search."
          },
          "record_type" => %{
            "type" => "string",
            "enum" => ControlKeel.Memory.record_types(),
            "description" => "Record type classification."
          },
          "top_k" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of top-ranked results to return."
          },
          "source_type" => %{
            "type" => "string",
            "description" =>
              "Origin category of the record (e.g., developer, tool_output, human_review)."
          },
          "source_id" => %{"type" => "string"},
          "detail_level" => %{
            "type" => "string",
            "enum" => ["compact", "full"],
            "description" =>
              "compact (default) returns title/summary/tags per record; full additionally includes each record's body and metadata. Use compact to save tokens, full when you need the record contents."
          }
        }
      }
    }
  end

  def ck_memory_record_tool do
    %{
      "name" => "ck_memory_record",
      "description" =>
        "Write a governed memory record so future agents can explicitly retrieve it via ck_memory_search. " <>
          "Write operation — persists to the database. Idempotent: re-submitting the same source_id updates the existing record rather than duplicating it. " <>
          "Pass memory as a plain string for quick notes, or as an object with body, title, summary, record_type, and tags for structured records. " <>
          "record_type controls retrieval filtering: use decision for architectural choices, finding for issues, proof for evidence, goal for intent, brief for task context. " <>
          "tags is a string or array of strings for categorization. source_id links the record to an external artifact (e.g., a review ID or commit SHA). " <>
          "Use ck_memory_record to persist knowledge that should survive session boundaries. Use ck_finding for policy violations with a ruling decision. Use ck_goal for durable multi-session intent.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["memory"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "memory" => %{
            "oneOf" => [
              %{
                "type" => "string",
                "description" =>
                  "The memory content: a plain string or a structured object with body and optional title."
              },
              %{
                "type" => "object",
                "properties" => %{
                  "content" => %{
                    "type" => "string",
                    "description" =>
                      "The content to validate or process: source code, config text, shell command, or freeform text."
                  },
                  "memory" => %{
                    "type" => "string",
                    "description" =>
                      "The memory content: a plain string or a structured object with body and optional title."
                  },
                  "body" => %{
                    "type" => "string",
                    "description" => "Full content body with detailed information."
                  },
                  "title" => %{
                    "type" => "string",
                    "description" => "Human-readable title for display and search."
                  },
                  "summary" => %{
                    "type" => "string",
                    "description" => "Brief human-readable summary of the record."
                  },
                  "record_type" => %{
                    "type" => "string",
                    "enum" => ControlKeel.Memory.record_types(),
                    "description" => "Record type classification."
                  },
                  "tags" => %{
                    "oneOf" => [
                      %{
                        "type" => "array",
                        "items" => %{"type" => "string"},
                        "description" => "Tags for categorization and retrieval."
                      },
                      %{"type" => "string"}
                    ]
                  },
                  "source_type" => %{
                    "type" => "string",
                    "description" =>
                      "Origin category of the record (e.g., developer, tool_output, human_review)."
                  },
                  "source_id" => %{
                    "type" => "string",
                    "description" => "Unique identifier of the source system or record."
                  },
                  "metadata" => %{"type" => "object"}
                }
              }
            ]
          },
          "title" => %{
            "type" => "string",
            "description" => "Human-readable title for display and search."
          },
          "summary" => %{
            "type" => "string",
            "description" => "Brief human-readable summary of the record."
          },
          "body" => %{
            "type" => "string",
            "description" => "Full content body with detailed information."
          },
          "record_type" => %{
            "type" => "string",
            "enum" => ControlKeel.Memory.record_types(),
            "description" => "Record type classification."
          },
          "tags" => %{
            "oneOf" => [
              %{"type" => "array", "items" => %{"type" => "string"}},
              %{"type" => "string"}
            ]
          },
          "source_type" => %{
            "type" => "string",
            "description" =>
              "Origin category of the record (e.g., developer, tool_output, human_review)."
          },
          "source_id" => %{
            "type" => "string",
            "description" => "Unique identifier of the source system or record."
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_goal_tool do
    %{
      "name" => "ck_goal",
      "description" =>
        "Record, list, or update durable governed goals so long-running intent stays explicit, citable, and reviewable across sessions. " <>
          "Three modes: record (write — creates a new goal); list (read-only — returns goals filtered by status and horizon); update_status (write — updates an existing goal's status or progress). " <>
          "Required: session_id and mode. For record: provide goal (the statement text) and optionally title, horizon (task/session/workspace), and tags. For update_status: provide goal_id and the new status. " <>
          "horizon controls scope: task for short-lived intent, session for the current session, workspace for persistent cross-session goals. " <>
          "Use ck_goal for structured multi-session intent that should be explicitly tracked and reviewed. Use ck_memory_record for general decisions or notes not requiring status tracking.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "mode"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["record", "list", "update_status"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "goal" => %{"type" => "string", "description" => "The goal statement text."},
          "goal_id" => %{
            "type" => ["integer", "string"],
            "description" => "Unique identifier of an existing goal to update."
          },
          "title" => %{
            "type" => "string",
            "description" => "Human-readable title for display and search."
          },
          "summary" => %{
            "type" => "string",
            "description" => "Brief human-readable summary of the record."
          },
          "body" => %{
            "type" => "string",
            "description" => "Full content body with detailed information."
          },
          "status" => %{
            "type" => "string",
            "enum" => ControlKeel.MCP.Tools.CkGoal.statuses() ++ ["all"],
            "description" => "Current status for filtering or updating."
          },
          "horizon" => %{
            "type" => "string",
            "enum" => ControlKeel.MCP.Tools.CkGoal.horizons(),
            "description" => "Temporal scope of the goal: task, session, or workspace."
          },
          "progress_note" => %{
            "type" => "string",
            "description" => "Note about progress toward the goal."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of results to return."
          },
          "tags" => %{
            "oneOf" => [
              %{"type" => "array", "items" => %{"type" => "string"}},
              %{"type" => "string"}
            ]
          },
          "source_type" => %{
            "type" => "string",
            "description" =>
              "Origin category of the record (e.g., developer, tool_output, human_review)."
          },
          "source_id" => %{
            "type" => "string",
            "description" => "Unique identifier of the source system or record."
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_archive_tool do
    %{
      "name" => "ck_memory_archive",
      "description" =>
        "Archive a memory record so it is excluded from future ck_memory_search results. Write operation — marks the record as archived in the database; it is not deleted. " <>
          "memory_id is the integer ID returned by ck_memory_record or ck_memory_search. " <>
          "Use when a record is stale, superseded by a newer decision, or contains information that should no longer guide future agents. " <>
          "To update a record's content instead of archiving it, call ck_memory_record again with the same source_id.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["memory_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "memory_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_budget_tool do
    %{
      "name" => "ck_budget",
      "description" =>
        "Estimate, record, or check the cost of an agent operation against session and daily spend budgets. " <>
          "Three modes: estimate (read-only, returns headroom and projected cost); commit (write — deducts estimated_cost_cents from the session budget); status (read-only, returns remaining budget). " <>
          "For commit mode: pass session_id, estimated_cost_cents, provider, model, input_tokens, and output_tokens. " <>
          "Pass include_token_overhead: true with project_root to attach a token overhead audit (rule files, skill duplicates, tool schemas) to the response. " <>
          "Check ck_budget before expensive multi-agent work or large model calls. Use ck_cost_optimizer for model price comparisons without recording spend.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["estimate", "commit", "status"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "estimated_cost_cents" => %{
            "type" => ["integer", "string"],
            "description" => "Estimated cost of the operation in US cents."
          },
          "provider" => %{
            "type" => "string",
            "description" => "AI provider name (e.g., openai, anthropic, ollama)."
          },
          "model" => %{
            "type" => "string",
            "description" => "AI model identifier (e.g., claude-sonnet-4.6, o4-mini)."
          },
          "input_tokens" => %{
            "type" => ["integer", "string"],
            "description" => "Number of input (prompt) tokens consumed."
          },
          "cached_input_tokens" => %{
            "type" => ["integer", "string"],
            "description" => "Number of tokens served from cache."
          },
          "output_tokens" => %{
            "type" => ["integer", "string"],
            "description" => "Number of output (completion) tokens generated."
          },
          "source" => %{
            "type" => "string",
            "description" => "Source system or component that triggered the cost."
          },
          "tool" => %{
            "type" => "string",
            "description" => "Specific tool or operation that incurred the cost."
          },
          "metadata" => %{
            "type" => "object",
            "description" => "Arbitrary key-value metadata for extensibility and audit context."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to project root. Required when include_token_overhead is true."
          },
          "include_token_overhead" => %{
            "type" => "boolean",
            "description" =>
              "When true, attach a token overhead summary (rule files, skill duplicates, tool schemas) to the response."
          }
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
        "Recommend the best available AI agent for a given task based on security tier, remaining budget, task type, and past performance data. Read-only — no session state is changed. " <>
          "task is a plain-language description of what needs to be done. " <>
          "risk_tier (low/medium/high/critical) filters out agents that are not cleared for the security level; defaults to medium. " <>
          "allowed_agents restricts routing to a specific subset of agent IDs; omit to allow all. " <>
          "Returns a ranked list of agent recommendations with rationale. " <>
          "Use ck_route to pick an agent, then ck_delegate to transfer the task. Use ck_cost_optimizer for a price-focused comparison without routing.",
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
            "items" => %{
              "type" => "string",
              "description" => "Restrict routing to these agent IDs. Omit to allow all."
            },
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
        "Hand off a governed task or session to another AI agent, transferring governance context (findings, budget, proofs) to the target. " <>
          "Mutates session state to reflect the delegation. " <>
          "Four modes: auto (ControlKeel picks the best agent), embedded (inline sub-agent), handoff (transfer session ownership), runtime (delegate to a pre-configured runtime agent). " <>
          "agent is the target agent ID (e.g., claude, opencode, cursor). " <>
          "Call ck_route first to identify the best agent, then ck_delegate to transfer. " <>
          "Prefer ck_route when you only need a recommendation without transferring; prefer ck_delegate when you are ready to hand off execution.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "agent" => %{
            "type" => "string",
            "description" => "Target agent identifier for delegation (e.g., claude, opencode)."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["auto", "embedded", "handoff", "runtime"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  defp ck_result_peek_tool do
    %{
      "name" => "ck_result_peek",
      "description" =>
        "Peek at the full stdout of a previously completed ck_delegate embedded run without loading it all into context. " <>
          "Use result_ref and package_root returned by ck_delegate to locate the stored output. " <>
          "Supports byte-range reads: pass peek_bytes to limit how much to load, and offset to skip ahead. " <>
          "Use result_length (returned by ck_delegate) to decide whether to peek, pass the ref downstream, or skip loading entirely. " <>
          "This is the RLM variable-encapsulation pattern: treat large sub-agent outputs as named references, not inline blobs.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["package_root"],
        "properties" => %{
          "package_root" => %{
            "type" => "string",
            "description" =>
              "package_root returned by ck_delegate for the completed embedded run."
          },
          "peek_bytes" => %{
            "type" => ["integer", "string"],
            "description" => "How many bytes to read (default 2000, max 32000)."
          },
          "offset" => %{
            "type" => ["integer", "string"],
            "description" => "Byte offset to start reading from (default 0)."
          }
        }
      }
    }
  end

  defp ck_cost_optimizer_tool do
    %{
      "name" => "ck_cost_optimizer",
      "description" =>
        "Get cost optimization suggestions or compare AI provider/model prices for a task. Read-only — no budget records are written (use ck_budget to record actual spend). " <>
          "Two modes: suggest returns optimization tips based on recent session spending patterns; compare returns a side-by-side price breakdown for the given task. " <>
          "For suggest mode, pass session_id. For compare mode, pass task_description and estimated_tokens along with top_provider and top_model as the baseline. " <>
          "Use ck_cost_optimizer before choosing a model for expensive multi-agent work; use ck_budget to record and enforce spend limits.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["suggest", "compare"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "spending" => %{"type" => "array", "items" => %{"type" => "object"}},
          "top_provider" => %{
            "type" => "string",
            "description" => "Primary provider for cost comparison."
          },
          "top_model" => %{
            "type" => "string",
            "description" => "Primary model for cost comparison."
          },
          "task_description" => %{
            "type" => "string",
            "description" => "Task description for cost estimation."
          },
          "estimated_tokens" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_deployment_advisor_tool do
    %{
      "name" => "ck_deployment_advisor",
      "description" =>
        "Analyze the project stack and suggest deployment platforms, or generate CI/CD and Docker configuration files. " <>
          "Three modes: analyze (read-only, returns platform recommendations based on detected stack); generate_files (write operation, creates Dockerfile and CI/CD configs in the project); dns_guide (read-only, returns DNS setup instructions for the recommended platform). " <>
          "project_root is required. Set dry_run: true with generate_files to preview what would be created without writing files. " <>
          "Use ck_deployment_advisor before deploying a new project or when setting up CI/CD for the first time. For budget and cost checks before deployment, use ck_budget.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode", "project_root"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["analyze", "generate_files", "dns_guide"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "dry_run" => %{"type" => "boolean"}
        }
      }
    }
  end

  defp ck_outcome_tracker_tool do
    %{
      "name" => "ck_outcome_tracker",
      "description" =>
        "Record session outcomes or retrieve agent performance leaderboards to close the reinforcement-learning feedback loop. " <>
          "Three modes: record persists a session outcome (write operation); get_session reads a specific outcome by session_id (read-only); get_leaderboard returns ranked agent performance (read-only). " <>
          "For record mode: pass session_id, outcome (success/partial/failure), agent_id, and task_type. " <>
          "For get_leaderboard: pass workspace_id and optional window (days) and limit. " <>
          "Call after task completion before ending the session so ck_route and ck_cost_optimizer have fresh performance data for future routing decisions.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["record", "get_session", "get_leaderboard"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "outcome" => %{
            "type" => "string",
            "description" => "Result classification of the operation."
          },
          "agent_id" => %{"type" => "string"},
          "task_type" => %{"type" => "string"},
          "workspace_id" => %{
            "type" => ["integer", "string"],
            "description" => "Workspace identifier for cross-session scope."
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of results to return."
          },
          "window" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_token_audit_tool do
    %{
      "name" => "ck_token_audit",
      "description" =>
        "Audit project rule files (AGENTS.md, CLAUDE.md, etc.) and skills for token overhead. " <>
          "Returns word counts, token estimates, duplicate detection, and optimization recommendations.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Omit to use current working directory."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["full", "skills", "rules", "tools"],
            "description" =>
              "Audit mode: 'full' (rules + skills), 'skills' (skills only), 'rules' (rules only), 'tools' (CK MCP tool schemas). Defaults to 'full'."
          }
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
          },
          "include_duplicate_copies" => %{
            "type" => "boolean",
            "description" =>
              "If true, surface diagnostics for identical duplicate skill copies that MCP hosts may load (token overhead). Defaults to false."
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
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp ck_skill_validate_tool do
    %{
      "name" => "ck_skill_validate",
      "description" =>
        "Validate skill output against a JSON Schema defined in the skill's result-schema frontmatter field. " <>
          "Skills can define a result_schema in their frontmatter; agents call this tool after running a skill to enforce typed, structured output. " <>
          "Accepts output + schema directly, or output + skill_name to validate against the skill's built-in schema.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["output"],
        "properties" => %{
          "output" => %{
            "type" => "string",
            "description" =>
              "The skill output to validate. Can be a JSON string or plain text, up to 100KB."
          },
          "schema" => %{
            "type" => "string",
            "description" =>
              "JSON Schema as a string to validate against. Required if skill_name is not provided."
          },
          "skill_name" => %{
            "type" => "string",
            "description" =>
              "Optional skill name to use the skill's built-in result_schema. If provided, schema is not required."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Only used when skill_name is provided."
          }
        }
      }
    }
  end

  defp ck_load_resources_tool do
    %{
      "name" => "ck_load_resources",
      "description" =>
        "Fallback for clients that do not support MCP resources or native bulk skill loading. Load one or more CK resource URIs such as skills://<name>; pass multiple skills:// URIs to activate several skills in one governed CK call.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["uris"],
        "properties" => %{
          "uris" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "description" => "List of CK resource URIs to load (e.g., skills://my-skill)."
            },
            "description" => "Resource URIs to load, for example skills://controlkeel-governance"
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root directory on the local filesystem."
          },
          "target" => %{
            "type" => "string",
            "description" => "Distribution target (e.g., opencode, cursor, claude)."
          },
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp ck_mcp_discover_tool do
    %{
      "name" => "ck_mcp_discover",
      "description" =>
        "Auto-discover tools from an external MCP server by querying its tools/list endpoint. " <>
          "This enables progressive discovery of MCP capabilities without manual configuration.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["server_url"],
        "properties" => %{
          "server_url" => %{
            "type" => "string",
            "description" => "HTTP URL of the MCP server (e.g., 'http://localhost:3001/mcp')."
          },
          "timeout" => %{
            "type" => "integer",
            "description" => "Request timeout in milliseconds. Default: 10000"
          },
          "transport" => %{
            "type" => "string",
            "enum" => ["http"],
            "description" =>
              "Transport type. Auto-detected from server_url if not specified. HTTP discovery uses Req with normal TLS verification."
          }
        }
      }
    }
  end

  defp ck_attach_tool do
    %{
      "name" => "ck_attach",
      "description" =>
        "Wire ControlKeel into the current agent host (Claude Code, Cursor, Codex, OpenCode, etc.). " <>
          "Closes the gap for users who installed ControlKeel via a one-line MCP-add command but skipped " <>
          "`controlkeel attach <host>`. Installs the host-specific hooks (SessionStart, PreToolUse, " <>
          "PostToolUse, UserPromptSubmit), skills directory, slash commands, AGENTS.md/CLAUDE.md preamble, " <>
          "and subagent profiles for the requested host. Idempotent — re-running refreshes artifacts to " <>
          "the current version. Writes only inside `project_root`; no network egress. " <>
          "Call this once after a one-line MCP install when the host lacks ControlKeel hooks/skills. " <>
          "Use `ck_mcp_discover` first if unsure which host ID to pass.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["host"],
        "properties" => %{
          "host" => %{
            "type" => "string",
            "description" =>
              "Agent host ID to attach. One of: claude-code, codex-cli, cursor, opencode, augment, " <>
                "continue, aider, cline, roo-code, kiro, goose, gemini-cli, letta-code, windsurf, " <>
                "vscode, copilot, pi."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Defaults to CK_PROJECT_ROOT or the MCP server's working directory."
          },
          "scope" => %{
            "type" => "string",
            "enum" => ["project", "user"],
            "description" => "Attach scope. Defaults to project."
          }
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

  # Determines active tool groups from env var or Application config.
  # Priority: CK_TOOL_GROUPS env var > config :controlkeel, :mcp, tool_groups: > :all
  # Example env var: CK_TOOL_GROUPS=core,governance
  # Example config:  config :controlkeel, :mcp, tool_groups: ["core", "governance"]
  defp env_tool_groups do
    case System.get_env("CK_TOOL_GROUPS") do
      v when is_binary(v) and v != "" ->
        groups =
          v
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        if groups == [], do: app_config_tool_groups(), else: groups

      _ ->
        app_config_tool_groups()
    end
  end

  defp app_config_tool_groups do
    case Application.get_env(:controlkeel, :mcp, [])[:tool_groups] do
      groups when is_list(groups) and groups != [] -> groups
      # Return nil to let adaptive mode handle it
      _ -> nil
    end
  end

  # Adaptive tool group selection based on project usage patterns.
  # Wrapped in safe calls because the MCP server starts before the deferred
  # boot task finishes starting Repo, ToolGroupTracker, etc.  A tools/list
  # request that arrives during that window must fall through to
  # smart_default_groups/1 instead of crashing the GenServer.
  defp adaptive_tool_groups(project_root) do
    # First, check if project has explicit tool group preferences
    case safe_get_project_tool_groups(project_root) do
      groups when is_list(groups) ->
        # Use project's explicit preference
        groups

      _ ->
        # No explicit preference, check usage data
        case safe_suggest_groups(project_root) do
          %{suggested: groups} when length(groups) > 2 ->
            # We have meaningful usage data, use suggested groups
            groups

          _ ->
            # No usage data yet, use smart defaults based on project type
            smart_default_groups(project_root)
        end
    end
  end

  defp safe_get_project_tool_groups(project_root) do
    try do
      ControlKeel.Project.Binding.get_tool_groups(project_root)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
      :throw, _ -> nil
    end
  end

  defp safe_suggest_groups(project_root) do
    try do
      ControlKeel.MCP.ToolGroupTracker.suggest_groups(project_root)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
      :throw, _ -> nil
    end
  end

  # Smart default groups based on project characteristics
  defp smart_default_groups(project_root) do
    try do
      has_git = File.exists?(Path.join(project_root, ".git"))
      has_tests = test_dir_exists?(project_root)
      has_package_json = File.exists?(Path.join(project_root, "package.json"))
      has_mix_exs = File.exists?(Path.join(project_root, "mix.exs"))
      has_cargo_toml = File.exists?(Path.join(project_root, "Cargo.toml"))
      has_agents_md = File.exists?(Path.join(project_root, "AGENTS.md"))

      if has_agents_md do
        :all
      else
        base_groups = ["core", "governance"]

        additional_groups =
          cond do
            has_mix_exs ->
              ["filesystem", "git", "observability", "skills", "checkpoints", "worktrees"]

            has_package_json ->
              ["filesystem", "git", "observability", "skills", "checkpoints", "worktrees"]

            has_cargo_toml ->
              ["filesystem", "git", "observability", "skills", "checkpoints", "worktrees"]

            has_tests and has_git ->
              ["filesystem", "git"]

            has_git ->
              ["git"]

            true ->
              ["filesystem"]
          end

        Enum.uniq(base_groups ++ additional_groups)
      end
    rescue
      _ -> ["core", "governance"]
    catch
      :exit, _ -> ["core", "governance"]
      :throw, _ -> ["core", "governance"]
    end
  end

  defp test_dir_exists?(project_root) do
    try do
      ["test", "tests", "__tests__", "spec"]
      |> Enum.any?(fn dir -> File.dir?(Path.join(project_root, dir)) end)
    rescue
      _ -> false
    catch
      :exit, _ -> false
      :throw, _ -> false
    end
  end

  # Log tool group decisions for transparency and debugging
  defp log_tool_group_decision(project_root, groups, total_tools, filtered_tools) do
    excluded_count = total_tools - filtered_tools

    Logger.info(
      "Adaptive tool groups for #{Path.basename(project_root)}: #{inspect(groups)} " <>
        "(#{filtered_tools}/#{total_tools} tools, #{excluded_count} excluded)"
    )
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
      "content" => [%{"type" => "text", "text" => success_content_summary(result)}],
      "structuredContent" => result
    })
  end

  defp tool_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  # Tool EXECUTION failure (not a malformed request): per the MCP June-2025 tools spec,
  # return a tool result with isError:true so the model can read the failure and
  # self-correct, instead of an opaque JSON-RPC protocol error. Protocol-level errors
  # (-32602) stay reserved for invalid/malformed arguments, which the clause above handles.
  defp tool_response(id, {:error, reason}) do
    ok_response(id, %{
      "content" => [%{"type" => "text", "text" => tool_error_text(reason)}],
      "isError" => true
    })
  end

  defp success_content_summary(result) when is_map(result) do
    keys =
      result
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.sort()
      |> Enum.take(8)
      |> Enum.join(", ")

    suffix = if map_size(result) > 8, do: ", …", else: ""
    "Structured result returned in structuredContent (keys: #{keys}#{suffix})."
  end

  defp success_content_summary(result) when is_list(result),
    do: "Structured result returned in structuredContent (list length: #{length(result)})."

  defp success_content_summary(_result), do: "Structured result returned in structuredContent."

  defp tool_error_text(reason) when is_binary(reason), do: reason
  defp tool_error_text(reason), do: inspect(reason)

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
    case await_mcp_backend_ready(mcp_boot_gate_wait_ms()) do
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

  defp await_mcp_backend_ready(timeout_ms) when is_integer(timeout_ms) and timeout_ms <= 0 do
    normalize_mcp_backend_status(ControlKeel.Application.mcp_backend_boot_status())
  end

  defp await_mcp_backend_ready(timeout_ms) when is_integer(timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    await_mcp_backend_ready_until(deadline_ms)
  end

  defp await_mcp_backend_ready(_timeout_ms), do: :ready

  defp await_mcp_backend_ready_until(deadline_ms) do
    case normalize_mcp_backend_status(ControlKeel.Application.mcp_backend_boot_status()) do
      :booting ->
        if System.monotonic_time(:millisecond) < deadline_ms do
          Process.sleep(25)
          await_mcp_backend_ready_until(deadline_ms)
        else
          :booting
        end

      other ->
        other
    end
  end

  defp normalize_mcp_backend_status(:ready), do: :ready
  defp normalize_mcp_backend_status(:booting), do: :booting
  defp normalize_mcp_backend_status({:failed, _reason} = failed), do: failed
  defp normalize_mcp_backend_status(_status), do: :ready

  defp mcp_boot_gate_wait_ms do
    case Application.get_env(:controlkeel, :mcp_boot_gate_wait_ms, 2000) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 2000
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

  def ck_session_digest_tool do
    %{
      "name" => "ck_session_digest",
      "description" =>
        "Generate a condensed, human-scannable digest of what happened in a session — tasks completed, findings raised, budget spent, reviews pending, and notable highlights. Three modes: generate (create a new digest), latest (return the most recent), list (paginated history). Designed for the forward-deployed engineer who needs an 'inbox that summarizes what happened' without reading raw event streams.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["generate", "latest", "list"],
            "description" => "Operation mode. Defaults to generate."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" => "Session identifier."
          },
          "digest_type" => %{
            "type" => "string",
            "enum" => ["session", "daily", "shift_change"],
            "description" => "Type of digest to generate. Defaults to session."
          }
        }
      }
    }
  end

  def ck_rollback_tool do
    %{
      "name" => "ck_rollback",
      "description" =>
        "Execute a governed rollback of an agent's work. Records a git checkpoint before each task and provides a single action to revert. Safety-checked: refuses if downstream tasks depend on the changes. Creates an audit finding on every rollback. Modes: checkpoint (capture git HEAD before task), execute (revert agent's changes), status (check snapshot state), list (all snapshots for session).",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["checkpoint", "execute", "status", "list"],
            "description" => "Operation mode. Defaults to status."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" => "Session identifier."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Task identifier. Required for checkpoint, execute, and status modes."
          },
          "reason" => %{
            "type" => "string",
            "description" => "Reason for rollback. Recorded in audit finding."
          },
          "project_root" => %{
            "type" => "string",
            "description" => "Absolute path to the project root."
          }
        }
      }
    }
  end

  def ck_loop_tool do
    %{
      "name" => "ck_loop",
      "description" =>
        "Create and govern a bounded iterative loop without executing worker code. The contract freezes verifier paths and hashes, separates mutable paths, classifies artifact longevity, and enforces metric, iteration, cost, duration, no-progress, blocked-finding, and lasting-code architecture stop conditions. Modes: create, record, status, stop, promote. Rejected iterations require an explicit audited rollback.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "task_id"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["create", "record", "status", "stop", "promote"]
          },
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "artifact_class" => %{
            "type" => "string",
            "enum" => [
              "ephemeral_experiment",
              "mechanical_transformation",
              "research",
              "security_triage",
              "lasting_code"
            ]
          },
          "mutable_paths" => %{"type" => "array", "items" => %{"type" => "string"}},
          "verifier_paths" => %{"type" => "array", "items" => %{"type" => "string"}},
          "verifier_command" => %{"type" => "string"},
          "metric_name" => %{"type" => "string"},
          "direction" => %{"type" => "string", "enum" => ["maximize", "minimize"]},
          "target" => %{"type" => "number"},
          "max_iterations" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
          "max_cost_cents" => %{"type" => "integer", "minimum" => 1},
          "max_duration_seconds" => %{"type" => "integer", "minimum" => 1, "maximum" => 86400},
          "no_progress_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
          "allowed_sandbox_adapters" => %{
            "type" => "array",
            "items" => %{"type" => "string", "enum" => ["docker", "e2b", "nono"]}
          },
          "require_ephemeral_environment" => %{"type" => "boolean"},
          "invariant_boundaries" => %{"type" => "array", "items" => %{"type" => "string"}},
          "allowed_semantic_changes" => %{"type" => "array", "items" => %{"type" => "string"}},
          "forbidden_semantic_changes" => %{"type" => "array", "items" => %{"type" => "string"}},
          "machine_independence_requirements" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          "review_risk" => %{
            "type" => "string",
            "enum" => ["standard", "high", "critical"]
          },
          "required_review_personas" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          "complexity_budget" => %{"type" => "object"},
          "local_defense_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
          "human_promotion_required" => %{"type" => "boolean"},
          "iteration" => %{"type" => "integer", "minimum" => 1},
          "metric_value" => %{"type" => "number"},
          "cost_cents" => %{"type" => "integer", "minimum" => 0},
          "verifier_passed" => %{"type" => "boolean"},
          "summary" => %{"type" => "string"},
          "changed_paths" => %{"type" => "array", "items" => %{"type" => "string"}},
          "sandbox_adapter" => %{
            "type" => "string",
            "enum" => ["docker", "e2b", "nono"]
          },
          "environment_id" => %{"type" => "string"},
          "hypothesis" => %{"type" => "string"},
          "mechanism" => %{"type" => "string"},
          "observed_effect" => %{"type" => "string"},
          "documentation_impact" => %{"type" => "string"},
          "invariant_effect" => %{
            "type" => "string",
            "enum" => ["strengthened", "preserved", "local_defense_added", "unknown"]
          },
          "invariant_evidence" => %{"type" => "string"},
          "semantic_changes" => %{"type" => "array", "items" => %{"type" => "string"}},
          "complexity_delta" => %{"type" => "object"},
          "machine_independence_verified" => %{"type" => "boolean"},
          "machine_independence_evidence" => %{"type" => "string"},
          "call_graph" => %{"type" => "string"},
          "diagnosis_path" => %{"type" => "string"},
          "rollback_path" => %{"type" => "string"},
          "maintenance_without_model" => %{"type" => "string"},
          "promotion_packet" => %{
            "type" => "object",
            "description" =>
              "Required when a lasting_code iteration reaches its target. Contains citable behavior, invariant, interface, deterministic command, rollback, and documentation evidence."
          },
          "review_id" => %{"type" => ["integer", "string"]},
          "reason" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_workspace_agent_tool do
    %{
      "name" => "ck_workspace_agent",
      "description" =>
        "Manage workspace agent roles: one primary 'super-agent' per workspace maintained by a forward-deployed engineer, specialized agents for specific domains, and ephemeral agents for short-lived tasks. Modes: register (create agent, only one primary per workspace), update (change scope/budget/status), list (all agents for workspace), health (aggregated health indicator), retire (deactivate agent).",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["register", "update", "list", "health", "retire"],
            "description" => "Operation mode. Defaults to list."
          },
          "workspace_id" => %{
            "type" => ["integer", "string"],
            "description" => "Workspace identifier."
          },
          "agent_id" => %{
            "type" => ["integer", "string"],
            "description" => "Agent identifier. Required for update, health, and retire modes."
          },
          "name" => %{
            "type" => "string",
            "description" => "Human-readable agent name."
          },
          "role" => %{
            "type" => "string",
            "enum" => ["primary", "specialized", "ephemeral"],
            "description" => "Agent role. Only one primary per workspace."
          },
          "agent_type" => %{
            "type" => "string",
            "description" => "Agent adapter type (e.g., claude-code, cursor, opencode)."
          },
          "status" => %{
            "type" => "string",
            "enum" => ["active", "paused", "retired"],
            "description" => "Agent status."
          },
          "scope" => %{
            "type" => "object",
            "description" => "Scoped capabilities and policies for this agent."
          },
          "budget_cents" => %{
            "type" => ["integer", "string"],
            "description" => "Budget allocation in cents."
          },
          "maintainer_id" => %{
            "type" => ["integer", "string"],
            "description" => "User ID of the human who maintains this agent."
          },
          "policy_overrides" => %{
            "type" => "object",
            "description" => "Policy overrides for this agent."
          }
        }
      }
    }
  end

  def ck_copilot_tool do
    %{
      "name" => "ck_copilot",
      "description" =>
        "Real-time collaborative channel where human actions stream to the agent. Build software for humans and agents to use together — agents can see when a human is viewing, editing, or approving. Modes: subscribe (receive events), publish (emit an event), presence (who is active), history (recent events).",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["subscribe", "publish", "presence", "history"],
            "description" => "Operation mode. Defaults to history."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" => "Session identifier."
          },
          "event_type" => %{
            "type" => "string",
            "enum" => [
              "human.viewing",
              "human.editing",
              "human.approving",
              "human.commenting",
              "agent.status",
              "agent.progress"
            ],
            "description" => "Event type for publish mode."
          },
          "payload" => %{
            "type" => "object",
            "description" => "Event payload."
          },
          "actor" => %{
            "type" => "string",
            "description" => "Actor identifier (e.g., 'human', 'agent')."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier for scoping the event."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Max events to return in history mode. Default: 50."
          }
        }
      }
    }
  end

  def ck_external_service_tool do
    %{
      "name" => "ck_external_service",
      "description" =>
        "Track and govern agent interactions with external SaaS APIs. Rate limits per service, cost attribution, and PII redaction. Modes: record (log an interaction with auto-redaction), summary (aggregated view per service), rate_limit_status (current rates against limits), top_services (ranked by volume and cost).",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ["record", "summary", "rate_limit_status", "top_services"],
            "description" => "Operation mode. Defaults to summary."
          },
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" => "Session identifier."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier for scoping the interaction."
          },
          "service_name" => %{
            "type" => "string",
            "description" => "External service name (e.g., github, slack, jira)."
          },
          "interaction_type" => %{
            "type" => "string",
            "enum" => ["api_call", "webhook", "browser_action"],
            "description" => "Type of interaction. Defaults to api_call."
          },
          "method" => %{
            "type" => "string",
            "description" => "HTTP method (GET, POST, etc.)."
          },
          "endpoint" => %{
            "type" => "string",
            "description" => "Sanitized endpoint path. PII is auto-redacted."
          },
          "status_code" => %{
            "type" => ["integer", "string"],
            "description" => "HTTP status code or result code."
          },
          "latency_ms" => %{
            "type" => ["integer", "string"],
            "description" => "Request latency in milliseconds."
          },
          "cost_cents" => %{
            "type" => ["integer", "string"],
            "description" => "Estimated cost in cents."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Max results for top_services mode. Default: 10."
          },
          "metadata" => %{
            "type" => "object",
            "description" => "Additional metadata."
          }
        }
      }
    }
  end

  def ck_task_tool do
    %{
      "name" => "ck_task",
      "description" =>
        "Manage governed tasks within a session. Six modes: status (return task details for a given task_id); claim (claim an available task for execution); complete (mark a task as done, blocked if unresolved findings exist); heartbeat (signal the agent is alive and working on a task); checks (record task quality check results); report (submit a task report with output and metadata).",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier for correlating findings, proofs, budget, and audit trail."
          },
          "task_id" => %{
            "type" => ["integer", "string"],
            "description" => "Task identifier within the session for scoped operations."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["status", "claim", "complete", "heartbeat", "checks", "report"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "execution_mode" => %{
            "type" => "string",
            "description" => "Execution mode for claim (e.g., local, external)."
          },
          "progress" => %{
            "type" => "string",
            "description" => "Progress indicator for heartbeat mode."
          },
          "note" => %{
            "type" => "string",
            "description" => "Freeform note for heartbeat mode."
          },
          "checks" => %{
            "type" => "array",
            "items" => %{"type" => "object"},
            "description" => "Array of check result objects for checks mode."
          },
          "status" => %{
            "type" => "string",
            "description" => "Target status for report mode (e.g., done, failed, blocked)."
          },
          "output" => %{
            "type" => "object",
            "description" => "Structured output payload for report mode."
          },
          "metadata" => %{
            "type" => "object",
            "description" => "Arbitrary key-value metadata for report mode."
          },
          "project_root" => %{
            "type" => "string",
            "description" => "Absolute path to project root."
          }
        }
      }
    }
  end

  def ck_session_tool do
    %{
      "name" => "ck_session",
      "description" =>
        "Enumerate and manage governed sessions. Three modes: list (enumerate sessions for the project); status (get current session details, resolves from project binding if session_id omitted); switch (change active session binding — REQUIRES confirm: true).",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "session_id" => %{
            "type" => ["integer", "string"],
            "description" =>
              "Unique session identifier. Required for switch mode. Omit or pass nil to resolve from project binding."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["list", "status", "switch"],
            "description" => "Operation mode that determines the tool behavior and return shape."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Max sessions to return for list mode. Default: 20, max: 100."
          },
          "confirm" => %{
            "type" => "boolean",
            "description" => "Must be true to authorize a session switch."
          },
          "project_root" => %{
            "type" => "string",
            "description" => "Absolute path to project root. Required for switch mode."
          }
        }
      }
    }
  end
end
