defmodule ControlKeel.CLI.Parser do
  @moduledoc false

  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI.Help

  @init_switches [
    project_root: :string,
    industry: :string,
    agent: :string,
    idea: :string,
    features: :string,
    budget: :string,
    users: :string,
    data: :string,
    project_name: :string,
    org: :string,
    workspace: :string,
    no_attach: :boolean,
    json: :boolean
  ]
  @attach_switches [
    project_root: :string,
    mcp_only: :boolean,
    no_native: :boolean,
    with_skills: :boolean,
    scope: :string,
    json: :boolean
  ]
  @status_switches [format: :string, json: :boolean, project_root: :string]
  @doctor_switches [project_root: :string, format: :string, json: :boolean]
  @capabilities_switches [format: :string, json: :boolean]
  @update_switches [
    apply: :boolean,
    sync_attached: :boolean,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @context_switches [
    session_id: :integer,
    task_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @validate_switches [
    content: :string,
    kind: :string,
    path: :string,
    session_id: :integer,
    task_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @findings_switches [
    severity: :string,
    status: :string,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @findings_translate_switches [
    session_id: :integer,
    severity: :string,
    json: :boolean,
    project_root: :string
  ]
  @proofs_switches [
    session_id: :integer,
    task_id: :integer,
    deploy_ready: :boolean,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @mcp_switches [project_root: :string, json: :boolean]
  @memory_search_switches [session_id: :integer, type: :string, json: :boolean]
  @deploy_analyze_switches [project_root: :string, json: :boolean]
  @deploy_cost_switches [
    stack: :string,
    tier: :string,
    needs_db: :boolean,
    db_tier: :string,
    bandwidth: :integer,
    storage: :integer,
    json: :boolean
  ]
  @cost_optimize_switches [
    session_id: :integer,
    provider: :string,
    model: :string,
    json: :boolean
  ]
  @cost_compare_switches [tokens: :integer, json: :boolean]
  @precommit_check_switches [
    project_root: :string,
    domain_pack: :string,
    enforce: :boolean,
    json: :boolean
  ]
  @progress_switches [
    session_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @skills_list_switches [project_root: :string, target: :string, format: :string, json: :boolean]
  @skills_validate_switches [project_root: :string, json: :boolean]
  @skills_export_switches [project_root: :string, target: :string, scope: :string, json: :boolean]
  @skills_install_switches [
    project_root: :string,
    target: :string,
    scope: :string,
    json: :boolean
  ]
  @skills_doctor_switches [project_root: :string, json: :boolean, prune_duplicates: :boolean]
  @token_audit_switches [mode: :string, format: :string, project_root: :string, json: :boolean]
  @tool_groups_suggest_switches [
    project_root: :string,
    format: :string,
    apply: :boolean,
    json: :boolean
  ]
  @benchmark_run_switches [
    suite: :string,
    subjects: :string,
    baseline_subject: :string,
    scenario_slugs: :string,
    domain_pack: :string,
    json: :boolean
  ]
  @benchmark_list_switches [domain_pack: :string, format: :string, json: :boolean]
  @benchmark_compare_switches [format: :string, json: :boolean]
  @benchmark_export_switches [format: :string, json: :boolean]
  @watch_switches [interval: :integer, status: :boolean, json: :boolean]
  @obs_switches [
    by: :string,
    days: :integer,
    format: :string,
    json: :boolean,
    limit: :integer,
    stale_days: :integer,
    suite: :string,
    subjects: :string,
    baseline_subject: :string,
    scenario_slugs: :string,
    dry_run: :boolean,
    execute: :boolean,
    project_root: :string
  ]
  @obs_import_switches [
    dry_run: :boolean,
    persist: :boolean,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @audit_log_switches [format: :string, json: :boolean, project_root: :string]
  @service_account_create_switches [
    workspace_id: :integer,
    name: :string,
    scopes: :string,
    json: :boolean
  ]
  @service_account_list_switches [workspace_id: :integer, json: :boolean]
  @policy_set_create_switches [
    name: :string,
    scope: :string,
    description: :string,
    rules_file: :string,
    json: :boolean
  ]
  @policy_set_list_switches [workspace_id: :integer, json: :boolean]
  @policy_set_apply_switches [precedence: :integer, json: :boolean]
  @webhook_create_switches [
    workspace_id: :integer,
    name: :string,
    url: :string,
    events: :string,
    secret: :string,
    json: :boolean
  ]
  @webhook_list_switches [workspace_id: :integer, json: :boolean]
  @worker_start_switches [service_account_token: :string, interval: :integer, json: :boolean]
  @provider_default_switches [scope: :string, project_root: :string, json: :boolean]
  @provider_set_key_switches [value: :string, json: :boolean]
  @provider_set_base_url_switches [value: :string, json: :boolean]
  @provider_set_model_switches [value: :string, json: :boolean]
  @provider_show_switches [project_root: :string, json: :boolean]
  @provider_list_switches [project_root: :string, json: :boolean]
  @provider_doctor_switches [project_root: :string, json: :boolean]
  @bootstrap_switches [
    project_root: :string,
    ephemeral_ok: :boolean,
    agent: :string,
    json: :boolean
  ]
  @setup_switches [project_root: :string, ephemeral_ok: :boolean, agent: :string, json: :boolean]
  @runtime_export_switches [project_root: :string, json: :boolean]
  @review_diff_switches [
    base: :string,
    head: :string,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string,
    json: :boolean
  ]
  @review_pr_switches [
    patch: :string,
    url: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string,
    json: :boolean
  ]
  @review_socket_switches [
    report: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string,
    json: :boolean
  ]
  @review_plan_submit_switches [
    session_id: :integer,
    task_id: :integer,
    body_file: :string,
    stdin: :boolean,
    title: :string,
    submitted_by: :string,
    project_root: :string,
    json: :boolean
  ]
  @review_plan_open_switches [id: :integer, project_root: :string, json: :boolean]
  @review_plan_wait_switches [
    id: :integer,
    timeout: :integer,
    interval_ms: :integer,
    project_root: :string,
    json: :boolean
  ]
  @review_plan_respond_switches [
    decision: :string,
    feedback_notes: :string,
    reviewed_by: :string,
    annotations: :string,
    project_root: :string,
    json: :boolean
  ]
  @release_ready_switches [
    session_id: :integer,
    sha: :string,
    smoke_status: :string,
    artifact_source: :string,
    provenance_verified: :boolean,
    project_root: :string,
    json: :boolean
  ]
  @plugin_switches [project_root: :string, scope: :string, mode: :string, json: :boolean]
  @detach_switches [project_root: :string, json: :boolean, force: :boolean]
  @agents_doctor_switches [project_root: :string, json: :boolean]
  @cloud_doctor_switches [project_root: :string, json: :boolean]
  @cloud_connect_switches [
    project_root: :string,
    rotate: :boolean,
    enroll: :string,
    name: :string,
    invite: :string,
    json: :boolean
  ]
  @telemetry_enable_switches [project_root: :string, level: :string, json: :boolean]
  @telemetry_disable_switches [project_root: :string, json: :boolean]
  @mcp_registry_list_switches [project_root: :string, json: :boolean]
  @mcp_registry_check_switches [project_root: :string, attested: :boolean, json: :boolean]
  @mcp_guardrails_switches [project_root: :string, json: :boolean]
  @user_create_switches [project_root: :string, email: :string, name: :string, json: :boolean]
  @org_create_switches [
    project_root: :string,
    name: :string,
    slug: :string,
    default_workspace: :boolean,
    json: :boolean
  ]
  @org_list_switches [project_root: :string, json: :boolean]
  @org_budget_set_switches [
    project_root: :string,
    cents: :integer,
    clear: :boolean,
    json: :boolean
  ]
  @org_budget_show_switches [project_root: :string, json: :boolean]
  @org_invite_switches [project_root: :string, email: :string, role: :string, json: :boolean]
  @org_members_switches [project_root: :string, json: :boolean]
  @workspace_create_switches [
    project_root: :string,
    org: :string,
    name: :string,
    slug: :string,
    json: :boolean
  ]
  @run_cloud_agent_switches [
    project_root: :string,
    runtime: :string,
    budget_cents: :integer,
    scopes: :string,
    note: :string,
    user_id: :integer,
    repo_url: :string,
    branch: :string,
    commit_sha: :string,
    dispatch: :boolean,
    json: :boolean
  ]
  @eval_list_switches [project_root: :string, json: :boolean]
  @eval_run_switches [project_root: :string, suite: :string, json: :boolean]
  @audit_export_switches [
    project_root: :string,
    workspace: :string,
    org: :string,
    since: :string,
    until: :string,
    out: :string,
    template: :string,
    sign: :boolean,
    signing_key_env: :string,
    json: :boolean
  ]
  @baseline_compute_switches [workspace_id: :integer, window_days: :integer, json: :boolean]
  @workspace_tool_policy_get_switches [workspace_id: :integer, json: :boolean]
  @workspace_tool_policy_set_switches [
    workspace_id: :integer,
    mode: :string,
    tools: :string,
    json: :boolean
  ]
  @selfhost_switches [project_root: :string, json: :boolean]
  @govern_bind_github_switches [
    project_root: :string,
    workspace_id: :integer,
    owner: :string,
    repo: :string,
    default_branch: :string,
    installation_id: :string,
    json: :boolean
  ]
  @govern_unbind_github_switches [
    project_root: :string,
    workspace_id: :integer,
    owner: :string,
    repo: :string,
    json: :boolean
  ]
  @govern_list_github_switches [workspace_id: :integer, json: :boolean]
  @cloud_sync_push_switches [project_root: :string, workspace: :string, json: :boolean]
  @cloud_sync_pull_switches [project_root: :string, workspace: :string, json: :boolean]
  @cloud_sync_migrate_switches [project_root: :string, json: :boolean]
  @selfhost_pack_switches [project_root: :string, output: :string, json: :boolean]
  @agents_discover_switches [
    project_root: :string,
    max_depth: :integer,
    json: :boolean
  ]
  @agents_list_switches [project_root: :string, format: :string, json: :boolean]
  @route_agent_switches [
    task: :string,
    risk_tier: :string,
    budget_remaining_cents: :integer,
    allowed_agents: :string,
    domain_pack: :string,
    format: :string,
    json: :boolean
  ]
  @task_claim_switches [execution_mode: :string, json: :boolean]
  @task_heartbeat_switches [progress: :integer, note: :string, json: :boolean]
  @task_checks_switches [checks: :string, json: :boolean]
  @task_report_switches [status: :string, output: :string, metadata: :string, json: :boolean]
  @agent_run_switches [
    project_root: :string,
    agent: :string,
    mode: :string,
    sandbox: :string,
    json: :boolean
  ]
  @session_list_switches [format: :string, json: :boolean]
  @session_switch_switches [format: :string, json: :boolean]
  @sandbox_status_switches [format: :string, json: :boolean]
  @outcome_record_switches [format: :string, json: :boolean]
  @outcome_score_switches [format: :string, json: :boolean]
  @outcome_leaderboard_switches [format: :string, json: :boolean]

  def parse(argv) when is_list(argv) do
    case scoped_help_args(argv) do
      {:help, args} ->
        {:ok, %{command: :help, options: %{}, args: args}}

      :not_help ->
        parse_command(argv)
    end
  end

  defp scoped_help_args([flag]) when flag in ["--help", "-h"], do: {:help, []}

  defp scoped_help_args(argv) do
    if Enum.any?(argv, &(&1 in ["--help", "-h"])) do
      args = Enum.reject(argv, &(&1 in ["--help", "-h"]))
      {:help, args}
    else
      :not_help
    end
  end

  defp parse_command(argv) do
    case argv do
      [] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["--help"] ->
        {:ok, %{command: :help, options: %{}, args: []}}

      ["-h"] ->
        {:ok, %{command: :help, options: %{}, args: []}}

      ["--version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["-V"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["-v"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["serve"] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["doctor" | rest] ->
        parse_with_switches(:doctor, rest, @doctor_switches)

      ["capabilities" | rest] ->
        parse_with_switches(:capabilities, rest, @capabilities_switches)

      ["init" | rest] ->
        parse_with_switches(:init, rest, @init_switches)

      ["setup" | rest] ->
        parse_with_switches(:setup, rest, @setup_switches)

      ["attach", "doctor" | rest] ->
        parse_with_switches(:attach_doctor, rest, @agents_doctor_switches)

      ["attach", agent | rest] ->
        if agent in Integration.attachable_ids() do
          parse_attach(agent, rest)
        else
          {:error, ControlKeel.CLI.usage_text()}
        end

      ["detach", agent | rest] ->
        if agent in Integration.attachable_ids() do
          parse_detach(agent, rest)
        else
          {:error, ControlKeel.CLI.usage_text()}
        end

      ["runtime", "export", runtime_id | rest] ->
        parse_runtime_export(runtime_id, rest)

      ["review", "diff" | rest] ->
        parse_with_switches(:review_diff, rest, @review_diff_switches)

      ["review", "pr" | rest] ->
        parse_with_switches(:review_pr, rest, @review_pr_switches)

      ["review", "socket" | rest] ->
        parse_with_switches(:review_socket, rest, @review_socket_switches)

      ["review", "plan", "submit" | rest] ->
        parse_with_switches(:review_plan_submit, rest, @review_plan_submit_switches)

      ["review", "plan", "open" | rest] ->
        parse_with_switches(:review_plan_open, rest, @review_plan_open_switches)

      ["review", "plan", "wait" | rest] ->
        parse_with_switches(:review_plan_wait, rest, @review_plan_wait_switches)

      ["review", "plan", "respond", review_id | rest] ->
        parse_review_plan_respond(review_id, rest)

      ["release-ready" | rest] ->
        parse_with_switches(:release_ready, rest, @release_ready_switches)

      ["plugin", "export", plugin | rest] ->
        parse_plugin_command(:plugin_export, plugin, rest)

      ["plugin", "install", plugin | rest] ->
        parse_plugin_command(:plugin_install, plugin, rest)

      ["agents", "doctor" | rest] ->
        parse_with_switches(:agents_doctor, rest, @agents_doctor_switches)

      ["cloud", "doctor" | rest] ->
        parse_with_switches(:cloud_doctor, rest, @cloud_doctor_switches)

      ["cloud", "connect" | rest] ->
        parse_with_switches(:cloud_connect, rest, @cloud_connect_switches)

      ["cloud", "push" | rest] ->
        parse_with_switches(:cloud_sync_push, rest, @cloud_sync_push_switches)

      ["cloud", "pull" | rest] ->
        parse_with_switches(:cloud_sync_pull, rest, @cloud_sync_pull_switches)

      ["cloud", "migrate" | rest] ->
        parse_with_switches(:cloud_sync_migrate, rest, @cloud_sync_migrate_switches)

      ["govern", "bind", "github" | rest] ->
        parse_with_switches(:govern_bind_github, rest, @govern_bind_github_switches)

      ["govern", "unbind", "github" | rest] ->
        parse_with_switches(:govern_unbind_github, rest, @govern_unbind_github_switches)

      ["govern", "list", "github" | rest] ->
        parse_with_switches(:govern_list_github, rest, @govern_list_github_switches)

      ["selfhost", "pack" | rest] ->
        parse_with_switches(:selfhost_pack, rest, @selfhost_pack_switches)

      ["selfhost", "verify" | rest] ->
        parse_with_switches(:selfhost_verify, rest, @selfhost_switches)

      ["selfhost", "manifest" | rest] ->
        parse_with_switches(:selfhost_manifest, rest, @selfhost_switches)

      ["selfhost", "install-guide" | rest] ->
        parse_with_switches(:selfhost_install_guide, rest, @selfhost_switches)

      ["telemetry", "enable" | rest] ->
        parse_with_switches(:telemetry_enable, rest, @telemetry_enable_switches)

      ["telemetry", "disable" | rest] ->
        parse_with_switches(:telemetry_disable, rest, @telemetry_disable_switches)

      ["mcp", "registry", "list" | rest] ->
        parse_with_switches(:mcp_registry_list, rest, @mcp_registry_list_switches)

      ["mcp", "guardrails", "list" | rest] ->
        parse_with_switches(:mcp_guardrails_list, rest, @mcp_guardrails_switches)

      ["user", "create" | rest] ->
        parse_with_switches(:user_create, rest, @user_create_switches)

      ["org", "create" | rest] ->
        parse_with_switches(:org_create, rest, @org_create_switches)

      ["org", "list" | rest] ->
        parse_with_switches(:org_list, rest, @org_list_switches)

      ["org", "budget", "set", slug | rest] ->
        case parse_with_switches(:org_budget_set, rest, @org_budget_set_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "budget", "show", slug | rest] ->
        case parse_with_switches(:org_budget_show, rest, @org_budget_show_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "invite", slug | rest] ->
        case parse_with_switches(:org_invite, rest, @org_invite_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "members", slug | rest] ->
        case parse_with_switches(:org_members, rest, @org_members_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["workspace", "create" | rest] ->
        parse_with_switches(:workspace_create, rest, @workspace_create_switches)

      ["mcp", "registry", "check", server_name | rest] ->
        case parse_with_switches(:mcp_registry_check, rest, @mcp_registry_check_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [server_name])}
          err -> err
        end

      ["agents", "list" | rest] ->
        parse_with_switches(:agents_list, rest, @agents_list_switches)

      ["route-agent" | rest] ->
        parse_with_switches(:route_agent, rest, @route_agent_switches)

      ["task", "complete", task_id] ->
        {:ok, %{command: :task_complete, options: %{}, args: [task_id]}}

      ["task", "claim", task_id | rest] ->
        parse_task_command(:task_claim, task_id, rest, @task_claim_switches)

      ["task", "heartbeat", task_id | rest] ->
        parse_task_command(:task_heartbeat, task_id, rest, @task_heartbeat_switches)

      ["task", "checks", task_id | rest] ->
        parse_task_command(:task_checks, task_id, rest, @task_checks_switches)

      ["task", "report", task_id | rest] ->
        parse_task_command(:task_report, task_id, rest, @task_report_switches)

      ["run", "task", task_id | rest] ->
        parse_run_command(:run_task, task_id, rest)

      ["run", "cloud-agent", task_id | rest] ->
        case parse_with_switches(:run_cloud_agent, rest, @run_cloud_agent_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [task_id])}
          err -> err
        end

      ["eval", "list" | rest] ->
        parse_with_switches(:eval_list, rest, @eval_list_switches)

      ["eval", "run" | rest] ->
        parse_with_switches(:eval_run, rest, @eval_run_switches)

      ["audit", "export" | rest] ->
        parse_with_switches(:audit_export, rest, @audit_export_switches)

      ["workspace", "tool-policy", "get" | rest] ->
        parse_with_switches(:workspace_tool_policy_get, rest, @workspace_tool_policy_get_switches)

      ["workspace", "tool-policy", "set" | rest] ->
        parse_with_switches(:workspace_tool_policy_set, rest, @workspace_tool_policy_set_switches)

      ["baseline", "compute" | rest] ->
        parse_with_switches(:baseline_compute, rest, @baseline_compute_switches)

      ["agents", "discover", path | rest] ->
        case parse_with_switches(:agents_discover, rest, @agents_discover_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [path])}
          err -> err
        end

      ["run", "session", session_id | rest] ->
        parse_run_command(:run_session, session_id, rest)

      ["session", "list" | rest] ->
        parse_with_switches(:session_list, rest, @session_list_switches)

      ["session", "switch", session_id | rest] ->
        case parse_with_switches(:session_switch, rest, @session_switch_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [session_id])}
          err -> err
        end

      ["registry", "sync", "acp"] ->
        {:ok, %{command: :registry_sync_acp, options: %{}, args: []}}

      ["registry", "status", "acp"] ->
        {:ok, %{command: :registry_status_acp, options: %{}, args: []}}

      ["sandbox", "status" | rest] ->
        parse_with_switches(:sandbox_status, rest, @sandbox_status_switches)

      ["sandbox", "config", adapter] ->
        {:ok, %{command: :sandbox_config, options: %{adapter: adapter}, args: []}}

      ["sandbox", "config"] ->
        {:ok, %{command: :sandbox_status, options: %{}, args: []}}

      ["status" | rest] ->
        parse_with_switches(:status, rest, @status_switches)

      ["obs"] ->
        parse_with_switches(:obs_status, [], @obs_switches)

      ["obs", "status" | rest] ->
        parse_with_switches(:obs_status, rest, @obs_switches)

      ["obs", "loop" | rest] ->
        parse_with_switches(:obs_loop_status, rest, @obs_switches)

      ["obs", "loop-status" | rest] ->
        parse_with_switches(:obs_loop_status, rest, @obs_switches)

      ["obs", "problems" | rest] ->
        parse_with_switches(:obs_problems, rest, @obs_switches)

      ["obs", "costs" | rest] ->
        parse_with_switches(:obs_costs, rest, @obs_switches)

      ["obs", "imports" | rest] ->
        parse_with_switches(:obs_imports, rest, @obs_switches)

      ["obs", "trends" | rest] ->
        parse_with_switches(:obs_trends, rest, @obs_switches)

      ["obs", "regressions" | rest] ->
        parse_with_switches(:obs_regressions, rest, @obs_switches)

      ["obs", "recommend" | rest] ->
        parse_with_switches(:obs_recommend, rest, @obs_switches)

      ["obs", "evals", "save" | rest] ->
        parse_with_switches(:obs_evals_save, rest, @obs_switches)

      ["obs", "evals", "persisted" | rest] ->
        parse_with_switches(:obs_evals_persisted, rest, @obs_switches)

      ["obs", "evals" | rest] ->
        parse_with_switches(:obs_evals, rest, @obs_switches)

      ["obs", "benchmarks", "draft" | rest] ->
        parse_with_switches(:obs_benchmark_draft, rest, @obs_switches)

      ["obs", "benchmarks", "approve", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_approve, draft_id, rest)

      ["obs", "benchmarks", "reject", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_reject, draft_id, rest)

      ["obs", "benchmarks", "archive", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_archive, draft_id, rest)

      ["obs", "benchmarks", "drafts" | rest] ->
        parse_with_switches(:obs_benchmark_drafts, rest, @obs_switches)

      ["obs", "benchmarks", "materialize" | rest] ->
        parse_with_switches(:obs_benchmark_materialize, rest, @obs_switches)

      ["obs", "benchmarks", "scenarios" | rest] ->
        parse_with_switches(:obs_benchmark_scenarios, rest, @obs_switches)

      ["obs", "benchmarks", "run" | rest] ->
        parse_with_switches(:obs_benchmark_run, rest, @obs_switches)

      ["obs", "benchmarks", "history" | rest] ->
        parse_with_switches(:obs_benchmark_history, rest, @obs_switches)

      ["obs", "promotions" | rest] ->
        parse_with_switches(:obs_promotions, rest, @obs_switches)

      ["obs", "compare" | rest] ->
        parse_with_switches(:obs_compare, rest, @obs_switches)

      ["obs", "timeline" | rest] ->
        parse_obs_timeline(rest)

      ["obs", "memory-quality" | rest] ->
        parse_with_switches(:obs_memory_quality, rest, @obs_switches)

      ["obs", "memory" | rest] ->
        parse_obs_memory(rest)

      ["obs", "export", session_id | rest] ->
        parse_obs_session_command(:obs_export, session_id, rest)

      ["obs", "import", file_path | rest] ->
        parse_obs_import(file_path, rest)

      ["obs", "run", session_id | rest] ->
        parse_obs_run(session_id, rest)

      ["context" | rest] ->
        parse_with_switches(:context, rest, @context_switches)

      ["validate" | rest] ->
        parse_with_switches(:validate, rest, @validate_switches)

      ["findings", "translate" | rest] ->
        parse_with_switches(:findings_translate, rest, @findings_translate_switches)

      ["findings" | rest] ->
        parse_with_switches(:findings, rest, @findings_switches)

      ["approve", finding_id] ->
        {:ok, %{command: :approve, options: %{}, args: [finding_id]}}

      ["proofs" | rest] ->
        parse_with_switches(:proofs, rest, @proofs_switches)

      ["proof", id] ->
        {:ok, %{command: :proof, options: %{}, args: [id]}}

      ["proof", "verify", id] ->
        {:ok, %{command: :proof_verify, options: %{}, args: [id]}}

      ["audit-log", session_id | rest] ->
        parse_audit_log(session_id, rest)

      ["pause", task_id] ->
        {:ok, %{command: :pause, options: %{}, args: [task_id]}}

      ["resume", task_id] ->
        {:ok, %{command: :resume, options: %{}, args: [task_id]}}

      ["memory", "search", query | rest] ->
        parse_memory_search(query, rest)

      ["skills", "list" | rest] ->
        parse_with_switches(:skills_list, rest, @skills_list_switches)

      ["skills", "validate" | rest] ->
        parse_with_switches(:skills_validate, rest, @skills_validate_switches)

      ["skills", "export" | rest] ->
        parse_skills_subcommand(:skills_export, rest, @skills_export_switches)

      ["skills", "install" | rest] ->
        parse_skills_subcommand(:skills_install, rest, @skills_install_switches)

      ["skills", "doctor" | rest] ->
        parse_with_switches(:skills_doctor, rest, @skills_doctor_switches)

      ["token", "audit" | rest] ->
        parse_with_switches(:token_audit, rest, @token_audit_switches)

      ["tool", "groups", "suggest" | rest] ->
        parse_with_switches(:tool_groups_suggest, rest, @tool_groups_suggest_switches)

      ["benchmark", "list" | rest] ->
        parse_with_switches(:benchmark_list, rest, @benchmark_list_switches)

      ["benchmark", "run" | rest] ->
        parse_with_switches(:benchmark_run, rest, @benchmark_run_switches)

      ["benchmark", "show", id] ->
        {:ok, %{command: :benchmark_show, options: %{}, args: [id]}}

      ["benchmark", "compare", run_id | rest] ->
        parse_benchmark_compare(run_id, rest)

      ["benchmark", "import", run_id, subject, file_path] ->
        {:ok, %{command: :benchmark_import, options: %{}, args: [run_id, subject, file_path]}}

      ["benchmark", "export", run_id | rest] ->
        parse_benchmark_export(run_id, rest)

      ["service-account", "create" | rest] ->
        parse_with_switches(:service_account_create, rest, @service_account_create_switches)

      ["service-account", "list" | rest] ->
        parse_with_switches(:service_account_list, rest, @service_account_list_switches)

      ["service-account", "revoke", id] ->
        {:ok, %{command: :service_account_revoke, options: %{}, args: [id]}}

      ["service-account", "rotate", id] ->
        {:ok, %{command: :service_account_rotate, options: %{}, args: [id]}}

      ["policy-set", "create" | rest] ->
        parse_with_switches(:policy_set_create, rest, @policy_set_create_switches)

      ["policy-set", "list" | rest] ->
        parse_with_switches(:policy_set_list, rest, @policy_set_list_switches)

      ["policy-set", "apply", workspace_id, policy_set_id | rest] ->
        parse_policy_set_apply(workspace_id, policy_set_id, rest)

      ["webhook", "create" | rest] ->
        parse_with_switches(:webhook_create, rest, @webhook_create_switches)

      ["webhook", "list" | rest] ->
        parse_with_switches(:webhook_list, rest, @webhook_list_switches)

      ["webhook", "replay", id] ->
        {:ok, %{command: :webhook_replay, options: %{}, args: [id]}}

      ["graph", "show", session_id] ->
        {:ok, %{command: :graph_show, options: %{}, args: [session_id]}}

      ["execute", session_id] ->
        {:ok, %{command: :execute_session, options: %{}, args: [session_id]}}

      ["worker", "start" | rest] ->
        parse_with_switches(:worker_start, rest, @worker_start_switches)

      ["provider", "list" | rest] ->
        parse_with_switches(:provider_list, rest, @provider_list_switches)

      ["provider", "show" | rest] ->
        parse_with_switches(:provider_show, rest, @provider_show_switches)

      ["provider", "doctor" | rest] ->
        parse_with_switches(:provider_doctor, rest, @provider_doctor_switches)

      ["provider", "default", source | rest] ->
        parse_provider_default(source, rest)

      ["provider", "set-key", provider | rest] ->
        parse_provider_set_key(provider, rest)

      ["provider", "set-base-url", provider | rest] ->
        parse_provider_set_base_url(provider, rest)

      ["provider", "set-model", provider | rest] ->
        parse_provider_set_model(provider, rest)

      ["provider", "set-fallback-chain" | rest] ->
        parse_provider_set_fallback_chain(rest)

      ["bootstrap" | rest] ->
        parse_with_switches(:bootstrap, rest, @bootstrap_switches)

      ["mcp" | rest] ->
        parse_with_switches(:mcp, rest, @mcp_switches)

      ["watch" | rest] ->
        parse_with_switches(:watch, rest, @watch_switches)

      ["deploy", "analyze" | rest] ->
        parse_with_switches(:deploy_analyze, rest, @deploy_analyze_switches)

      ["deploy", "cost" | rest] ->
        parse_with_switches(:deploy_cost, rest, @deploy_cost_switches)

      ["deploy", "dns", stack] ->
        {:ok, %{command: :deploy_dns, options: %{stack: stack}, args: []}}

      ["deploy", "migration", stack] ->
        {:ok, %{command: :deploy_migration, options: %{stack: stack}, args: []}}

      ["deploy", "scaling", stack] ->
        {:ok, %{command: :deploy_scaling, options: %{stack: stack}, args: []}}

      ["cost", "optimize" | rest] ->
        parse_with_switches(:cost_optimize, rest, @cost_optimize_switches)

      ["cost", "compare" | rest] ->
        parse_with_switches(:cost_compare, rest, @cost_compare_switches)

      ["precommit-check" | rest] ->
        parse_with_switches(:precommit_check, rest, @precommit_check_switches)

      ["precommit-install" | rest] ->
        parse_with_switches(:precommit_install, rest, @precommit_check_switches)

      ["precommit-uninstall" | rest] ->
        parse_with_switches(:precommit_uninstall, rest, @precommit_check_switches)

      ["progress" | rest] ->
        parse_with_switches(:progress, rest, @progress_switches)

      ["outcome", "record", session_id, outcome | rest] ->
        case parse_with_switches(:outcome_record, rest, @outcome_record_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [session_id, outcome])}
          err -> err
        end

      ["outcome", "score", agent_id | rest] ->
        case parse_with_switches(:outcome_score, rest, @outcome_score_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [agent_id])}
          err -> err
        end

      ["outcome", "leaderboard" | rest] ->
        parse_with_switches(:outcome_leaderboard, rest, @outcome_leaderboard_switches)

      ["help" | rest] ->
        {:ok, %{command: :help, options: %{}, args: rest}}

      ["version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["update" | rest] ->
        parse_with_switches(:update, rest, @update_switches)

      ["upgrade" | rest] ->
        parse_with_switches(:update, rest, @update_switches)

      _ ->
        {:error, Help.unknown_command_text(argv)}
    end
  end

  defp parse_with_switches(command, argv, switches) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: switches)

    cond do
      invalid != [] ->
        {:error, Help.command_parse_error(command, invalid, remainder, argv)}

      remainder != [] ->
        {:error, Help.command_parse_error(command, invalid, remainder, argv)}

      true ->
        {:ok, %{command: command, options: options, args: []}}
    end
  end

  defp parse_skills_subcommand(command, [target | rest] = argv, switches)
       when byte_size(target) > 0 do
    case target do
      "-" <> _ -> parse_with_switches(command, argv, switches)
      _ -> parse_with_switches(command, ["--target", target | rest], switches)
    end
  end

  defp parse_skills_subcommand(command, argv, switches) do
    parse_with_switches(command, argv, switches)
  end

  defp parse_obs_run(session_id, rest) do
    parse_obs_session_command(:obs_run, session_id, rest)
  end

  defp parse_obs_session_command(command, session_id, rest) do
    with {id, ""} <- Integer.parse(session_id),
         {:ok, parsed} <- parse_with_switches(command, rest, @obs_switches) do
      {:ok, %{parsed | args: [id]}}
    else
      _ -> {:error, "Invalid session id: #{session_id}"}
    end
  end

  defp parse_obs_benchmark_status(command, draft_id, rest) do
    with {id, ""} <- Integer.parse(draft_id),
         {:ok, parsed} <- parse_with_switches(command, rest, @obs_switches) do
      {:ok, %{parsed | args: [id]}}
    else
      _ -> {:error, "Invalid benchmark draft id: #{draft_id}"}
    end
  end

  defp parse_obs_import(file_path, rest) do
    with {:ok, parsed} <- parse_with_switches(:obs_import, rest, @obs_import_switches) do
      {:ok, %{parsed | args: [file_path]}}
    end
  end

  defp parse_obs_timeline([]), do: parse_with_switches(:obs_timeline, [], @obs_switches)

  defp parse_obs_timeline([maybe_session_id | rest]) do
    case Integer.parse(maybe_session_id) do
      {session_id, ""} ->
        with {:ok, parsed} <- parse_with_switches(:obs_timeline, rest, @obs_switches) do
          {:ok, %{parsed | args: [session_id]}}
        end

      _ ->
        parse_with_switches(:obs_timeline, [maybe_session_id | rest], @obs_switches)
    end
  end

  defp parse_obs_memory([]), do: parse_with_switches(:obs_memory, [], @obs_switches)

  defp parse_obs_memory([maybe_session_id | rest]) do
    case Integer.parse(maybe_session_id) do
      {session_id, ""} ->
        with {:ok, parsed} <- parse_with_switches(:obs_memory, rest, @obs_switches) do
          {:ok, %{parsed | args: [session_id]}}
        end

      _ ->
        parse_with_switches(:obs_memory, [maybe_session_id | rest], @obs_switches)
    end
  end

  defp parse_attach(agent, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @attach_switches)

    cond do
      invalid != [] ->
        {:error, Help.command_parse_error(:attach, invalid, remainder, argv)}

      remainder != [] ->
        {:error, Help.command_parse_error(:attach, invalid, remainder, argv)}

      true ->
        case ControlKeel.CLI.validate_attach_scope(agent, options) do
          {:ok, _scope} ->
            {:ok, %{command: :attach, options: options, args: [agent]}}

          {:error, message} ->
            {:error, message}
        end
    end
  end

  defp parse_detach(agent, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @detach_switches)

    cond do
      invalid != [] ->
        {:error, Help.command_parse_error(:detach, invalid, remainder, argv)}

      remainder != [] ->
        {:error, Help.command_parse_error(:detach, invalid, remainder, argv)}

      true ->
        {:ok, %{command: :detach, options: options, args: [agent]}}
    end
  end

  defp parse_memory_search(query, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @memory_search_switches)

    cond do
      invalid != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      remainder != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      true ->
        {:ok, %{command: :memory_search, options: options, args: [query]}}
    end
  end

  defp parse_audit_log(session_id, argv) do
    case OptionParser.parse(argv, strict: @audit_log_switches) do
      {options, [], []} ->
        {:ok, %{command: :audit_log, options: options, args: [session_id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_benchmark_export(run_id, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @benchmark_export_switches)

    cond do
      invalid != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      remainder != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      true ->
        {:ok, %{command: :benchmark_export, options: options, args: [run_id]}}
    end
  end

  defp parse_benchmark_compare(run_id, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @benchmark_compare_switches)

    cond do
      invalid != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      remainder != [] ->
        {:error, ControlKeel.CLI.usage_text()}

      true ->
        {:ok, %{command: :benchmark_compare, options: options, args: [run_id]}}
    end
  end

  defp parse_policy_set_apply(workspace_id, policy_set_id, argv) do
    case OptionParser.parse(argv, strict: @policy_set_apply_switches) do
      {options, [], []} ->
        {:ok,
         %{command: :policy_set_apply, options: options, args: [workspace_id, policy_set_id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_provider_default(source, argv) do
    case OptionParser.parse(argv, strict: @provider_default_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_default, options: options, args: [source]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_provider_set_key(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_key_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_key, options: options, args: [provider]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_provider_set_fallback_chain(argv) do
    case OptionParser.parse(argv, strict: [json: :boolean, project_root: :string]) do
      {options, providers, []} when providers != [] ->
        {:ok, %{command: :provider_set_fallback_chain, options: options, args: providers}}

      {options, [], []} ->
        {:ok, %{command: :provider_set_fallback_chain, options: options, args: []}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_provider_set_base_url(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_base_url_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_base_url, options: options, args: [provider]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_provider_set_model(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_model_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_model, options: options, args: [provider]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_runtime_export(runtime_id, argv) do
    case OptionParser.parse(argv, strict: @runtime_export_switches) do
      {options, [], []} ->
        {:ok, %{command: :runtime_export, options: options, args: [runtime_id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_review_plan_respond(review_id, argv) do
    case OptionParser.parse(argv, strict: @review_plan_respond_switches) do
      {options, [], []} ->
        {:ok, %{command: :review_plan_respond, options: options, args: [review_id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_plugin_command(command, plugin, argv) do
    allowed =
      case command do
        :plugin_export -> ~w(codex claude copilot openclaw augment droid)
        :plugin_install -> ~w(codex claude copilot openclaw)
      end

    if plugin in allowed do
      case OptionParser.parse(argv, strict: @plugin_switches) do
        {options, [], []} ->
          {:ok, %{command: command, options: options, args: [plugin]}}

        _ ->
          {:error, ControlKeel.CLI.usage_text()}
      end
    else
      {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_run_command(command, id, argv) do
    case OptionParser.parse(argv, strict: @agent_run_switches) do
      {options, [], []} ->
        {:ok, %{command: command, options: options, args: [id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end

  defp parse_task_command(command, task_id, argv, switches) do
    case OptionParser.parse(argv, strict: switches) do
      {options, [], []} ->
        {:ok, %{command: command, options: options, args: [task_id]}}

      _ ->
        {:error, ControlKeel.CLI.usage_text()}
    end
  end
end
