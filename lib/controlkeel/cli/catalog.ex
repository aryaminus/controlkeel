defmodule ControlKeel.CLI.Catalog do
  @moduledoc """
  Declarative metadata for the ControlKeel CLI command surface.

  This module is intentionally read-only. It does not parse or execute commands;
  it gives humans, agents, help text, docs, MCP, skills, hooks, and web surfaces
  a common capability map to build on without changing command behavior.
  """

  @risk_keys [
    :local_write,
    :repo_write,
    :git,
    :network,
    :cloud,
    :secrets,
    :deploy,
    :sandbox_execution
  ]

  @default_safety @risk_keys
                  |> Enum.map(&{&1, false})
                  |> Map.new()
                  |> Map.merge(%{mutates: false, idempotent: true, dry_run: false})

  def all do
    family_specs()
    |> Enum.flat_map(&expand_family/1)
    |> Enum.sort_by(&{to_string(&1.family), &1.path})
  end

  def commands, do: Enum.map(all(), & &1.command)

  def families do
    all()
    |> Enum.group_by(& &1.family)
    |> Enum.map(fn {family, entries} -> {family, Enum.map(entries, & &1.command)} end)
    |> Map.new()
  end

  def for_command(command) when is_atom(command) do
    Enum.find(all(), &(&1.command == command))
  end

  def for_command(command) when is_binary(command) do
    command
    |> String.to_existing_atom()
    |> for_command()
  rescue
    ArgumentError -> nil
  end

  def for_family(family) when is_atom(family), do: Enum.filter(all(), &(&1.family == family))

  def for_path_args(args) when is_list(args) do
    normalized = normalize_tokens(args)

    all()
    |> Enum.filter(fn entry -> path_matches?(entry.path, normalized) end)
    |> Enum.sort_by(fn entry ->
      {abs(length(concrete_path_tokens(entry.path)) - length(normalized)),
       length(concrete_path_tokens(entry.path)), entry.path}
    end)
    |> List.first()
  end

  def for_path_query(query) when is_binary(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> for_path_args()
  end

  def required_metadata_keys do
    [
      :command,
      :path,
      :family,
      :summary,
      :examples,
      :inputs,
      :outputs,
      :safety,
      :related_mcp_tools,
      :related_skills,
      :related_hooks,
      :related_plugins,
      :help_topic
    ]
  end

  def safety_keys, do: [:mutates, :idempotent, :dry_run | @risk_keys]

  defp path_matches?(path, tokens) do
    concrete = concrete_path_tokens(path)
    tokens != [] and Enum.take(concrete, length(tokens)) == tokens
  end

  defp concrete_path_tokens(path) do
    path
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.starts_with?(&1, "<") or String.starts_with?(&1, "[")))
    |> normalize_tokens()
  end

  defp normalize_tokens(tokens) do
    tokens
    |> Enum.reject(&(&1 in ["--help", "-h"]))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp expand_family(%{commands: commands} = spec) do
    Enum.map(commands, fn command ->
      overrides = Map.get(spec[:overrides] || %{}, command, %{})
      path = Map.get(overrides, :path, command_path(command))
      examples = Map.get(overrides, :examples, Map.get(spec, :examples, ["controlkeel #{path}"]))
      inputs = Map.get(overrides, :inputs, Map.get(spec, :inputs, [:flags, :project_binding]))
      outputs = Map.get(overrides, :outputs, Map.get(spec, :outputs, [:text]))

      safety =
        @default_safety
        |> Map.merge(Map.get(spec, :safety, %{}))
        |> Map.merge(Map.get(overrides, :safety, %{}))

      %{
        command: command,
        path: path,
        family: spec.family,
        summary: Map.get(overrides, :summary, spec.summary),
        examples: examples,
        inputs: inputs,
        outputs: outputs,
        safety: safety,
        related_mcp_tools:
          Map.get(overrides, :related_mcp_tools, Map.get(spec, :related_mcp_tools, [])),
        related_skills: Map.get(overrides, :related_skills, Map.get(spec, :related_skills, [])),
        related_hooks: Map.get(overrides, :related_hooks, Map.get(spec, :related_hooks, [])),
        related_plugins:
          Map.get(overrides, :related_plugins, Map.get(spec, :related_plugins, [])),
        help_topic: Map.get(overrides, :help_topic, Map.get(spec, :help_topic))
      }
    end)
  end

  defp command_path(:serve), do: "serve"
  defp command_path(:help), do: "help"
  defp command_path(:version), do: "version"
  defp command_path(:doctor), do: "doctor"
  defp command_path(:capabilities), do: "capabilities"
  defp command_path(:detach), do: "detach <agent>"

  defp command_path(:attach), do: "attach <agent>"
  defp command_path(:runtime_export), do: "runtime export <id>"
  defp command_path(:review_diff), do: "review diff"
  defp command_path(:review_pr), do: "review pr"
  defp command_path(:review_socket), do: "review socket"
  defp command_path(:review_plan_submit), do: "review plan submit"
  defp command_path(:review_plan_open), do: "review plan open"
  defp command_path(:review_plan_wait), do: "review plan wait"
  defp command_path(:review_plan_respond), do: "review plan respond <id>"
  defp command_path(:release_ready), do: "release-ready"
  defp command_path(:plugin_export), do: "plugin export <host>"
  defp command_path(:plugin_install), do: "plugin install <host>"
  defp command_path(:cloud_doctor), do: "cloud doctor"
  defp command_path(:cloud_connect), do: "cloud connect"
  defp command_path(:cloud_sync_push), do: "cloud push"
  defp command_path(:cloud_sync_pull), do: "cloud pull"
  defp command_path(:cloud_sync_migrate), do: "cloud migrate"
  defp command_path(:govern_bind_github), do: "govern bind github"
  defp command_path(:govern_unbind_github), do: "govern unbind github"
  defp command_path(:govern_list_github), do: "govern list github"
  defp command_path(:selfhost_pack), do: "selfhost pack"
  defp command_path(:selfhost_verify), do: "selfhost verify"
  defp command_path(:selfhost_manifest), do: "selfhost manifest"
  defp command_path(:selfhost_install_guide), do: "selfhost install-guide"
  defp command_path(:telemetry_enable), do: "telemetry enable"
  defp command_path(:telemetry_disable), do: "telemetry disable"
  defp command_path(:baseline_compute), do: "baseline compute"
  defp command_path(:agents_discover), do: "agents discover <path>"
  defp command_path(:audit_export), do: "audit export"
  defp command_path(:eval_list), do: "eval list"
  defp command_path(:eval_run), do: "eval run"
  defp command_path(:mcp_guardrails_list), do: "mcp guardrails list"
  defp command_path(:mcp_registry_list), do: "mcp registry list"
  defp command_path(:mcp_registry_check), do: "mcp registry check <server-name>"
  defp command_path(:agents_doctor), do: "agents doctor"
  defp command_path(:attach_doctor), do: "attach doctor"
  defp command_path(:agents_list), do: "agents list"
  defp command_path(:route_agent), do: "route-agent"
  defp command_path(:task_complete), do: "task complete <task-id>"
  defp command_path(:task_claim), do: "task claim <task-id>"
  defp command_path(:task_heartbeat), do: "task heartbeat <task-id>"
  defp command_path(:task_checks), do: "task checks <task-id>"
  defp command_path(:task_report), do: "task report <task-id>"
  defp command_path(:run_task), do: "run task <id>"
  defp command_path(:run_session), do: "run session <id>"
  defp command_path(:run_cloud_agent), do: "run cloud-agent <task-id>"
  defp command_path(:session_list), do: "session list"
  defp command_path(:session_switch), do: "session switch <session-id>"
  defp command_path(:obs_status), do: "obs status"
  defp command_path(:obs_run), do: "obs run <id>"
  defp command_path(:obs_loop_status), do: "obs loop"
  defp command_path(:obs_problems), do: "obs problems"
  defp command_path(:obs_costs), do: "obs costs"
  defp command_path(:obs_imports), do: "obs imports"
  defp command_path(:obs_trends), do: "obs trends"
  defp command_path(:obs_regressions), do: "obs regressions"
  defp command_path(:obs_recommend), do: "obs recommend"
  defp command_path(:obs_evals), do: "obs evals"
  defp command_path(:obs_evals_save), do: "obs evals save"
  defp command_path(:obs_evals_persisted), do: "obs evals persisted"
  defp command_path(:obs_benchmark_draft), do: "obs benchmarks draft"
  defp command_path(:obs_benchmark_drafts), do: "obs benchmarks drafts"
  defp command_path(:obs_benchmark_materialize), do: "obs benchmarks materialize"
  defp command_path(:obs_benchmark_scenarios), do: "obs benchmarks scenarios"
  defp command_path(:obs_benchmark_run), do: "obs benchmarks run"
  defp command_path(:obs_benchmark_history), do: "obs benchmarks history"
  defp command_path(:obs_benchmark_approve), do: "obs benchmarks approve <id>"
  defp command_path(:obs_benchmark_reject), do: "obs benchmarks reject <id>"
  defp command_path(:obs_benchmark_archive), do: "obs benchmarks archive <id>"
  defp command_path(:obs_promotions), do: "obs promotions"
  defp command_path(:obs_compare), do: "obs compare"
  defp command_path(:obs_timeline), do: "obs timeline [id]"
  defp command_path(:obs_memory), do: "obs memory [id]"
  defp command_path(:obs_memory_quality), do: "obs memory-quality"
  defp command_path(:obs_export), do: "obs export <id>"
  defp command_path(:obs_import), do: "obs import <file>"
  defp command_path(:findings_translate), do: "findings translate"
  defp command_path(:memory_search), do: "memory search <query>"
  defp command_path(:skills_list), do: "skills list"
  defp command_path(:skills_validate), do: "skills validate"
  defp command_path(:skills_export), do: "skills export"
  defp command_path(:skills_install), do: "skills install"
  defp command_path(:skills_doctor), do: "skills doctor"
  defp command_path(:token_audit), do: "token audit"
  defp command_path(:tool_groups_suggest), do: "tool groups suggest"
  defp command_path(:benchmark_list), do: "benchmark list"
  defp command_path(:benchmark_run), do: "benchmark run"
  defp command_path(:benchmark_show), do: "benchmark show <id>"
  defp command_path(:benchmark_compare), do: "benchmark compare <id>"
  defp command_path(:benchmark_import), do: "benchmark import <run-id> <subject> <json-file>"
  defp command_path(:benchmark_export), do: "benchmark export <run-id>"
  defp command_path(:provider_set_key), do: "provider set-key <provider>"
  defp command_path(:provider_set_base_url), do: "provider set-base-url <provider>"
  defp command_path(:provider_set_model), do: "provider set-model <provider>"

  defp command_path(:provider_set_fallback_chain),
    do: "provider set-fallback-chain <providers...>"

  defp command_path(:deploy_analyze), do: "deploy analyze"
  defp command_path(:deploy_cost), do: "deploy cost"
  defp command_path(:deploy_dns), do: "deploy dns <stack>"
  defp command_path(:deploy_migration), do: "deploy migration <stack>"
  defp command_path(:deploy_scaling), do: "deploy scaling <stack>"
  defp command_path(:cost_optimize), do: "cost optimize"
  defp command_path(:cost_compare), do: "cost compare"
  defp command_path(:precommit_check), do: "precommit-check"
  defp command_path(:precommit_install), do: "precommit-install"
  defp command_path(:precommit_uninstall), do: "precommit-uninstall"
  defp command_path(:outcome_record), do: "outcome record <session-id> <outcome>"
  defp command_path(:outcome_score), do: "outcome score <agent-id>"
  defp command_path(:outcome_leaderboard), do: "outcome leaderboard"

  defp command_path(command) do
    command
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp family_specs do
    [
      spec(
        :core,
        "Start CK, inspect version/help, update the binary, or bootstrap a project binding.",
        [
          :serve,
          :help,
          :version,
          :doctor,
          :capabilities,
          :update,
          :setup,
          :init,
          :bootstrap,
          :status,
          :watch
        ],
        help_topic: "getting-started",
        outputs: [:text, :json],
        related_mcp_tools: ["ck_context"],
        related_skills: ["controlkeel-governance"],
        safety: %{local_write: true, mutates: true},
        overrides: %{
          help: read_only(),
          version: read_only(),
          doctor: read_only_json(),
          capabilities: read_only_json(),
          status: read_only_json(),
          watch: read_only()
        }
      ),
      spec(
        :attach_hosts,
        "Attach supported agent hosts and verify host-native CK wiring.",
        [:attach, :detach, :attach_doctor, :agents_discover, :agents_doctor, :agents_list],
        help_topic: "attach",
        outputs: [:text, :json],
        safety: %{local_write: true, repo_write: true, mutates: true},
        related_mcp_tools: ["ck_attach", "ck_mcp_discover"],
        related_skills: ["agent-integration"],
        related_hooks: ["SessionStart", "PreToolUse", "PostToolUse", "UserPromptSubmit"],
        related_plugins: ["codex", "claude", "copilot", "openclaw"],
        examples: ["controlkeel attach codex-cli --scope project", "controlkeel attach doctor"],
        overrides: %{
          detach: %{
            summary:
              "Detach an agent host from this project and remove CK-owned MCP/config artifacts.",
            examples: [
              "controlkeel detach opencode",
              "controlkeel detach codex-cli --json",
              "controlkeel detach cursor --force"
            ],
            safety: %{local_write: true, repo_write: true, mutates: true, idempotent: true}
          },
          agents_discover: %{
            summary: "Scan a directory for agent-host configuration evidence.",
            examples: [
              "controlkeel agents discover .",
              "controlkeel agents discover ~/Developer --json"
            ],
            safety: %{local_write: false, repo_write: false, mutates: false}
          },
          agents_doctor: %{
            summary: "Inspect attached and runnable agent execution paths.",
            examples: ["controlkeel agents doctor", "controlkeel agents doctor --json"],
            safety: %{local_write: false, repo_write: false, mutates: false}
          },
          agents_list: %{
            summary: "List known agent integrations and their attached/runnable status.",
            examples: ["controlkeel agents list", "controlkeel agents list --json"],
            safety: %{local_write: false, repo_write: false, mutates: false}
          },
          attach_doctor: %{
            summary: "Check attach readiness and host-native CK wiring health.",
            examples: ["controlkeel attach doctor", "controlkeel attach doctor --json"],
            safety: %{local_write: false, repo_write: false, mutates: false}
          }
        }
      ),
      spec(
        :governance,
        "Load governed context, validate content, inspect findings, proofs, audit logs, and release gates.",
        [
          :context,
          :validate,
          :findings,
          :findings_translate,
          :approve,
          :proofs,
          :proof,
          :audit_log,
          :release_ready,
          :progress,
          :pause,
          :resume
        ],
        help_topic: "findings",
        outputs: [:text, :json, :file],
        related_mcp_tools: [
          "ck_context",
          "ck_context_pack",
          "ck_validate",
          "ck_finding",
          "ck_regression_result"
        ],
        related_skills: ["controlkeel-governance", "proof-memory", "ship-readiness"],
        examples: [
          "controlkeel context --json",
          "controlkeel validate --content '...' --kind text --json"
        ],
        overrides: %{approve: mutation(), pause: mutation(), resume: mutation()}
      ),
      spec(
        :review,
        "Submit and resolve plan, diff, PR, and external report reviews.",
        [
          :review_diff,
          :review_pr,
          :review_socket,
          :review_plan_submit,
          :review_plan_open,
          :review_plan_wait,
          :review_plan_respond
        ],
        help_topic: "review",
        inputs: [:flags, :stdin, :file, :project_binding, :runtime_env],
        outputs: [:text, :json],
        safety: %{local_write: true, network: true, mutates: true},
        related_mcp_tools: [
          "ck_review_submit",
          "ck_review_status",
          "ck_review_feedback",
          "ck_git_diff"
        ],
        related_skills: ["plan-slice", "reviewable-pr", "security-review"],
        examples: [
          "controlkeel review plan submit --stdin --json",
          "controlkeel review diff --base main --head HEAD"
        ]
      ),
      spec(
        :execution,
        "Route, claim, report, and run governed work through local, embedded, handoff, runtime, or cloud-agent paths.",
        [
          :route_agent,
          :task_complete,
          :task_claim,
          :task_heartbeat,
          :task_checks,
          :task_report,
          :run_task,
          :run_session,
          :run_cloud_agent,
          :execute_session,
          :graph_show,
          :worker_start
        ],
        help_topic: "run",
        outputs: [:text, :json],
        safety: %{
          local_write: true,
          network: true,
          cloud: true,
          sandbox_execution: true,
          mutates: true
        },
        related_mcp_tools: ["ck_route", "ck_delegate", "ck_result_peek", "ck_workspace_agent"],
        related_skills: ["orchestrate-tasks", "handoff", "cost-optimization"],
        examples: [
          "controlkeel route-agent --task 'fix bug' --json",
          "controlkeel run task 123 --agent auto --mode auto"
        ]
      ),
      spec(
        :observability,
        "Inspect telemetry, timelines, costs, memory quality, learning-loop signals, and generated benchmark candidates.",
        [
          :obs_status,
          :obs_run,
          :obs_loop_status,
          :obs_problems,
          :obs_costs,
          :obs_imports,
          :obs_trends,
          :obs_regressions,
          :obs_recommend,
          :obs_evals,
          :obs_evals_save,
          :obs_evals_persisted,
          :obs_benchmark_draft,
          :obs_benchmark_drafts,
          :obs_benchmark_approve,
          :obs_benchmark_reject,
          :obs_benchmark_archive,
          :obs_benchmark_materialize,
          :obs_benchmark_scenarios,
          :obs_benchmark_run,
          :obs_benchmark_history,
          :obs_promotions,
          :obs_compare,
          :obs_timeline,
          :obs_memory,
          :obs_memory_quality,
          :obs_export,
          :obs_import,
          :telemetry_enable,
          :telemetry_disable,
          :baseline_compute
        ],
        help_topic: "observability",
        inputs: [:flags, :file, :project_binding],
        outputs: [:text, :json, :file],
        safety: %{local_write: true, network: true, cloud: true, mutates: true, dry_run: true},
        related_mcp_tools: [
          "ck_observability",
          "ck_session_digest",
          "ck_external_service"
        ],
        related_skills: ["continual-learning", "benchmark-operator", "cost-optimization"],
        examples: ["controlkeel obs status --json", "controlkeel obs benchmarks run --dry-run"]
      ),
      spec(
        :memory_continuity,
        "Search memory and preserve continuity across sessions and worktrees.",
        [:memory_search, :session_list, :session_switch],
        help_topic: "sessions",
        outputs: [:text, :json],
        safety: %{local_write: true, mutates: true},
        related_mcp_tools: [
          "ck_memory_search",
          "ck_memory_record",
          "ck_memory_archive",
          "ck_worktree_list",
          "ck_worktree_switch"
        ],
        related_skills: ["continuity", "proof-memory"],
        examples: [
          "controlkeel memory search 'routing decision'",
          "controlkeel session switch 123"
        ]
      ),
      spec(
        :mcp_tools,
        "Run the local MCP server and inspect hosted/downstream MCP guardrails.",
        [
          :mcp,
          :mcp_registry_list,
          :mcp_registry_check,
          :mcp_guardrails_list,
          :registry_sync_acp,
          :registry_status_acp
        ],
        help_topic: "mcp",
        outputs: [:text, :json],
        safety: %{network: true},
        related_mcp_tools: ["ck_mcp_discover", "ck_tool_health", "ck_load_resources"],
        related_skills: ["agent-integration"],
        examples: ["controlkeel mcp --project-root /abs/path", "controlkeel mcp registry list"]
      ),
      spec(
        :skills_plugins_hooks,
        "List, validate, install, and export skills, plugins, hooks, adaptive tool groups, and token audits.",
        [
          :skills_list,
          :skills_validate,
          :skills_export,
          :skills_install,
          :skills_doctor,
          :plugin_export,
          :plugin_install,
          :token_audit,
          :tool_groups_suggest
        ],
        help_topic: "skills",
        outputs: [:text, :json, :file],
        safety: %{local_write: true, repo_write: true, mutates: true, dry_run: true},
        related_mcp_tools: [
          "ck_skill_list",
          "ck_skill_load",
          "ck_skill_validate",
          "ck_token_audit"
        ],
        related_skills: ["agent-integration", "cli-for-agents"],
        related_hooks: ["SessionStart", "PreToolUse", "PostToolUse", "UserPromptSubmit"],
        related_plugins: ["codex", "claude", "copilot", "openclaw", "augment", "droid"],
        examples: [
          "controlkeel skills list --json",
          "controlkeel tool groups suggest --format json"
        ]
      ),
      spec(
        :cloud_selfhost,
        "Operate cloud sync, workspace enrollment, enterprise orgs, audit exports, and self-host bundles.",
        [
          :cloud_doctor,
          :cloud_connect,
          :audit_export,
          :user_create,
          :org_create,
          :org_list,
          :org_budget_set,
          :org_budget_show,
          :org_invite,
          :org_members,
          :workspace_create,
          :service_account_create,
          :service_account_list,
          :service_account_revoke,
          :service_account_rotate,
          :policy_set_create,
          :policy_set_list,
          :policy_set_apply,
          :cloud_sync_push,
          :cloud_sync_pull,
          :cloud_sync_migrate,
          :govern_bind_github,
          :govern_unbind_github,
          :govern_list_github,
          :selfhost_pack,
          :selfhost_verify,
          :selfhost_manifest,
          :selfhost_install_guide,
          :webhook_create,
          :webhook_list,
          :webhook_replay
        ],
        help_topic: "cloud",
        outputs: [:text, :json, :file],
        safety: %{local_write: true, network: true, cloud: true, secrets: true, mutates: true},
        related_mcp_tools: ["ck_external_service", "ck_budget"],
        related_skills: ["compliance-audit", "domain-audit"],
        examples: ["controlkeel cloud doctor", "controlkeel selfhost verify"]
      ),
      spec(
        :providers_budget,
        "Configure provider brokerage and inspect cost optimization choices.",
        [
          :provider_list,
          :provider_show,
          :provider_doctor,
          :provider_default,
          :provider_set_key,
          :provider_set_base_url,
          :provider_set_model,
          :provider_set_fallback_chain,
          :cost_optimize,
          :cost_compare,
          :workspace_tool_policy_get,
          :workspace_tool_policy_set
        ],
        help_topic: "providers",
        outputs: [:text, :json],
        safety: %{local_write: true, secrets: true, mutates: true},
        related_mcp_tools: ["ck_budget", "ck_cost_optimizer"],
        related_skills: ["cost-optimization"],
        examples: ["controlkeel provider doctor", "controlkeel cost compare --tokens 50000"]
      ),
      spec(
        :sandbox_security_code_mode,
        "Inspect sandbox adapters, precommit policy checks, security gates, and governed code execution posture.",
        [
          :sandbox_status,
          :sandbox_config,
          :precommit_check,
          :precommit_install,
          :precommit_uninstall
        ],
        help_topic: "security",
        outputs: [:text, :json],
        safety: %{
          local_write: true,
          repo_write: true,
          git: true,
          sandbox_execution: true,
          mutates: true
        },
        related_mcp_tools: ["ck_execute_code", "ck_validate", "ck_rollback"],
        related_skills: ["security-review", "agent-pattern-verification"],
        examples: [
          "controlkeel sandbox status",
          "controlkeel precommit-check --domain-pack software"
        ]
      ),
      spec(
        :benchmarks_harness,
        "Run validation evals, benchmark suites, import manual outputs, and export benchmark results.",
        [
          :eval_list,
          :eval_run,
          :benchmark_list,
          :benchmark_run,
          :benchmark_show,
          :benchmark_compare,
          :benchmark_import,
          :benchmark_export
        ],
        help_topic: "benchmarks",
        inputs: [:flags, :file, :project_binding],
        outputs: [:text, :json, :csv, :openeval, :file],
        safety: %{local_write: true, mutates: true, dry_run: true},
        related_mcp_tools: ["ck_regression_result"],
        related_skills: ["benchmark-operator"],
        examples: [
          "controlkeel eval run --suite governance-regression",
          "controlkeel benchmark run --suite host_comparison_v1 --subjects null_policy_baseline,controlkeel_validate --baseline-subject null_policy_baseline",
          "controlkeel benchmark compare <run-id> --json",
          # --format openeval emits ONE bundle document, not a bare ResultSet:
          # {"suite": <EvalSuite>, "result_set": <ResultSet>}, conforming to
          # the EvalPort/OpenEval interchange spec (github.com/adhabnr-ux/evalport).
          "controlkeel benchmark export <run-id> --format openeval"
        ]
      ),
      spec(
        :deployment_portability,
        "Analyze deployment posture, export runtime bundles, and inspect DNS, migrations, scaling, and hosting costs.",
        [
          :deploy_analyze,
          :deploy_cost,
          :deploy_dns,
          :deploy_migration,
          :deploy_scaling,
          :runtime_export
        ],
        help_topic: "deploy",
        outputs: [:text, :json, :file],
        safety: %{local_write: true, repo_write: true, deploy: true, mutates: true, dry_run: true},
        related_mcp_tools: ["ck_deployment_advisor"],
        related_skills: ["ship-readiness"],
        examples: [
          "controlkeel deploy analyze --project-root .",
          "controlkeel runtime export devin"
        ]
      ),
      spec(
        :learning_loop,
        "Record outcomes and surface learning-loop scores for routing and continuous improvement.",
        [:outcome_record, :outcome_score, :outcome_leaderboard],
        help_topic: "learning",
        outputs: [:text, :json],
        safety: %{local_write: true, mutates: true},
        related_mcp_tools: ["ck_outcome_tracker", "ck_experience_search", "ck_skill_evolution"],
        related_skills: ["continual-learning"],
        examples: ["controlkeel outcome record 1 success", "controlkeel outcome leaderboard"]
      )
    ]
  end

  defp spec(family, summary, commands, opts) do
    opts
    |> Map.new()
    |> Map.merge(%{family: family, summary: summary, commands: commands})
  end

  defp read_only, do: %{safety: %{local_write: false, mutates: false}, outputs: [:text]}

  defp read_only_json,
    do: %{safety: %{local_write: false, mutates: false}, outputs: [:text, :json]}

  defp mutation, do: %{safety: %{mutates: true, local_write: true}}
end
