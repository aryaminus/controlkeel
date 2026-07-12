defmodule ControlKeel.MCP.OutputSchemas do
  @moduledoc false

  @nullable_string %{"type" => ["string", "null"]}
  @nullable_integer %{"type" => ["integer", "null"]}
  @nullable_object %{"type" => ["object", "null"]}
  @nullable_object_or_string %{"type" => ["object", "string", "null"]}

  @schemas %{
    "ck_validate" => %{
      "type" => "object",
      "properties" => %{
        "allowed" => %{"type" => "boolean"},
        "decision" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "findings" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => @nullable_string,
              "severity" => %{"type" => "string"},
              "category" => %{"type" => "string"},
              "rule_id" => %{"type" => "string"},
              "decision" => %{"type" => "string"},
              "plain_message" => %{"type" => "string"},
              "location" => @nullable_object,
              "metadata" => %{"type" => "object"}
            }
          }
        },
        "fix_prompts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "rule_id" => %{"type" => "string"},
              "supported" => %{"type" => "boolean"},
              "agent_prompt" => %{"type" => "string"},
              "summary" => %{"type" => "string"},
              "requires_human" => %{"type" => "boolean"}
            }
          }
        },
        "scanned_at" => %{"type" => "string"},
        "precedent" => %{"type" => "array", "items" => %{"type" => "object"}},
        "advisory" => @nullable_object,
        "trust_policy_advisory" => @nullable_string
      }
    },
    "ck_execute_code" => %{
      "type" => "object",
      "properties" => %{
        "allowed" => %{"type" => "boolean"},
        "language" => %{"type" => "string"},
        "sandbox" => %{"type" => "string"},
        "dry_run" => %{"type" => "boolean"},
        "exit_status" => @nullable_integer,
        "output" => %{"type" => "string"},
        "output_truncated" => %{"type" => "boolean"},
        "command" => %{"type" => "string"},
        "policy" => %{"type" => "object"},
        "validation" => %{"type" => "object"},
        "proof_artifacts" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    },
    "ck_context" => %{
      "type" => "object",
      "properties" => %{
        "session_id" => %{"type" => "integer"},
        "project_root" => %{"type" => "string"},
        "session_title" => %{"type" => "string"},
        "risk_tier" => %{"type" => "string"},
        "compliance_profile" => %{"type" => "string"},
        "active_findings" => %{"type" => "object"},
        "security_case_summary" => %{"type" => "object"},
        "autonomy_profile" => %{"type" => "object"},
        "outcome_profile" => %{"type" => "object"},
        "improvement_loop" => %{"type" => "object"},
        "budget_summary" => %{"type" => "object"},
        "boundary_summary" => %{"type" => "object"},
        "current_task" => @nullable_object,
        "past_patterns" => %{"type" => ["object", "array"], "items" => %{"type" => "object"}},
        "proof_summary" => @nullable_object,
        "planning_context" => %{"type" => "object"},
        "task_augmentation" => %{"type" => "object"},
        "memory_hits" => %{"type" => "array", "items" => %{"type" => "object"}},
        "precedent" => %{"type" => "array", "items" => %{"type" => "object"}},
        "resume_packet" => %{"type" => "object"},
        "workspace_context" => %{"type" => "object"},
        "workspace_cache_key" => @nullable_string,
        "context_reacquisition" => %{"type" => "object"},
        "instruction_hierarchy" => %{"type" => "object"},
        "recent_events" => %{"type" => "array", "items" => %{"type" => "object"}},
        "transcript_summary" => %{"type" => "object"},
        "provider_status" => %{"type" => "object"},
        "bootstrap_status" => @nullable_object,
        "attach_advisory" => @nullable_object_or_string,
        "detail_level" => %{"type" => "string"},
        "detail_hint" => %{"type" => "string"}
      }
    },
    "ck_context_pack" => %{
      "type" => "object",
      "properties" => %{
        "session_id" => %{"type" => "integer"},
        "task_id" => @nullable_integer,
        "query" => %{"type" => "string"},
        "generated_at" => %{"type" => "string"},
        "factual_only" => %{"type" => "boolean"},
        "detail_level" => %{"type" => "string"},
        "semantic_available" => %{"type" => "boolean"},
        "retrieval_strategy" => @nullable_string,
        "excluded_ids_count" => %{"type" => "integer"},
        "count_only" => %{"type" => "boolean"},
        "hit_count" => %{"type" => "integer"},
        "tag_distribution" => %{"type" => "object"},
        "context_pack" => %{
          "type" => "object",
          "properties" => %{
            "task" => @nullable_object,
            "proof" => @nullable_object,
            "resume" => @nullable_object,
            "memory" => %{"type" => "array", "items" => %{"type" => "object"}},
            "citations" => %{"type" => "array", "items" => %{"type" => "object"}}
          }
        }
      }
    },
    "ck_observability" => %{
      "type" => "object",
      "properties" => %{
        "report" => %{"type" => "string"},
        "data" => %{"type" => "object"}
      }
    },
    "ck_experience_index" => %{
      "type" => "object",
      "properties" => %{
        "sessions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_experience_read" => %{
      "type" => "object",
      "properties" => %{
        "artifact_type" => %{"type" => "string"},
        "data" => %{"type" => "object"}
      }
    },
    "ck_experience_search" => %{
      "type" => "object",
      "properties" => %{
        "results" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_finding" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "finding_id" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "requires_human" => %{"type" => "boolean"},
        "precedent" => %{"type" => "array", "items" => %{"type" => "object"}},
        "resolved_finding_ids" => %{"type" => "array", "items" => %{"type" => "integer"}},
        "resolved_findings_count" => %{"type" => "integer"},
        "disposed_finding_ids" => %{"type" => "array", "items" => %{"type" => "integer"}},
        "disposed_count" => %{"type" => "integer"},
        "extends_finding_id" => @nullable_integer,
        "contradicts_finding_id" => @nullable_integer,
        "summary" => %{"type" => "string"}
      }
    },
    "ck_trace_packet" => %{
      "type" => "object",
      "properties" => %{
        "session_id" => %{"type" => "integer"},
        "task_id" => %{"type" => "integer"},
        "events" => %{"type" => "array", "items" => %{"type" => "object"}},
        "failure_patterns" => %{"type" => "array", "items" => %{"type" => "object"}},
        "eval_candidates" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_failure_clusters" => %{
      "type" => "object",
      "properties" => %{
        "clusters" => %{"type" => "array", "items" => %{"type" => "object"}},
        "eval_candidates" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_tool_health" => %{
      "type" => "object",
      "properties" => %{
        "coverage" => %{"type" => "object"},
        "recommendations" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    },
    "ck_skill_evolution" => %{
      "type" => "object",
      "properties" => %{
        "anti_patterns" => %{"type" => "array", "items" => %{"type" => "object"}},
        "reinforced_practices" => %{"type" => "array", "items" => %{"type" => "object"}},
        "suggested_skill_document" => %{"type" => "string"},
        "guidance" => %{"type" => "object"},
        "merge_strategy" => %{"type" => "object"},
        "validation" => %{
          "type" => "object",
          "properties" => %{
            "accepted" => %{"type" => "boolean"},
            "checks" => %{"type" => "object"},
            "held_in_cluster_count" => %{"type" => "integer"},
            "held_out_cluster_count" => %{"type" => "integer"},
            "notes" => %{"type" => "array", "items" => %{"type" => "string"}}
          }
        },
        "install" => %{
          "type" => "object",
          "properties" => %{
            "applied" => %{"type" => "boolean"},
            "skill_name" => %{"type" => "string"},
            "path" => %{"type" => "string"},
            "backup_path" => %{"type" => "string"},
            "validation" => %{"type" => "object"}
          }
        }
      }
    },
    "ck_fs_ls" => %{
      "type" => "object",
      "properties" => %{
        "entries" => %{"type" => "array", "items" => %{"type" => "object"}},
        "path" => %{"type" => "string"}
      }
    },
    "ck_fs_read" => %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string"},
        "content" => %{"type" => "string"},
        "start_line" => %{"type" => "integer"},
        "total_lines" => %{"type" => "integer"}
      }
    },
    "ck_fs_find" => %{
      "type" => "object",
      "properties" => %{
        "results" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_fs_grep" => %{
      "type" => "object",
      "properties" => %{
        "matches" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_worktree_list" => %{
      "type" => "object",
      "properties" => %{
        "worktrees" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_worktree_switch" => %{
      "type" => "object",
      "properties" => %{
        "switched" => %{"type" => "boolean"},
        "worktree_path" => %{"type" => "string"},
        "branch" => %{"type" => "string"}
      }
    },
    "ck_checkpoint_create" => %{
      "type" => "object",
      "properties" => %{
        "checkpoint_id" => %{"type" => "integer"},
        "type" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "created_at" => %{"type" => "string"}
      }
    },
    "ck_checkpoint_restore" => %{
      "type" => "object",
      "properties" => %{
        "restored" => %{"type" => "boolean"},
        "checkpoint_id" => %{"type" => "integer"},
        "summary" => %{"type" => "string"}
      }
    },
    "ck_checkpoint_list" => %{
      "type" => "object",
      "properties" => %{
        "checkpoints" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_git_diff" => %{
      "type" => "object",
      "properties" => %{
        "base_ref" => @nullable_string,
        "head_ref" => @nullable_string,
        "diff" => %{"type" => "string"},
        "files_changed" => %{"type" => "integer"},
        "validation" => %{"type" => "object"}
      }
    },
    "ck_git_commit" => %{
      "type" => "object",
      "properties" => %{
        "sha" => %{"type" => "string"},
        "message" => %{"type" => "string"},
        "validation" => %{"type" => "object"},
        "error" => %{"type" => "string"}
      }
    },
    "ck_git_status" => %{
      "type" => "object",
      "properties" => %{
        "branch" => %{"type" => "string"},
        "status" => %{"type" => "object"},
        "findings_correlation" => %{"type" => "object"}
      }
    },
    "ck_review_submit" => %{
      "type" => "object",
      "properties" => %{
        "review_id" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "review_url" => @nullable_string,
        "title" => %{"type" => "string"}
      }
    },
    "ck_review_status" => %{
      "type" => "object",
      "properties" => %{
        "review_id" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "decision" => %{"type" => "string"},
        "reviewer_notes" => %{"type" => "string"},
        "review_url" => @nullable_string
      }
    },
    "ck_review_feedback" => %{
      "type" => "object",
      "properties" => %{
        "review_id" => %{"type" => "integer"},
        "decision" => %{"type" => "string"},
        "updated" => %{"type" => "boolean"}
      }
    },
    "ck_regression_result" => %{
      "type" => "object",
      "properties" => %{
        "result_id" => %{"type" => "integer"},
        "recorded" => %{"type" => "boolean"},
        "engine" => %{"type" => "string"},
        "flow_name" => %{"type" => "string"},
        "outcome" => %{"type" => "string"}
      }
    },
    "ck_memory_search" => %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        "count" => %{"type" => "integer"},
        "detail_level" => %{"type" => "string"},
        "semantic_available" => %{"type" => "boolean"},
        "records" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "record_type" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "summary" => %{"type" => "string"},
              "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
              "source_type" => @nullable_string,
              "source_id" => @nullable_string,
              "session_id" => @nullable_integer,
              "task_id" => @nullable_integer,
              "inserted_at" => %{"type" => "string"},
              "score" => %{"type" => "number"},
              "body" => @nullable_string,
              "metadata" => @nullable_object
            }
          }
        }
      }
    },
    "ck_memory_record" => %{
      "type" => "object",
      "properties" => %{
        "recorded" => %{"type" => "boolean"},
        "memory_id" => %{"type" => "integer"},
        "record_type" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "session_id" => @nullable_integer,
        "task_id" => @nullable_integer
      }
    },
    "ck_goal" => %{
      "type" => "object",
      "properties" => %{
        "goal_id" => %{"type" => "integer"},
        "goal" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "horizon" => %{"type" => "string"},
        "progress_note" => %{"type" => "string"},
        "goals" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_memory_archive" => %{
      "type" => "object",
      "properties" => %{
        "archived" => %{"type" => "boolean"},
        "memory_id" => %{"type" => "integer"}
      }
    },
    "ck_budget" => %{
      "type" => "object",
      "properties" => %{
        "decision" => %{"type" => "string"},
        "session_id" => %{"type" => "integer"},
        "mode" => %{"type" => "string"},
        "remaining_session_cents" => %{"type" => "integer"},
        "remaining_daily_cents" => %{"type" => "integer"},
        "projected_cost_cents" => %{"type" => "integer"},
        "headroom_cents" => %{"type" => "integer"},
        "token_overhead" => %{"type" => "object"}
      }
    },
    "ck_route" => %{
      "type" => "object",
      "properties" => %{
        "recommended" => %{"type" => "array", "items" => %{"type" => "object"}},
        "task" => %{"type" => "string"},
        "risk_tier" => %{"type" => "string"}
      }
    },
    "ck_delegate" => %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string"},
        "session_id" => %{"type" => "integer"},
        "agent" => %{"type" => "string"},
        "mode" => %{"type" => "string"},
        "result_ref" => %{"type" => "string"},
        "package_root" => %{"type" => "string"},
        "result_length" => %{"type" => "integer"}
      }
    },
    "ck_result_peek" => %{
      "type" => "object",
      "properties" => %{
        "output" => %{"type" => "string"},
        "bytes_read" => %{"type" => "integer"},
        "total_bytes" => %{"type" => "integer"},
        "truncated" => %{"type" => "boolean"}
      }
    },
    "ck_cost_optimizer" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "suggestions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "comparisons" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_deployment_advisor" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "platforms" => %{"type" => "array", "items" => %{"type" => "object"}},
        "files_created" => %{"type" => "array", "items" => %{"type" => "string"}},
        "dns_instructions" => %{"type" => "object"}
      }
    },
    "ck_outcome_tracker" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "recorded" => %{"type" => "boolean"},
        "outcomes" => %{"type" => "array", "items" => %{"type" => "object"}},
        "entries" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_token_audit" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "word_counts" => %{"type" => "object"},
        "token_estimates" => %{"type" => "object"},
        "duplicates" => %{"type" => "array", "items" => %{"type" => "object"}},
        "recommendations" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    },
    "ck_skill_list" => %{
      "type" => "object",
      "properties" => %{
        "skills" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "description" => %{"type" => "string"},
              "scope" => %{"type" => "string"}
            }
          }
        },
        "total" => %{"type" => "integer"}
      }
    },
    "ck_skill_load" => %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string"},
        "content" => %{"type" => "string"},
        "resources" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    },
    "ck_skill_validate" => %{
      "type" => "object",
      "properties" => %{
        "valid" => %{"type" => "boolean"},
        "errors" => %{"type" => "array", "items" => %{"type" => "string"}},
        "skill_name" => %{"type" => "string"}
      }
    },
    "ck_load_resources" => %{
      "type" => "object",
      "properties" => %{
        "resources" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "uri" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "text" => %{"type" => "string"}
            }
          }
        }
      }
    },
    "ck_mcp_discover" => %{
      "type" => "object",
      "properties" => %{
        "tools" => %{"type" => "array", "items" => %{"type" => "object"}},
        "server_url" => %{"type" => "string"},
        "total" => %{"type" => "integer"}
      }
    },
    "ck_attach" => %{
      "type" => "object",
      "properties" => %{
        "attached" => %{"type" => "boolean"},
        "host" => %{"type" => "string"},
        "files_created" => %{"type" => "array", "items" => %{"type" => "string"}},
        "hooks_installed" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    },
    "ck_session_digest" => %{
      "type" => "object",
      "properties" => %{
        "digest_type" => %{"type" => "string"},
        "session_id" => %{"type" => "integer"},
        "tasks_completed" => %{"type" => "integer"},
        "findings_raised" => %{"type" => "integer"},
        "budget_spent_cents" => %{"type" => "integer"},
        "reviews_pending" => %{"type" => "integer"},
        "highlights" => %{"type" => "object"}
      }
    },
    "ck_rollback" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "task_id" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "sha" => %{"type" => "string"},
        "reverted" => %{"type" => "boolean"},
        "snapshots" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_loop" => %{
      "type" => "object",
      "required" => ["session_id", "task_id", "status", "contract", "iterations"],
      "properties" => %{
        "session_id" => %{"type" => "integer"},
        "task_id" => %{"type" => "integer"},
        "contract_id" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "stop_reason" => %{"type" => ["string", "null"]},
        "contract" => %{"type" => "object"},
        "iteration_count" => %{"type" => "integer"},
        "cost_cents" => %{"type" => "integer"},
        "best_metric" => %{"type" => ["number", "null"]},
        "iterations" => %{"type" => "array", "items" => %{"type" => "object"}},
        "decision" => %{"type" => "object"}
      }
    },
    "ck_workspace_agent" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "agent_id" => %{"type" => "integer"},
        "name" => %{"type" => "string"},
        "role" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "agents" => %{"type" => "array", "items" => %{"type" => "object"}},
        "health" => %{"type" => "object"}
      }
    },
    "ck_copilot" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "events" => %{"type" => "array", "items" => %{"type" => "object"}},
        "presence" => %{"type" => "array", "items" => %{"type" => "object"}},
        "published" => %{"type" => "boolean"}
      }
    },
    "ck_external_service" => %{
      "type" => "object",
      "properties" => %{
        "mode" => %{"type" => "string"},
        "recorded" => %{"type" => "boolean"},
        "summary" => %{"type" => "object"},
        "rate_limits" => %{"type" => "object"},
        "services" => %{"type" => "array", "items" => %{"type" => "object"}}
      }
    },
    "ck_task" => %{
      "type" => "object",
      "properties" => %{
        "task_id" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "session_id" => %{"type" => "integer"},
        "risk_tier" => %{"type" => "string"},
        "claimed" => %{"type" => "boolean"},
        "run_id" => %{"type" => "integer"},
        "completed" => %{"type" => "boolean"},
        "recorded" => %{"type" => "boolean"},
        "count" => %{"type" => "integer"},
        "results" => %{"type" => "array", "items" => %{"type" => "object"}},
        "reported" => %{"type" => "boolean"}
      }
    },
    "ck_session" => %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "risk_tier" => %{"type" => "string"},
        "workspace_id" => %{"type" => "integer"},
        "sessions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "total" => %{"type" => "integer"},
        "switched" => %{"type" => "boolean"},
        "project_root" => %{"type" => "string"}
      }
    }
  }

  @doc "Returns the output schema map for a given tool name."
  def schema_for(tool_name) when is_binary(tool_name) do
    Map.get(@schemas, tool_name, generic_schema())
  end

  @doc "Returns the full schemas map."
  def schemas, do: @schemas

  @doc "Returns all tool names that have an output schema defined."
  def tool_names, do: Map.keys(@schemas)

  @doc "Injects outputSchema into a tool definition map."
  def inject(tool_def) when is_map(tool_def) do
    name = Map.get(tool_def, "name")

    schema =
      case Map.get(@schemas, name) do
        nil -> generic_schema()
        s -> s
      end

    tool_def
    |> Map.put("outputSchema", schema)
    |> Map.put("annotations", ControlKeel.MCP.Annotations.for_tool(name))
  end

  @doc "Injects outputSchema into a list of tool definitions."
  def inject_all(tools) when is_list(tools) do
    Enum.map(tools, &inject/1)
  end

  defp generic_schema do
    %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string"},
        "data" => %{"type" => "object"}
      }
    }
  end
end
