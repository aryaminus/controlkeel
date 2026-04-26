defmodule ControlKeel.Intent.ExecutionPostureTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent

  import ControlKeel.IntentFixtures

  test "prefers typed runtime for regulated or critical briefs" do
    brief = execution_brief_fixture()
    posture = Intent.execution_posture(brief)

    assert posture["exploration_surface"] == "virtual_workspace"
    assert posture["state_surface"] == "typed_storage"
    assert posture["api_execution_surface"] == "typed_runtime"
    assert posture["mutation_surface"] == "shell_sandbox"
    assert posture["shell_role"] == "broad_fallback_only"
    assert posture["clearance_focus"] == ["bash", "file_write", "network", "deploy", "secrets"]
  end

  test "keeps lower-risk software briefs hybrid while preserving read-only discovery" do
    brief =
      execution_brief_fixture(
        payload: %{
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "Source code and test fixtures only.",
          "recommended_stack" => "Phoenix monolith with repo-local tests"
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software"
        }
      )

    posture = Intent.execution_posture(brief)

    assert posture["exploration_surface"] == "virtual_workspace"
    assert posture["state_surface"] == "typed_storage"
    assert posture["api_execution_surface"] == "typed_runtime_or_shell"
    assert posture["shell_role"] == "repo_local_fallback"
    assert posture["clearance_focus"] == ["file_write", "network", "deploy", "secrets"]
    refute Map.has_key?(posture, "code_mode_policy")
  end

  test "recommends a headless typed runtime when API-heavy work is not approval-gated" do
    project_root =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-intent-runtime-catalog-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(project_root)
    File.mkdir_p!(project_root)

    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "Cloudflare Sync",
          "idea" => "Build a Cloudflare Workers MCP sync workflow for external APIs",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "Webhook payloads, API responses, and MCP tool results.",
          "recommended_stack" => "Cloudflare Workers + D1 + R2 + webhook integrations",
          "acceptance_criteria" => [
            "The worker syncs external API data into a typed runtime.",
            "The runtime keeps intermediate MCP responses out of transcript context."
          ],
          "next_step" => "Stand up the worker runtime and test the MCP bridge."
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Low latency, Cloudflare deploy"
          }
        }
      )

    recommendation = Intent.runtime_recommendation(brief, project_root: project_root)

    assert recommendation["strategy"] == "headless_runtime"
    assert recommendation["recommended_integration"]["id"] == "cloudflare-workers"

    assert recommendation["recommended_integration"]["runtime_export_command"] ==
             "controlkeel runtime export cloudflare-workers"

    assert recommendation["recommended_integration"]["availability"] == "catalog"
  end

  test "prefers headless runtime for search and execute code-mode API orchestration" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "API Control Plane",
          "idea" =>
            "Use a search and execute code-mode workflow to inspect an OpenAPI spec, then run a single-shot orchestration against matching endpoints.",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "OpenAPI schema and API responses only.",
          "recommended_stack" => "Typed runtime with code-mode search+execute adapter"
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Use code-mode search execute flow for API orchestration"
          }
        }
      )

    posture = Intent.execution_posture(brief)

    assert posture["code_mode_policy"]["sandbox_required"] == true

    assert posture["code_mode_policy"]["default_denied_capabilities"] == [
             "filesystem",
             "network",
             "secrets",
             "shell",
             "deploy"
           ]

    recommendation = Intent.runtime_recommendation(brief)

    assert recommendation["strategy"] == "headless_runtime"
  end

  test "prefers executor when the brief emphasizes typed integration discovery" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "Executor Tool Router",
          "idea" =>
            "Use Executor as a typed integration runtime to discover OpenAPI and GraphQL tools, describe schemas, and execute them outside transcript context.",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "OpenAPI specs, GraphQL schemas, and MCP tool descriptions only.",
          "recommended_stack" => "Executor typed runtime for integration discovery and execution"
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Executor-style typed discovery for OpenAPI, GraphQL, and MCP"
          }
        }
      )

    recommendation = Intent.runtime_recommendation(brief)

    assert recommendation["strategy"] == "headless_runtime"
    assert recommendation["recommended_integration"]["id"] == "executor"

    assert recommendation["recommended_integration"]["runtime_export_command"] ==
             "controlkeel runtime export executor"
  end

  test "prefers virtual bash when the brief emphasizes virtual workspace discovery" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "Repo Discovery Loop",
          "idea" =>
            "Use a virtual bash runtime to search the repo with a read-only virtual workspace, grep files, and keep shell as a sandboxed fallback for package commands and tests.",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "Source code, fixture files, and build scripts only.",
          "recommended_stack" =>
            "Virtual workspace discovery plus governed bash runtime export for repo-local execution",
          "next_step" =>
            "Export the runtime, use filesystem search first, and only drop to sandboxed shell when mutation is required."
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Just-bash-style repo search with sandboxed shell fallback"
          }
        }
      )

    recommendation = Intent.runtime_recommendation(brief)

    assert recommendation["strategy"] == "headless_runtime"
    assert recommendation["recommended_integration"]["id"] == "virtual-bash"

    assert recommendation["recommended_integration"]["runtime_export_command"] ==
             "controlkeel runtime export virtual-bash"
  end

  test "prefers an already attached host when the brief needs review-first execution" do
    brief = execution_brief_fixture()

    provider_status = %{
      "selected_source" => "agent_bridge",
      "selected_provider" => "openai",
      "attached_agents" => [
        %{"id" => "codex-cli"},
        %{"id" => "opencode"}
      ],
      "runtime_hints" => [
        %{"agent_id" => "codex-cli"},
        %{"agent_id" => "opencode"}
      ]
    }

    recommendation = Intent.runtime_recommendation(brief, provider_status: provider_status)

    assert recommendation["strategy"] == "attach_client"
    assert recommendation["recommended_integration"]["id"] == "opencode"
    assert recommendation["recommended_integration"]["availability"] == "attached"
  end

  test "marks headless runtime recommendations as configured when a runtime bundle exists" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "Cloudflare Sync",
          "idea" => "Build a Cloudflare Workers MCP sync workflow for external APIs",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "Webhook payloads, API responses, and MCP tool results.",
          "recommended_stack" => "Cloudflare Workers + D1 + R2 + webhook integrations",
          "acceptance_criteria" => [
            "The worker syncs external API data into a typed runtime.",
            "The runtime keeps intermediate MCP responses out of transcript context."
          ],
          "next_step" => "Stand up the worker runtime and test the MCP bridge."
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Low latency, Cloudflare deploy"
          }
        }
      )

    provider_status = %{
      "selected_source" => "heuristic",
      "selected_provider" => "heuristic",
      "attached_agents" => [],
      "runtime_hints" => []
    }

    recommendation =
      Intent.runtime_recommendation(
        brief,
        provider_status: provider_status,
        available_runtimes: ["cloudflare-workers"]
      )

    assert recommendation["recommended_integration"]["id"] == "cloudflare-workers"
    assert recommendation["recommended_integration"]["availability"] == "configured"
  end
end
