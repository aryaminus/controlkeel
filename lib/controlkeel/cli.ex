defmodule ControlKeel.CLI do
  @moduledoc false

  alias ControlKeel.ACPRegistry
  alias ControlKeel.AgentExecution
  alias ControlKeel.AgentIntegration
  alias ControlKeel.AttachedAgentSync
  alias ControlKeel.Analytics
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.Budget.CostOptimizer
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.CodexConfig
  alias ControlKeel.Distribution
  alias ControlKeel.Deployment.Advisor
  alias ControlKeel.Deployment.HostingCost
  alias ControlKeel.Governance
  alias ControlKeel.Governance.AgentMonitor
  alias ControlKeel.Governance.CircuitBreaker
  alias ControlKeel.Governance.PreCommitHook
  alias ControlKeel.Governance.Socket, as: GovernanceSocket
  alias ControlKeel.Help
  alias ControlKeel.Intent
  alias ControlKeel.Findings.PlainEnglish
  alias ControlKeel.Learning.OutcomeTracker
  alias ControlKeel.LocalProject
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.PolicyTraining
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProtocolAccess
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ReviewBridge
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Proxy
  alias ControlKeel.RuntimePaths
  alias ControlKeel.SetupAdvisor
  alias ControlKeel.Skills
  alias ControlKeel.TaskAugmentation
  alias ControlKeel.WorkspaceContext
  alias ControlKeelWeb.Endpoint

  @init_switches [
    industry: :string,
    agent: :string,
    idea: :string,
    features: :string,
    budget: :string,
    users: :string,
    data: :string,
    project_name: :string,
    no_attach: :boolean
  ]
  @attach_switches [
    mcp_only: :boolean,
    no_native: :boolean,
    with_skills: :boolean,
    scope: :string
  ]
  @findings_switches [severity: :string, status: :string]
  @findings_translate_switches [session_id: :integer, severity: :string]
  @proofs_switches [session_id: :integer, task_id: :integer, deploy_ready: :boolean]
  @mcp_switches [project_root: :string]
  @memory_search_switches [session_id: :integer, type: :string]
  @deploy_analyze_switches [project_root: :string]
  @deploy_cost_switches [
    stack: :string,
    tier: :string,
    needs_db: :boolean,
    db_tier: :string,
    bandwidth: :integer,
    storage: :integer
  ]
  @cost_optimize_switches [session_id: :integer, provider: :string, model: :string]
  @cost_compare_switches [tokens: :integer]
  @precommit_check_switches [project_root: :string, domain_pack: :string, enforce: :boolean]
  @progress_switches [session_id: :integer]
  @circuit_breaker_switches [agent_id: :string]
  @skills_list_switches [project_root: :string, target: :string]
  @skills_validate_switches [project_root: :string]
  @skills_export_switches [project_root: :string, target: :string, scope: :string]
  @skills_install_switches [project_root: :string, target: :string, scope: :string]
  @skills_doctor_switches [project_root: :string]
  @benchmark_run_switches [
    suite: :string,
    subjects: :string,
    baseline_subject: :string,
    scenario_slugs: :string,
    domain_pack: :string
  ]
  @benchmark_list_switches [domain_pack: :string]
  @benchmark_export_switches [format: :string]
  @policy_train_switches [type: :string]
  @watch_switches [interval: :integer]
  @audit_log_switches [format: :string]
  @service_account_create_switches [workspace_id: :integer, name: :string, scopes: :string]
  @service_account_list_switches [workspace_id: :integer]
  @policy_set_create_switches [
    name: :string,
    scope: :string,
    description: :string,
    rules_file: :string
  ]
  @policy_set_list_switches [workspace_id: :integer]
  @policy_set_apply_switches [precedence: :integer]
  @webhook_create_switches [
    workspace_id: :integer,
    name: :string,
    url: :string,
    events: :string,
    secret: :string
  ]
  @webhook_list_switches [workspace_id: :integer]
  @worker_start_switches [service_account_token: :string, interval: :integer]
  @provider_default_switches [scope: :string, project_root: :string]
  @provider_set_key_switches [value: :string]
  @provider_set_base_url_switches [value: :string]
  @provider_set_model_switches [value: :string]
  @provider_show_switches [project_root: :string]
  @provider_list_switches [project_root: :string]
  @provider_doctor_switches [project_root: :string]
  @bootstrap_switches [project_root: :string, ephemeral_ok: :boolean, agent: :string]
  @setup_switches [project_root: :string, ephemeral_ok: :boolean, agent: :string]
  @runtime_export_switches [project_root: :string]
  @review_diff_switches [
    base: :string,
    head: :string,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_pr_switches [
    patch: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_socket_switches [
    report: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_plan_submit_switches [
    session_id: :integer,
    task_id: :integer,
    body_file: :string,
    stdin: :boolean,
    title: :string,
    submitted_by: :string,
    json: :boolean
  ]
  @review_plan_open_switches [id: :integer, json: :boolean]
  @review_plan_wait_switches [
    id: :integer,
    timeout: :integer,
    interval_ms: :integer,
    json: :boolean
  ]
  @review_plan_respond_switches [
    decision: :string,
    feedback_notes: :string,
    reviewed_by: :string,
    annotations: :string,
    json: :boolean
  ]
  @release_ready_switches [
    session_id: :integer,
    sha: :string,
    smoke_status: :string,
    artifact_source: :string,
    provenance_verified: :boolean,
    project_root: :string
  ]
  @govern_install_switches [project_root: :string]
  @plugin_switches [project_root: :string, scope: :string, mode: :string]
  @agents_doctor_switches [project_root: :string]
  @agent_run_switches [project_root: :string, agent: :string, mode: :string, sandbox: :string]

  def standalone_argv do
    cond do
      standalone_wrapper_runtime?() ->
        plain_arguments()

      Code.ensure_loaded?(Burrito.Util.Args) and function_exported?(Burrito.Util.Args, :argv, 0) ->
        Burrito.Util.Args.argv()

      true ->
        System.argv()
    end
  end

  def parse(argv) when is_list(argv) do
    case argv do
      [] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["serve"] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["init" | rest] ->
        parse_with_switches(:init, rest, @init_switches)

      ["setup" | rest] ->
        parse_with_switches(:setup, rest, @setup_switches)

      ["attach", agent | rest] ->
        if agent in AgentIntegration.attachable_ids() do
          parse_attach(agent, rest)
        else
          {:error, usage_text()}
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

      ["govern", "install", "github" | rest] ->
        parse_with_switches(:govern_install_github, rest, @govern_install_switches)

      ["plugin", "export", plugin | rest] ->
        parse_plugin_command(:plugin_export, plugin, rest)

      ["plugin", "install", plugin | rest] ->
        parse_plugin_command(:plugin_install, plugin, rest)

      ["agents", "doctor" | rest] ->
        parse_with_switches(:agents_doctor, rest, @agents_doctor_switches)

      ["run", "task", task_id | rest] ->
        parse_run_command(:run_task, task_id, rest)

      ["run", "session", session_id | rest] ->
        parse_run_command(:run_session, session_id, rest)

      ["registry", "sync", "acp"] ->
        {:ok, %{command: :registry_sync_acp, options: %{}, args: []}}

      ["registry", "status", "acp"] ->
        {:ok, %{command: :registry_status_acp, options: %{}, args: []}}

      ["sandbox", "status"] ->
        {:ok, %{command: :sandbox_status, options: %{}, args: []}}

      ["sandbox", "config", adapter] ->
        {:ok, %{command: :sandbox_config, options: %{adapter: adapter}, args: []}}

      ["sandbox", "config"] ->
        {:ok, %{command: :sandbox_status, options: %{}, args: []}}

      ["status"] ->
        {:ok, %{command: :status, options: %{}, args: []}}

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
        parse_with_switches(:skills_export, rest, @skills_export_switches)

      ["skills", "install" | rest] ->
        parse_with_switches(:skills_install, rest, @skills_install_switches)

      ["skills", "doctor" | rest] ->
        parse_with_switches(:skills_doctor, rest, @skills_doctor_switches)

      ["benchmark", "list" | rest] ->
        parse_with_switches(:benchmark_list, rest, @benchmark_list_switches)

      ["benchmark", "run" | rest] ->
        parse_with_switches(:benchmark_run, rest, @benchmark_run_switches)

      ["benchmark", "show", id] ->
        {:ok, %{command: :benchmark_show, options: %{}, args: [id]}}

      ["benchmark", "import", run_id, subject, file_path] ->
        {:ok, %{command: :benchmark_import, options: %{}, args: [run_id, subject, file_path]}}

      ["benchmark", "export", run_id | rest] ->
        parse_benchmark_export(run_id, rest)

      ["policy", "list"] ->
        {:ok, %{command: :policy_list, options: %{}, args: []}}

      ["policy", "train" | rest] ->
        parse_with_switches(:policy_train, rest, @policy_train_switches)

      ["policy", "show", id] ->
        {:ok, %{command: :policy_show, options: %{}, args: [id]}}

      ["policy", "promote", id] ->
        {:ok, %{command: :policy_promote, options: %{}, args: [id]}}

      ["policy", "archive", id] ->
        {:ok, %{command: :policy_archive, options: %{}, args: [id]}}

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

      ["circuit-breaker", "status" | rest] ->
        parse_with_switches(:circuit_breaker_status, rest, @circuit_breaker_switches)

      ["circuit-breaker", "trip", agent_id] ->
        {:ok, %{command: :circuit_breaker_trip, options: %{agent_id: agent_id}, args: []}}

      ["circuit-breaker", "reset", agent_id] ->
        {:ok, %{command: :circuit_breaker_reset, options: %{agent_id: agent_id}, args: []}}

      ["agents", "monitor" | rest] ->
        parse_with_switches(:agents_monitor, rest, @circuit_breaker_switches)

      ["outcome", "record", session_id, outcome] ->
        {:ok, %{command: :outcome_record, options: %{}, args: [session_id, outcome]}}

      ["outcome", "score", agent_id] ->
        {:ok, %{command: :outcome_score, options: %{}, args: [agent_id]}}

      ["outcome", "leaderboard"] ->
        {:ok, %{command: :outcome_leaderboard, options: %{}, args: []}}

      ["help" | rest] ->
        {:ok, %{command: :help, options: %{}, args: rest}}

      ["version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      _ ->
        {:error, Help.unknown_command_text(argv)}
    end
  end

  def app_required?(%{command: command}) when command in [:help, :version], do: false
  def app_required?(_parsed), do: true

  def server_mode?(%{command: :serve}), do: true
  def server_mode?(_parsed), do: false

  def execute(parsed, opts \\ []) do
    printer = Keyword.get(opts, :printer, &IO.puts/1)
    error_printer = Keyword.get(opts, :error_printer, fn line -> IO.puts(:stderr, line) end)

    project_root =
      opts
      |> Keyword.get(:project_root, File.cwd!())
      |> ProjectRoot.resolve()

    case run_command(parsed, project_root) do
      {:ok, lines} ->
        Enum.each(List.wrap(lines), printer)
        0

      :ok ->
        0

      {:error, message} ->
        error_printer.(message)
        1
    end
  end

  def version do
    Application.spec(:controlkeel, :vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  def usage_text, do: Help.usage_text()

  def run_command(%{command: :serve}, _project_root), do: :ok
  def run_command(%{command: :help, args: args}, _project_root), do: {:ok, [Help.render(args)]}
  def run_command(%{command: :version}, _project_root), do: {:ok, ["ControlKeel #{version()}"]}

  def run_command(%{command: :init, options: options}, project_root) do
    project_root = resolve_project_root(options, project_root)
    attrs = Enum.into(options, %{}, fn {key, value} -> {Atom.to_string(key), value} end)
    no_attach = Keyword.get(options, :no_attach, false)

    case LocalProject.init(attrs, project_root) do
      {:ok, binding, :created} ->
        base_lines = [
          "Initialized ControlKeel for #{binding["project_root"]}",
          "Project binding: #{ProjectBinding.path(project_root)}",
          "MCP wrapper: #{ProjectBinding.mcp_wrapper_path(project_root)}"
        ]

        attach_lines =
          if no_attach do
            ["To attach to Claude Code: controlkeel attach claude-code"]
          else
            case auto_attach_claude_code(project_root) do
              {:ok, _result} ->
                [
                  "Attached ControlKeel to Claude Code.",
                  "Verified with `claude mcp get controlkeel`."
                ]

              {:skip, reason} ->
                ["To attach to Claude Code: controlkeel attach claude-code  (#{reason})"]

              {:error, _reason} ->
                ["To attach to Claude Code: controlkeel attach claude-code"]
            end
          end

        {:ok, base_lines ++ attach_lines}

      {:ok, binding, :existing} ->
        {:ok,
         [
           "ControlKeel is already initialized for session ##{binding["session_id"]}.",
           "Project binding: #{ProjectBinding.path(project_root)}",
           "MCP wrapper: #{ProjectBinding.mcp_wrapper_path(project_root)}"
         ]}

      {:error, reason} ->
        {:error, "Failed to initialize ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :setup, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    overrides = %{"agent" => options[:agent] || "claude"}

    case ensure_local_project(root, overrides) do
      {:ok, _binding, session, mode} ->
        snapshot = SetupAdvisor.snapshot(root)

        {:ok,
         [
           "ControlKeel setup",
           "Project root: #{snapshot["project_root"]}",
           "Session: #{session.title} (##{session.id})",
           "Binding mode: #{mode}",
           SetupAdvisor.detected_hosts_line(snapshot),
           SetupAdvisor.attached_agents_line(snapshot),
           "Provider source: #{snapshot["provider_status"]["selected_source"]}.",
           "Provider: #{snapshot["provider_status"]["selected_provider"]}.",
           "Core loop: #{SetupAdvisor.core_loop()}",
           "Recommended next steps:"
         ] ++
           Enum.map(SetupAdvisor.recommended_attach_lines(snapshot), &"  - #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  - ")}

      {:error, reason} ->
        {:error, "Failed to set up ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["claude-code"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "claude-code"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached_agent} <-
           ClaudeCLI.attach_local(
             project_root,
             command_spec.command,
             command_spec.args
           ),
         updated_binding <-
           ProjectBinding.update_attached_agent(binding, "claude_code", attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(
             updated_binding,
             project_root,
             mode: binding_write_mode(binding)
           ) do
      emit_attach_succeeded(binding, project_root, attached_agent)

      {:ok,
       [
         "Attached ControlKeel to Claude Code.",
         "Verified with `claude mcp get controlkeel`."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("claude-code", project_root, options) ++
         attach_guidance_lines("claude-code")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["cursor"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "cursor"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached} <- attach_to_cursor(command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "cursor", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Cursor.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Cursor to activate."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("cursor", project_root, options) ++ attach_guidance_lines("cursor")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Cursor: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["windsurf"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "windsurf"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached} <- attach_to_windsurf(command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "windsurf", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Windsurf.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Windsurf to activate."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("windsurf", project_root, options) ++
         attach_guidance_lines("windsurf")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Windsurf: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["codex-cli"], options: options}, project_root) do
    scope = attach_scope("codex-cli", options)

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "codex-cli"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         config_path <- CodexConfig.path_for_scope(project_root, scope),
         {:ok, _} <- CodexConfig.write(config_path, command_spec),
         {:ok, install_result} <- maybe_install_codex_native(project_root, scope, options),
         attached <-
           %{
             "server_name" => "controlkeel",
             "ide" => "codex-cli",
             "config_path" => config_path,
             "scope" => scope,
             "target" => "codex",
             "destination" => install_result && install_result[:destination],
             "compat_destination" => install_result && install_result[:compat_destination],
             "agents_destination" => install_result && install_result[:agent_destination],
             "commands_destination" => install_result && install_result[:commands_destination],
             "config_destination" => config_path,
             "controlkeel_version" => to_string(Application.spec(:controlkeel, :vsn) || "0.1.0"),
             "attached_at" =>
               DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
           },
         updated <- ProjectBinding.update_attached_agent(binding, "codex-cli", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Codex CLI.",
         "MCP server written to #{config_path}.",
         "Restart Codex CLI to activate."
       ] ++
         bootstrap_lines(project_root) ++
         codex_attach_install_lines(install_result) ++ attach_guidance_lines("codex-cli")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Codex CLI: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["kiro", "kilo", "amp", "augment", "opencode", "gemini-cli", "cline"] do
    config_path_fn = %{
      "kiro" => &kiro_mcp_config_path/0,
      "kilo" => &kilo_config_path/0,
      "amp" => &amp_mcp_config_path/0,
      "augment" => &augment_mcp_config_path/0,
      "opencode" => &opencode_mcp_config_path/0,
      "gemini-cli" => &gemini_cli_config_path/0,
      "cline" => &cline_mcp_config_path/0
    }

    display_name = %{
      "kiro" => "Kiro",
      "kilo" => "Kilo Code",
      "amp" => "Amp",
      "augment" => "Augment / Auggie CLI",
      "opencode" => "OpenCode",
      "gemini-cli" => "Gemini CLI",
      "cline" => "Cline"
    }

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => agent}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         config_path <- config_path_fn[agent].(),
         {:ok, attached} <- write_ide_mcp_config(config_path, "controlkeel", command_spec, agent),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to #{display_name[agent]}.",
         "MCP server written to #{attached["config_path"]}.",
         if(agent == "augment",
           do:
             "Restart Auggie or use `auggie --mcp-config #{attached["config_path"]}` to activate.",
           else: "Restart #{display_name[agent]} to activate."
         )
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines(agent, project_root, options) ++
         attach_guidance_lines(agent)}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to #{display_name[agent]}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["goose"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "goose"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached} <- attach_to_goose(command_spec, project_root),
         updated <- ProjectBinding.update_attached_agent(binding, "goose", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Goose.",
         "Goose extension written to #{attached["config_path"]}.",
         "Restart Goose to activate."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("goose", project_root, options) ++
         attach_guidance_lines("goose")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Goose: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["continue"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "continue"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached} <-
           write_continue_mcp_config(continue_config_path(), "controlkeel", command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "continue", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Continue.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Continue to activate."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("continue", project_root, options) ++
         attach_guidance_lines("continue")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Continue: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["aider"], options: options}, project_root) do
    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => "aider"}),
         command_spec <- ProjectBinding.mcp_command_spec(project_root),
         {:ok, attached} <- attach_to_aider(command_spec, project_root),
         updated <- ProjectBinding.update_attached_agent(binding, "aider", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       [
         "Attached ControlKeel to Aider.",
         "MCP config written to #{attached["config_path"]}."
       ] ++
         bootstrap_lines(project_root) ++
         native_attach_lines("aider", project_root, options) ++
         attach_guidance_lines("aider")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Aider: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["roo-code", "hermes-agent", "openclaw", "droid", "forge", "pi"] do
    target =
      %{
        "roo-code" => "roo-native",
        "hermes-agent" => "hermes-native",
        "openclaw" => "openclaw-native",
        "droid" => "droid-bundle",
        "forge" => "forge-acp",
        "pi" => "pi-native"
      }[agent]

    scope = attach_scope(agent, options)

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => agent}),
         {:ok, result} <- attach_bundle_target(target, project_root, scope, options),
         attached_agent <- bundled_attached_agent(agent, target, scope, result),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      {:ok,
       bundle_attach_lines(agent, result) ++
         bootstrap_lines(project_root) ++
         attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["vscode", "copilot"] do
    scope = attach_scope(agent, options)

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(project_root, %{"agent" => agent}),
         {:ok, install_result} <- Skills.install("github-repo", project_root, scope: scope),
         attached_agent <- github_repo_attached_agent(agent, scope, install_result),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ) do
      lines =
        case install_result do
          %{destination: destination} ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Installed project bundle at #{destination}.",
              "Repository MCP config written under .github and .vscode."
            ] ++ bootstrap_lines(project_root)

          %ControlKeel.Skills.SkillExportPlan{} = plan ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Output: #{plan.output_dir}"
            ] ++ bootstrap_lines(project_root)
        end

      {:ok, lines ++ attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["open-swe"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("open-swe-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Open SWE runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Open SWE runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["devin"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("devin-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Devin runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Devin runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: [runtime_id]}, _project_root) do
    {:error, "Unknown runtime export target: #{runtime_id}"}
  end

  def run_command(%{command: :review_diff, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, base_ref} <- required_option(options, :base, "--base"),
         {:ok, head_ref} <- required_option(options, :head, "--head"),
         {:ok, review} <-
           Governance.review_diff(
             base_ref,
             head_ref,
             governance_opts(options, root)
           ) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_pr, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, patch} <- patch_input(options),
         {:ok, review} <- Governance.review_patch(patch, governance_opts(options, root)) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_socket, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, report} <- socket_report_input(options),
         {:ok, dependency_review} <- GovernanceSocket.dependency_review(report),
         {:ok, review} <-
           Governance.review_patch(
             "",
             governance_opts(options, root)
             |> Keyword.put(:dependency_review, dependency_review)
             |> Keyword.put(:source, "socket_review")
             |> Keyword.put(:phase, "dependency_review")
           ) do
      {:ok, review_lines(review, "dependency")}
    end
  end

  def run_command(%{command: :review_plan_submit, options: options}, _project_root) do
    with {:ok, submission_body} <- review_submission_input(options),
         {:ok, attrs} <- review_submission_attrs(options, submission_body),
         {:ok, review} <- Mission.submit_review(attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "submitted",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Submitted plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}",
           "Execution gate: task remains blocked until the plan review is approved."
         ]}
      end
    else
      {:error, reason} ->
        cli_error("Failed to submit plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_open, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review_open} <-
           ReviewBridge.open_review(review_id, auto_open: ReviewBridge.auto_open_reviews?()) do
      review = review_open.review

      payload =
        review_cli_payload(review, %{
          "message" => "open",
          "browser_url" => review_open.url,
          "browser_embed" => review_open.browser_embed,
          "open_target" => review_open.open_target,
          "remote" => review_open.remote,
          "opened" => review_open.opened,
          "open_error" => review_open.open_error
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Review ##{review.id}: #{review.title}",
           "Status: #{review.status}",
           "Type: #{review.review_type}",
           "Browser URL: #{review_open.url}",
           "Browser embed: #{review_open.browser_embed}"
         ] ++
           maybe_cli_line("Open target", review_open.open_target) ++
           maybe_cli_line("Opened browser", to_string(review_open.opened)) ++
           maybe_cli_line("Open error", review_open.open_error)}
      end
    else
      {:error, :not_found} ->
        cli_error("Review not found", :not_found, options)

      {:error, reason} ->
        cli_error("Failed to open plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_wait, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review} <-
           ReviewBridge.wait_for_review(review_id,
             timeout_ms: (options[:timeout] || 120) * 1000,
             interval_ms: options[:interval_ms] || 1000
           ) do
      payload =
        review_cli_payload(review, %{
          "message" => "wait",
          "browser_url" => review_url(review.id)
        })

      case review.status do
        "approved" ->
          if options[:json] do
            {:ok, [Jason.encode!(payload)]}
          else
            {:ok,
             [
               "Plan review ##{review.id} approved.",
               "Status: #{review.status}",
               "Browser URL: #{review_url(review.id)}"
             ] ++ review_feedback_lines(review)}
          end

        "denied" ->
          cli_error(
            "Plan review ##{review.id} was denied",
            {:review_denied, review},
            options,
            payload
          )

        other ->
          cli_error(
            "Plan review ##{review.id} is still #{other}",
            {:review_pending, %{review_id: review.id, review_status: other}},
            options,
            payload
          )
      end
    else
      {:error, {:timeout, review}} ->
        cli_error(
          "Timed out waiting for plan review ##{review.id}",
          {:timeout, review},
          options,
          review_cli_payload(review, %{
            "message" => "timeout",
            "browser_url" => review_url(review.id)
          })
        )

      {:error, reason} ->
        cli_error("Failed while waiting for plan review", reason, options)
    end
  end

  def run_command(
        %{command: :review_plan_respond, args: [review_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(review_id),
         {:ok, decision} <- required_option(options, :decision, "--decision"),
         attrs <- review_response_attrs(options, decision),
         {:ok, review} <- Mission.respond_review(parsed_id, attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "responded",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Updated plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}"
         ]}
      end
    else
      {:error, :invalid_id} ->
        cli_error("Review id must be an integer", :invalid_id, options)

      {:error, reason} ->
        cli_error("Failed to respond to plan review", reason, options)
    end
  end

  def run_command(%{command: :release_ready, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, session_id} <- release_ready_session_id(options, root),
         {:ok, readiness} <-
           Governance.release_readiness(
             release_ready_opts(options, root)
             |> Map.put(:session_id, session_id)
           ) do
      {:ok, release_ready_lines(readiness)}
    end
  end

  def run_command(%{command: :govern_install_github, options: options}, project_root) do
    root = options[:project_root] || project_root

    case Governance.install_github_scaffolding(root) do
      {:ok, result} ->
        {:ok,
         [
           "Installed ControlKeel GitHub governance scaffolding.",
           "Project root: #{result["project_root"]}"
         ] ++ Enum.map(result["files"], &"  #{&1}")}

      {:error, message} ->
        {:error, message}
    end
  end

  def run_command(%{command: :plugin_export, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, target} <- plugin_target(plugin),
         {:ok, plan} <- Skills.export(target, root, scope: "export") do
      {:ok,
       [
         "Exported #{plugin} plugin bundle.",
         "Target: #{plan.target}",
         "Output: #{plan.output_dir}"
       ] ++ Enum.map(plan.instructions, &"  #{&1}")}
    else
      {:error, reason} ->
        {:error, "Failed to export plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :plugin_install, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root
    scope = options[:scope] || "project"
    mode = options[:mode] || "local"

    with {:ok, target} <- plugin_target(plugin) do
      case Skills.install(target, root, scope: scope) do
        {:ok, %{destination: destination} = result} ->
          {:ok,
           [
             "Installed #{plugin} plugin bundle.",
             "Target: #{target}",
             "Scope: #{scope}",
             "Destination: #{destination}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++
             maybe_cli_line("Marketplace", Map.get(result, :marketplace_destination))}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:ok,
           [
             "Prepared #{plugin} plugin bundle.",
             "Target: #{plan.target}",
             "Scope: #{scope}",
             "Output: #{plan.output_dir}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++ Enum.map(plan.instructions, &"  #{&1}")}

        {:error, reason} ->
          {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :agents_doctor, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    doctor = AgentExecution.doctor(root)
    snapshot = SetupAdvisor.snapshot(root)

    agent_lines =
      Enum.map(doctor["agents"], fn agent ->
        "  #{agent.id}: #{agent.execution_support} / #{agent.ck_runs_agent_via} attached=#{if(agent.attached, do: "yes", else: "no")} runnable=#{if(agent.runnable, do: "yes", else: "no")}"
      end)

    {:ok,
     [
       "Agent execution doctor",
       "Project root: #{doctor["project_root"]}",
       SetupAdvisor.detected_hosts_line(snapshot),
       "Attached agents: #{if(doctor["attached_agents"] == [], do: "none", else: Enum.join(doctor["attached_agents"], ", "))}",
       "Direct ready: #{length(doctor["direct_ready"])}",
       "Handoff ready: #{length(doctor["handoff_ready"])}",
       "Runtime ready: #{length(doctor["runtime_ready"])}",
       "Core loop: #{SetupAdvisor.core_loop()}",
       "Agents:"
       | agent_lines
     ]}
  end

  def run_command(%{command: :run_task, args: [task_id], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, parsed_id} <- parse_id(task_id),
         {:ok, result} <- AgentExecution.run_task(parsed_id, agent_run_opts(options, root)) do
      {:ok, agent_execution_lines(result)}
    else
      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, {:policy_blocked, reason}} ->
        {:error, "Delegated execution blocked: #{reason}"}

      {:error, reason} ->
        {:error, "Failed to run task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :run_session, args: [session_id], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, parsed_id} <- parse_id(session_id),
         {:ok, result} <- AgentExecution.run_session(parsed_id, agent_run_opts(options, root)) do
      session_lines =
        Enum.flat_map(result["results"], fn item ->
          [
            "  task ##{item["task_id"]}: #{item["status"]} via #{item["agent_id"] || "unknown"} (#{item["mode"] || "unknown"})"
          ]
        end)

      {:ok,
       [
         "Delegated session ##{result["session_id"]}.",
         "Project root: #{result["project_root"]}",
         "Task count: #{result["task_count"]}",
         "Results:"
         | session_lines
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to run session: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :status}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, binding, session, _mode} ->
        metrics = Analytics.session_metrics(session.id) || %{}
        rolling_24h = Budget.rolling_24h_spend_cents(session.id)
        provider_status = ProviderBroker.status(project_root)
        autonomy = AutonomyLoop.session_autonomy_profile(session)
        outcome = AutonomyLoop.session_outcome_profile(session)
        improvement = AutonomyLoop.session_improvement_loop(session)
        active_task = current_session_task(session)
        workspace_context = session_workspace_context(session, project_root)
        augmentation = TaskAugmentation.build(session, active_task, workspace_context)
        security_summary = Mission.security_case_summary(session.findings)

        active_findings =
          Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))

        active_tasks = Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"]))

        {:ok,
         [
           "Session: #{session.title} (##{session.id})",
           "Risk tier: #{session.risk_tier}",
           "Budget: #{format_money(session.spent_cents)} / #{format_money(session.budget_cents)} used",
           "Rolling 24h: #{format_money(rolling_24h)} / #{format_money(session.daily_budget_cents)}",
           "Active findings: #{active_findings}",
           "Active tasks: #{active_tasks}",
           "Autonomy: #{autonomy["label"]}",
           "Outcome: #{outcome["label"]} · #{outcome["metric"]}",
           "Current task: #{(active_task && active_task.title) || "No active task"}",
           "Task augmentation: #{augmentation_status_line(augmentation)}",
           "Security cases: #{security_case_status_line(security_summary)}",
           "Funnel stage: #{Analytics.stage_label(metrics[:funnel_stage])}",
           "Time to first finding: #{format_duration(metrics[:time_to_first_finding_seconds])}",
           "Total findings: #{metrics[:total_findings] || 0}",
           "Blocked findings: #{metrics[:blocked_findings_total] || 0}",
           "Bootstrap mode: #{provider_status["bootstrap"]["mode"]}",
           "Provider source: #{provider_status["selected_source"]}",
           "Provider: #{provider_status["selected_provider"]}",
           "Auth mode: #{provider_status["selected_auth_mode"]}",
           "Auth owner: #{provider_status["selected_auth_owner"]}",
           "Execution sandbox: #{ExecutionSandbox.adapter_name([])}",
           "OpenAI responses: #{Proxy.url(session, :openai, "/v1/responses")}",
           "OpenAI chat: #{Proxy.url(session, :openai, "/v1/chat/completions")}",
           "OpenAI completions: #{Proxy.url(session, :openai, "/v1/completions")}",
           "OpenAI embeddings: #{Proxy.url(session, :openai, "/v1/embeddings")}",
           "OpenAI models: #{Proxy.url(session, :openai, "/v1/models")}",
           "OpenAI realtime: #{Proxy.realtime_url(session, :openai, "/v1/realtime")}",
           "Anthropic messages: #{Proxy.url(session, :anthropic, "/v1/messages")}"
         ] ++
           attached_agent_status_lines(binding) ++
           contextual_status_help_lines(session, active_task, active_findings, improvement)}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :findings, options: options}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        findings =
          Mission.list_session_findings(session.id, %{
            severity: options[:severity],
            status: options[:status]
          })

        security_summary = Mission.security_case_summary(findings)

        active_total =
          Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))

        filter_summary = findings_filter_summary(options)

        if findings == [] do
          {:ok,
           [
             "Findings: 0 matched#{filter_summary}",
             "Active findings in session: #{active_total}",
             "Security cases: #{security_case_status_line(security_summary)}"
           ] ++ findings_help_lines([], options)}
        else
          {:ok,
           [
             "Findings: #{length(findings)} matched#{filter_summary}",
             "Active findings in session: #{active_total}",
             "Security cases: #{security_case_status_line(security_summary)}"
           ] ++
             Enum.map(findings, fn finding ->
               "##{finding.id} [#{finding.severity}/#{finding.status}] #{finding.title} (#{finding.rule_id})"
             end) ++ findings_help_lines(findings, options)}
        end

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :approve, args: [finding_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(finding_id),
         finding when not is_nil(finding) <- Mission.get_finding(parsed_id),
         true <- finding.session_id == session.id || {:error, :wrong_session},
         {:ok, updated} <- Mission.approve_finding(finding) do
      {:ok, ["Approved finding ##{updated.id}: #{updated.title}"]}
    else
      {:error, :wrong_session} ->
        {:error, "That finding does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Finding id must be an integer."}

      nil ->
        {:error, "Finding not found."}

      {:error, reason} ->
        {:error, "Failed to approve finding: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :proofs, options: options}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        browser =
          Mission.browse_proof_bundles(%{
            session_id: options[:session_id] || session.id,
            task_id: options[:task_id],
            deploy_ready: options[:deploy_ready]
          })

        if browser.entries == [] do
          {:ok,
           [
             "Proof bundles: 0 matched#{proofs_filter_summary(options)}",
             "Session proof bundles: #{browser.total_count}",
             "Deploy-ready in view: 0"
           ] ++ proofs_help_lines([], options)}
        else
          {:ok,
           [
             "Proof bundles: #{length(browser.entries)} matched#{proofs_filter_summary(options)}",
             "Session proof bundles: #{browser.total_count}",
             "Deploy-ready in view: #{Enum.count(browser.entries, & &1.deploy_ready)}"
           ] ++
             Enum.map(browser.entries, fn proof ->
               deploy = if proof.deploy_ready, do: "deploy-ready", else: "review-required"

               "##{proof.id} v#{proof.version} [#{proof.status}] #{proof.task.title} (risk #{proof.risk_score}, #{deploy})"
             end) ++ proofs_help_lines(browser.entries, options)}
        end

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :proof, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id) do
      cond do
        proof = Mission.get_proof_bundle(parsed_id) ->
          {:ok, [Jason.encode!(proof.bundle, pretty: true)]}

        true ->
          case Mission.proof_bundle(parsed_id) do
            {:ok, bundle} -> {:ok, [Jason.encode!(bundle, pretty: true)]}
            {:error, :not_found} -> {:error, "Proof bundle or task was not found."}
          end
      end
    else
      {:error, :invalid_id} ->
        {:error, "Proof id must be an integer."}
    end
  end

  def run_command(%{command: :audit_log, args: [session_id], options: options}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         format <- options[:format] || "json",
         true <- format in ["json", "csv", "pdf"] || {:error, :invalid_format},
         {:ok, %{export: export, payload: payload}} <-
           Platform.export_audit_log(parsed_id, format) do
      lines =
        case format do
          "pdf" ->
            [
              "Audit log exported for session ##{parsed_id}.",
              "Format: pdf",
              "Checksum: #{export.checksum}",
              "Artifact: #{export.artifact_path_or_ref}"
            ]

          _ ->
            [payload]
        end

      {:ok, lines}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, :invalid_format} ->
        {:error, "Audit log format must be json, csv, or pdf."}

      {:error, :renderer_unavailable} ->
        {:error, "PDF renderer is unavailable in this runtime."}

      {:error, :not_found} ->
        {:error, "Session not found."}

      {:error, reason} ->
        {:error, "Failed to export audit log: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_list, options: options}, project_root) do
    filter_opts = benchmark_filter_opts(options[:domain_pack])
    suites = Benchmark.list_suites(filter_opts)
    runs = Benchmark.list_recent_runs(filter_opts)
    subjects = Benchmark.available_subjects(project_root)

    suite_lines =
      if suites == [] do
        [
          "Benchmark suites: 0#{benchmark_filter_summary(options)}",
          "Available subjects: #{length(subjects)}",
          "Recent runs: #{length(runs)}"
        ]
      else
        [
          "Benchmark suites: #{length(suites)}#{benchmark_filter_summary(options)}",
          "Available subjects: #{length(subjects)}",
          "Recent runs: #{length(runs)}",
          "Benchmark suites:"
          | Enum.map(suites, fn suite ->
              packs = Benchmark.domain_packs_for_suite(suite)

              "  #{suite.slug} v#{suite.version} — #{suite.name} (#{length(suite.scenarios)} scenarios; domains: #{format_domain_packs(packs)})"
            end)
        ]
      end

    subject_lines =
      [
        "",
        "Available subjects:"
        | Enum.map(subjects, fn subject ->
            "  #{subject["id"]} [#{subject["type"]}] #{subject["label"]}"
          end)
      ]

    run_lines =
      if runs == [] do
        ["", "No benchmark runs recorded yet."]
      else
        [
          "",
          "Recent runs:"
          | Enum.map(runs, fn run ->
              "  ##{run.id} #{run.suite.slug} [#{run.status}] catch #{run.catch_rate}% baseline #{run.baseline_subject}"
            end)
        ]
      end

    {:ok,
     suite_lines ++
       subject_lines ++ run_lines ++ benchmark_list_help_lines(suites, runs, subjects)}
  end

  def run_command(%{command: :benchmark_run, options: options}, project_root) do
    attrs = %{
      "suite" => options[:suite] || "vibe_failures_v1",
      "subjects" => options[:subjects],
      "baseline_subject" => options[:baseline_subject],
      "scenario_slugs" => options[:scenario_slugs],
      "domain_pack" => options[:domain_pack]
    }

    case Benchmark.run_suite(attrs, project_root) do
      {:ok, run} ->
        detail = Benchmark.run_detail_metrics(run)

        {:ok,
         [
           "Benchmark run ##{run.id} completed.",
           "Suite: #{run.suite.slug}",
           "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
           "Subjects: #{Enum.join(run.subjects, ", ")}",
           "Status: #{run.status}",
           "Catch rate: #{run.catch_rate}%",
           "Block rate: #{detail.block_rate}%",
           "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
           "Average overhead: #{format_percent(run.average_overhead_percent)}"
         ]}

      {:error, :suite_not_found} ->
        {:error, "Benchmark suite was not found."}

      {:error, reason} ->
        {:error, "Failed to run benchmark: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_show, args: [id]}, _project_root) do
    with {:ok, run_id} <- parse_id(id),
         %{} = run <- Benchmark.get_run(run_id) do
      detail = Benchmark.run_detail_metrics(run)

      subject_lines =
        run.results
        |> Enum.group_by(& &1.subject)
        |> Enum.map(fn {subject, results} ->
          catches = Enum.count(results, &(&1.findings_count > 0))
          blocked = Enum.count(results, &(&1.decision == "block"))
          "  #{subject}: #{catches} caught, #{blocked} blocked, #{length(results)} total"
        end)

      {:ok,
       [
         "Benchmark run ##{run.id}",
         "Suite: #{run.suite.name} (#{run.suite.slug})",
         "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
         "Status: #{run.status}",
         "Baseline subject: #{run.baseline_subject}",
         "Catch rate: #{run.catch_rate}%",
         "Block rate: #{detail.block_rate}%",
         "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
         "Median latency: #{format_ms(run.median_latency_ms)}",
         "Average overhead: #{format_percent(run.average_overhead_percent)}",
         "Subjects:"
         | subject_lines
       ] ++ benchmark_show_help_lines(run)}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      nil ->
        {:error, "Benchmark run not found."}
    end
  end

  def run_command(
        %{command: :benchmark_import, args: [run_id, subject, file_path]},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, contents} <- File.read(file_path),
         {:ok, payload} <- Jason.decode(contents),
         {:ok, run} <- Benchmark.import_result(parsed_id, subject, payload) do
      {:ok,
       [
         "Imported benchmark output for #{subject} into run ##{run.id}.",
         "Run status: #{run.status}",
         "Catch rate: #{run.catch_rate}%"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :enoent} ->
        {:error, "Benchmark import file was not found."}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Benchmark import file must be valid JSON: #{Exception.message(error)}"}

      {:error, :scenario_slug_required} ->
        {:error, "Benchmark import payload must include `scenario_slug`."}

      {:error, :result_not_found} ->
        {:error,
         "No matching benchmark result slot exists for that run, subject, and scenario_slug."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}

      {:error, reason} ->
        {:error, "Failed to import benchmark output: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_export, args: [run_id], options: options}, _project_root) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, output} <- Benchmark.export_run(parsed_id, options[:format] || "json") do
      {:ok, [output]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}
    end
  end

  def run_command(%{command: :policy_list}, _project_root) do
    artifacts = PolicyTraining.list_artifacts(%{"limit" => 10})
    training_runs = PolicyTraining.list_training_runs()
    active = PolicyTraining.active_artifacts_summary()

    artifact_lines =
      if artifacts == [] do
        ["No policy artifacts recorded yet."]
      else
        [
          "Policy artifacts:"
          | Enum.map(artifacts, fn artifact ->
              "  ##{artifact.id} #{artifact.artifact_type} v#{artifact.version} [#{artifact.status}] #{artifact.model_family}"
            end)
        ]
      end

    active_lines =
      [
        "",
        "Active artifacts:",
        "  router: #{format_active_artifact(active["router"])}",
        "  budget_hint: #{format_active_artifact(active["budget_hint"])}"
      ]

    training_lines =
      if training_runs == [] do
        ["", "No training runs recorded yet."]
      else
        [
          "",
          "Recent training runs:"
          | Enum.map(training_runs, fn run ->
              "  ##{run.id} #{run.artifact_type} [#{run.status}]"
            end)
        ]
      end

    {:ok, artifact_lines ++ active_lines ++ training_lines}
  end

  def run_command(%{command: :policy_train, options: options}, _project_root) do
    case PolicyTraining.start_training(%{"type" => options[:type] || "router"}) do
      {:ok, artifact} ->
        {:ok,
         [
           "Policy artifact ##{artifact.id} trained.",
           "Type: #{artifact.artifact_type}",
           "Version: #{artifact.version}",
           "Model family: #{artifact.model_family}",
           "Eligible for promotion: #{get_in(artifact.metrics, ["gates", "eligible"]) == true}"
         ]}

      {:error, :unknown_artifact_type} ->
        {:error, "Artifact type must be `router` or `budget_hint`."}

      {:error, reason} ->
        {:error, "Failed to train policy artifact: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_show, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         %{} = artifact <- PolicyTraining.get_artifact(parsed_id) do
      {:ok,
       [
         "Policy artifact ##{artifact.id}",
         "Type: #{artifact.artifact_type}",
         "Version: #{artifact.version}",
         "Status: #{artifact.status}",
         "Model family: #{artifact.model_family}",
         "Promotion eligible: #{get_in(artifact.metrics, ["gates", "eligible"]) == true}",
         Jason.encode!(artifact.metrics, pretty: true)
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Policy artifact id must be an integer."}

      nil ->
        {:error, "Policy artifact not found."}
    end
  end

  def run_command(%{command: :policy_promote, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, artifact} <- PolicyTraining.promote_artifact(parsed_id) do
      {:ok,
       [
         "Promoted policy artifact ##{artifact.id}.",
         "Type: #{artifact.artifact_type}",
         "Version: #{artifact.version}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Policy artifact id must be an integer."}

      {:error, :not_found} ->
        {:error, "Policy artifact not found."}

      {:error, {:promotion_failed, reasons}} ->
        {:error, "Promotion gate failed: #{Enum.join(List.wrap(reasons), "; ")}"}

      {:error, reason} ->
        {:error, "Failed to promote policy artifact: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_archive, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, artifact} <- PolicyTraining.archive_artifact(parsed_id) do
      {:ok,
       [
         "Archived policy artifact ##{artifact.id}.",
         "Type: #{artifact.artifact_type}",
         "Version: #{artifact.version}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Policy artifact id must be an integer."}

      {:error, :not_found} ->
        {:error, "Policy artifact not found."}

      {:error, reason} ->
        {:error, "Failed to archive policy artifact: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         scopes = options[:scopes] || "admin",
         {:ok, %{service_account: account, token: token}} <-
           Platform.create_service_account(workspace_id, %{
             "name" => name,
             "scopes" => scopes
           }) do
      {:ok,
       [
         "Created service account ##{account.id} for workspace ##{workspace_id}.",
         "Name: #{account.name}",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}",
         "Token: #{token}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      accounts = Platform.list_service_accounts(workspace_id)

      lines =
        if accounts == [] do
          ["No service accounts found for workspace ##{workspace_id}."]
        else
          [
            "Service accounts for workspace ##{workspace_id}:"
            | Enum.map(accounts, fn account ->
                "  ##{account.id} #{account.name} [#{account.status}] client: #{ProtocolAccess.oauth_client_id(account)} scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}"
              end)
          ]
        end

      {:ok, lines}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :service_account_revoke, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, account} <- Platform.revoke_service_account(parsed_id) do
      {:ok, ["Revoked service account ##{account.id}."]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to revoke service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_rotate, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, %{service_account: account, token: token}} <-
           Platform.rotate_service_account(parsed_id) do
      {:ok,
       [
         "Rotated service account ##{account.id}.",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Token: #{token}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to rotate service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_set_create, options: options}, _project_root) do
    with {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, rules} <- load_rules_payload(options[:rules_file]),
         {:ok, policy_set} <-
           Platform.create_policy_set(%{
             "name" => name,
             "scope" => options[:scope] || "workspace",
             "description" => options[:description],
             "rules" => rules
           }) do
      {:ok,
       [
         "Created policy set ##{policy_set.id}.",
         "Name: #{policy_set.name}",
         "Rules: #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_set_list, options: options}, _project_root) do
    workspace_id = options[:workspace_id]
    policy_sets = Platform.list_policy_sets()

    assignment_lines =
      if workspace_id do
        ["", "Assignments:"] ++
          Enum.map(Platform.list_workspace_policy_sets(workspace_id), fn assignment ->
            "  workspace ##{workspace_id} -> ##{assignment.policy_set_id} #{assignment.policy_set.name} precedence #{assignment.precedence}"
          end)
      else
        []
      end

    {:ok,
     [
       "Policy sets:"
       | Enum.map(policy_sets, fn policy_set ->
           "  ##{policy_set.id} #{policy_set.name} [#{policy_set.status}] #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))} rules"
         end)
     ] ++ assignment_lines}
  end

  def run_command(
        %{command: :policy_set_apply, args: [workspace_id, policy_set_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_workspace_id} <- parse_id(workspace_id),
         {:ok, parsed_policy_set_id} <- parse_id(policy_set_id),
         {:ok, assignment} <-
           Platform.apply_policy_set(parsed_workspace_id, parsed_policy_set_id, %{
             "precedence" => options[:precedence] || 100,
             "enabled" => true
           }) do
      {:ok,
       [
         "Applied policy set ##{assignment.policy_set_id} to workspace ##{assignment.workspace_id}.",
         "Precedence: #{assignment.precedence}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Workspace id and policy set id must be integers."}

      {:error, reason} ->
        {:error, "Failed to apply policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, url} <- require_string_option(options[:url], "url"),
         events <- options[:events] || Enum.join(Platform.webhook_events(), ","),
         {:ok, webhook} <-
           Platform.create_webhook(workspace_id, %{
             "name" => name,
             "url" => url,
             "secret" => options[:secret],
             "subscribed_events" => events
           }) do
      {:ok,
       [
         "Created webhook ##{webhook.id} for workspace ##{workspace_id}.",
         "Events: #{Enum.join(ControlKeel.Platform.IntegrationWebhook.event_list(webhook), ", ")}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      webhooks = Platform.list_webhooks(workspace_id)
      deliveries = Platform.list_deliveries(workspace_id)

      {:ok,
       [
         "Webhooks for workspace ##{workspace_id}:"
         | Enum.map(webhooks, fn webhook ->
             "  ##{webhook.id} #{webhook.name} [#{webhook.status}] #{webhook.url}"
           end)
       ] ++
         ["", "Recent deliveries:"] ++
         Enum.map(deliveries, fn delivery ->
           "  ##{delivery.id} #{delivery.event} [#{delivery.status}] attempts #{delivery.attempts}"
         end)}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :webhook_replay, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, delivery} <- Platform.replay_webhook(parsed_id) do
      {:ok,
       [
         "Replayed webhook ##{parsed_id}.",
         "Latest delivery status: #{delivery.status}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Webhook id must be an integer."}

      {:error, :not_found} ->
        {:error, "Webhook or delivery not found."}

      {:error, reason} ->
        {:error, "Failed to replay webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :graph_show, args: [session_id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id) do
      graph = Platform.ensure_session_graph(parsed_id)

      edge_lines =
        Enum.map(graph.edges, fn edge ->
          "  #{edge.from_task_id} -> #{edge.to_task_id} [#{edge.dependency_type}]"
        end)

      {:ok,
       [
         "Task graph for session ##{parsed_id}:",
         "Ready tasks: #{Enum.join(Enum.map(graph.ready_task_ids, &to_string/1), ", ")}",
         "Edges:"
         | edge_lines
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}
    end
  end

  def run_command(%{command: :execute_session, args: [session_id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         {:ok, graph} <- Platform.execute_session(parsed_id) do
      {:ok,
       [
         "Executed scheduling for session ##{parsed_id}.",
         "Ready tasks: #{Enum.join(Enum.map(graph.ready_task_ids, &to_string/1), ", ")}",
         "Task runs: #{length(graph.task_runs)}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to execute session: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :worker_start, options: options}, _project_root) do
    with {:ok, token} <-
           require_string_option(options[:service_account_token], "service-account-token") do
      case Platform.Worker.start(token, interval: options[:interval] || 2_000) do
        {:error, :unauthorized} ->
          {:error, "Invalid service account token."}

        other ->
          other
      end
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :provider_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Project root: #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Bootstrap mode: #{status["bootstrap"]["mode"]}",
       "Profiles:"
     ] ++
       Enum.map(status["profiles"], fn profile ->
         "  #{profile["provider"]}: configured=#{if(profile["configured"], do: "yes", else: "no")} env=#{if(profile["env_override"], do: "yes", else: "no")} default=#{if(profile["default"], do: "yes", else: "no")} model=#{profile["model"] || "n/a"} base_url=#{profile["base_url"] || "default"}"
       end)}
  end

  def run_command(%{command: :registry_sync_acp}, _project_root) do
    case ACPRegistry.sync() do
      {:ok, status} ->
        {:ok,
         [
           "Refreshed ACP registry cache.",
           "Source: #{status["registry_url"]}",
           "Fetched at: #{status["fetched_at"]}",
           "Entries: #{status["entry_count"]}",
           "Matched integrations: #{status["matched_integrations"]}",
           "Cache: #{status["cache_path"]}"
         ]}

      {:error, reason} ->
        {:error, "Failed to refresh ACP registry cache: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :registry_status_acp}, _project_root) do
    status = ACPRegistry.status()

    {:ok,
     [
       "ACP registry cache status:",
       "Source: #{status["registry_url"]}",
       "Fetched at: #{status["fetched_at"] || "never"}",
       "Entries: #{status["entry_count"]}",
       "Matched integrations: #{status["matched_integrations"]}",
       "Stale: #{if(status["stale"], do: "yes", else: "no")}",
       "Cache: #{status["cache_path"]}"
     ]}
  end

  def run_command(%{command: :sandbox_status}, _project_root) do
    adapters = ExecutionSandbox.supported_adapters()

    current_adapter_name = ExecutionSandbox.adapter_name([])

    current =
      Map.get(
        Enum.find(adapters, fn a -> a[:id] == current_adapter_name end) || %{},
        :name,
        "Unknown"
      )

    adapter_lines =
      Enum.map(adapters, fn adapter ->
        available = if adapter[:available], do: "available", else: "not available"
        marker = if adapter[:id] == ExecutionSandbox.adapter_name([]), do: " (active)", else: ""
        "  #{adapter[:name]} [#{adapter[:id]}]: #{available}#{marker}"
      end)

    {:ok,
     [
       "Execution sandbox adapters:",
       "Active: #{current}"
     ] ++ adapter_lines}
  end

  def run_command(%{command: :sandbox_config, options: %{adapter: adapter}}, _project_root) do
    valid_adapters = Enum.map(ExecutionSandbox.supported_adapters(), & &1[:id])

    if adapter in valid_adapters do
      config_path = RuntimePaths.config_path()
      config = read_json_config(config_path)
      updated = Map.put(config, "execution_sandbox", adapter)

      File.mkdir_p!(Path.dirname(config_path))
      File.write!(config_path, Jason.encode!(updated, pretty: true) <> "\n")

      {:ok, ["Execution sandbox set to: #{adapter}", "Config written to: #{config_path}"]}
    else
      {:error,
       "Unknown sandbox adapter: #{adapter}. Valid adapters: #{Enum.join(valid_adapters, ", ")}"}
    end
  end

  def run_command(%{command: :provider_show, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Provider status for #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Selected model: #{status["selected_model"] || "n/a"}",
       "Selected base URL: #{selected_base_url(status)}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Reason: #{status["reason"]}",
       "Fallback chain: #{Enum.join(status["fallback_chain"], " -> ")}"
     ] ++
       Enum.map(status["provider_chain"], fn resolution ->
         "  #{resolution["source"]}: #{resolution["provider"]} (#{resolution["model"] || "default"}) base_url=#{resolution["base_url"] || "default"} [#{resolution["auth_mode"]}/#{resolution["auth_owner"]}]"
       end)}
  end

  def run_command(%{command: :provider_doctor, options: options}, project_root) do
    root = options[:project_root] || project_root
    doctor = ProviderBroker.doctor(root)
    status = doctor["status"]

    {:ok,
     [
       "Provider doctor for #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Bootstrap mode: #{status["bootstrap"]["mode"]}"
     ] ++ Enum.map(doctor["suggestions"], &"  #{&1}")}
  end

  def run_command(%{command: :provider_default, args: [source], options: options}, project_root) do
    scope = options[:scope] || "user"
    root = options[:project_root] || project_root

    case ProviderBroker.set_default_source(source, scope: scope, project_root: root) do
      {:ok, _config} ->
        {:ok, ["Set default provider source to #{source} for #{scope} scope."]}

      {:error, reason} ->
        {:error, "Failed to set default provider source: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_base_url, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_BASE_URL")

    with {:ok, base_url} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_base_url(provider, base_url) do
      {:ok, ["Stored base URL for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_BASE_URL"}

      {:error, reason} ->
        {:error, "Failed to store provider base URL: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_model, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_MODEL")

    with {:ok, model} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_model(provider, model) do
      {:ok, ["Stored model for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_MODEL"}

      {:error, reason} ->
        {:error, "Failed to store provider model: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_key, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_KEY")

    with {:ok, key} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_key(provider, key) do
      {:ok, ["Stored provider key for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_KEY"}

      {:error, reason} ->
        {:error, "Failed to store provider key: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :bootstrap, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    overrides = %{"agent" => options[:agent] || "claude"}

    case LocalProject.load_or_bootstrap(root, overrides,
           ephemeral_ok: options[:ephemeral_ok] != false
         ) do
      {:ok, binding, session, mode} ->
        {:ok,
         [
           "Bootstrapped ControlKeel for #{binding["project_root"]}",
           "Session: #{session.title} (##{session.id})",
           "Binding mode: #{mode}",
           "Binding path: #{ProjectBinding.bootstrap_summary(root)["binding_path"]}"
         ] ++ bootstrap_lines(root)}

      {:error, reason} ->
        {:error, "Failed to bootstrap ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :pause, args: [task_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session},
         {:ok, %{task: updated, resume_packet: packet}} <- Mission.pause_task(task, "cli") do
      {:ok,
       [
         "Paused task ##{updated.id}: #{updated.title}",
         Jason.encode!(packet, pretty: true)
       ]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to pause task: #{inspect(reason)}"}

      nil ->
        {:error, "Task not found."}

      _error ->
        {:error, "Failed to pause task."}
    end
  end

  def run_command(%{command: :resume, args: [task_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session},
         {:ok, %{task: updated, resume_packet: packet}} <- Mission.resume_task(task, "cli") do
      {:ok,
       [
         "Resumed task ##{updated.id}: #{updated.title}",
         Jason.encode!(packet, pretty: true)
       ]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to resume task: #{inspect(reason)}"}

      nil ->
        {:error, "Task not found."}

      _error ->
        {:error, "Failed to resume task."}
    end
  end

  def run_command(%{command: :memory_search, args: [query], options: options}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        result =
          Memory.search(query, %{
            workspace_id: session.workspace_id,
            session_id: options[:session_id] || session.id,
            record_type: options[:type]
          })

        if result.entries == [] do
          {:ok, ["No memory records matched the search query."]}
        else
          {:ok,
           Enum.map(result.entries, fn record ->
             "[#{record.record_type}] #{record.title} (score #{Float.round(record.score, 2)})"
           end)}
        end

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root)
    selected_target = options[:target]

    skills =
      if selected_target do
        Enum.filter(analysis.skills, &(selected_target in (&1.compatibility_targets || [])))
      else
        analysis.skills
      end

    lines =
      if skills == [] do
        ["No skills available for the selected scope or target."]
      else
        Enum.flat_map(skills, fn skill ->
          targets =
            if skill.compatibility_targets == [],
              do: "mcp",
              else: Enum.join(skill.compatibility_targets, ", ")

          tools =
            if skill.required_mcp_tools == [],
              do: "none",
              else: Enum.join(skill.required_mcp_tools, ", ")

          [
            "#{skill.name} [#{skill.scope}]",
            "  #{skill.description}",
            "  targets: #{targets}",
            "  CK tools: #{tools}"
          ]
        end)
      end

    diagnostic_lines =
      if analysis.diagnostics == [] do
        []
      else
        ["", "Diagnostics:"] ++
          Enum.map(analysis.diagnostics, fn diagnostic ->
            "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
          end)
      end

    {:ok, lines ++ diagnostic_lines}
  end

  def run_command(%{command: :skills_validate, options: options}, project_root) do
    root = options[:project_root] || project_root
    result = Skills.validate(root)

    {:ok,
     [
       "Skills valid: #{if(result.valid?, do: "yes", else: "no")}",
       "Total skills: #{result.total}",
       "Warnings: #{result.warning_count}",
       "Errors: #{result.error_count}"
     ] ++
       Enum.map(result.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :skills_export, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.export(target, root, scope: options[:scope]) do
      {:ok, plan} ->
        {:ok,
         [
           "Exported #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill export target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to export skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.install(target, root, scope: options[:scope]) do
      {:ok, %{destination: destination} = result} ->
        lines = [
          "Installed #{result.target} skills.",
          "Destination: #{destination}"
        ]

        lines =
          if Map.has_key?(result, :agent_destination) do
            lines ++ ["Agent destination: #{result.agent_destination}"]
          else
            lines
          end

        {:ok, lines}

      {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
        {:ok,
         [
           "Prepared #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill install target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to install skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_doctor, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root)
    integrations = Skills.agent_integrations()
    provider_status = ProviderBroker.status(root)

    attach_clients =
      integrations
      |> Enum.filter(&(&1.support_class == "attach_client"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    runtimes =
      integrations
      |> Enum.filter(&(&1.support_class == "headless_runtime"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    frameworks =
      integrations
      |> Enum.filter(&(&1.support_class == "framework_adapter"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    {:ok,
     [
       "Project root: #{Path.expand(root)}",
       "Trusted project skills: #{if(analysis.trusted_project?, do: "yes", else: "no")}",
       "Catalog size: #{length(analysis.skills)}",
       "Provider source: #{provider_status["selected_source"]}",
       "Provider: #{provider_status["selected_provider"]}",
       "Auth mode: #{provider_status["selected_auth_mode"]}",
       "Auth owner: #{provider_status["selected_auth_owner"]}",
       "Bootstrap mode: #{provider_status["bootstrap"]["mode"]}",
       "Attachable clients: #{attach_clients}",
       "Headless runtimes: #{if(runtimes == "", do: "none", else: runtimes)}",
       "Framework adapters: #{if(frameworks == "", do: "none", else: frameworks)}"
     ] ++
       Enum.map(analysis.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :watch, options: options}, project_root) do
    interval = Keyword.get(options, :interval, 2_000)

    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        IO.puts("")
        IO.puts("ControlKeel Watch — session ##{session.id}: #{session.title}")
        IO.puts("  Polling every #{interval}ms  ·  Ctrl+C to exit")
        IO.puts(String.duplicate("─", 60))
        watch_loop(session.id, MapSet.new(), interval)

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :mcp, options: options}, project_root) do
    root = Path.expand(options[:project_root] || project_root)

    with {:ok, _binding, _session, _mode} <- ensure_local_project(root) do
      File.cd!(root, fn ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            ControlKeel.MCP.Supervisor,
            {ControlKeel.MCP.Server, input: :stdio, output: :stdio}
          )

        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, _pid, :normal} ->
            :ok

          {:DOWN, ^ref, :process, _pid, :shutdown} ->
            :ok

          {:DOWN, ^ref, :process, _pid, reason} ->
            {:error, "MCP server stopped: #{inspect(reason)}"}
        end
      end)
    else
      {:error, reason} ->
        {:error, "Failed to bootstrap local project for MCP: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :deploy_analyze, options: options}, project_root) do
    root = options[:project_root] || project_root

    case Advisor.analyze(root) do
      {:ok, result} ->
        platform_lines =
          Enum.map_join(result.platforms, "\n", fn p ->
            "  - " <> p.name <> " (" <> p.url <> ")"
          end)

        generator_lines =
          Enum.map_join(result.generators, "\n", fn g ->
            "  - " <> g.name <> " (" <> g.filename <> ")"
          end)

        lines =
          ["Stack: " <> to_string(result.stack), ""] ++
            ["Compatible platforms:", platform_lines, ""] ++
            [
              "Monthly cost estimate: $" <>
                to_string(result.monthly_cost_range.low) <>
                " - $" <> to_string(result.monthly_cost_range.high),
              ""
            ] ++
            ["Generated files:", generator_lines]

        {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_cost, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "static", deployment_stacks(), "stack"),
         {:ok, tier} <- parse_atom_option(options[:tier] || "free", hosting_tiers(), "tier"),
         {:ok, db_tier} <-
           parse_atom_option(options[:db_tier] || "managed_small", database_tiers(), "db_tier") do
      needs_db = options[:needs_db] || false
      bandwidth = options[:bandwidth] || 10
      storage = options[:storage] || 1

      case HostingCost.estimate(
             stack: stack,
             tier: tier,
             needs_db: needs_db,
             db_tier: db_tier,
             expected_bandwidth_gb: bandwidth,
             expected_storage_gb: storage
           ) do
        {:ok, estimates} ->
          lines =
            Enum.map(estimates, fn e ->
              fit = if e.fits_stack, do: "check", else: " "

              "$" <>
                to_string(Float.round(e.total_monthly_usd, 2)) <>
                " [#{fit}] " <> e.name <> " - " <> e.notes
            end)

          {:ok, ["Hosting cost estimates (stack: #{stack}):", "" | lines]}
      end
    end
  end

  def run_command(%{command: :deploy_dns, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.dns_ssl_guide(stack)

      lines =
        ["DNS Setup for #{stack}:", ""] ++
          Enum.map(guide.dns_setup, &("  " <> &1)) ++
          ["", "SSL Setup:", ""] ++
          Enum.map(guide.ssl_setup, &("  " <> &1))

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_migration, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.db_migration_guide(stack)

      lines =
        ["Database Migration Guide for #{stack}:", ""] ++
          Enum.map(guide.steps, &("  " <> &1)) ++
          ["", "Rollback: #{guide.rollback}", "Backup: #{guide.backup_before}"]

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_scaling, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.scaling_guide(stack)

      lines = ["Scaling Guide for #{stack}:", ""]

      lines =
        lines ++
          ["Vertical Scaling:", "  #{guide.vertical_scaling.description}"] ++
          Enum.map(guide.vertical_scaling.tiers, fn t ->
            "  #{t.users} users: #{t.tier} - #{t.cost}"
          end) ++
          [
            "",
            "Horizontal: #{guide.horizontal_scaling}",
            "",
            "Database: #{guide.database_scaling}"
          ]

      {:ok, lines}
    end
  end

  def run_command(%{command: :cost_optimize, options: options}, _project_root) do
    session_id = options[:session_id]
    provider = options[:provider]
    model = options[:model]

    spending =
      if session_id do
        import Ecto.Query

        from(i in ControlKeel.Mission.Invocation,
          where: i.session_id == ^session_id,
          select: %{
            estimated_cost_cents: i.estimated_cost_cents,
            tool: i.tool,
            metadata: i.metadata
          }
        )
        |> ControlKeel.Repo.all()
      else
        []
      end

    case CostOptimizer.suggest(session_id || "cli",
           spending: spending,
           top_provider: provider,
           top_model: model
         ) do
      {:ok, []} ->
        {:ok, ["No cost optimization suggestions at this time."]}

      {:ok, suggestions} ->
        lines =
          Enum.map(suggestions, fn s ->
            "[#{s.priority}] #{s.title}\n  #{s.description}\n  Potential savings: #{s.savings_percent}%"
          end)

        {:ok, ["Cost Optimization Suggestions:", "" | lines]}
    end
  end

  def run_command(%{command: :cost_compare, options: options}, _project_root) do
    tokens = options[:tokens] || 10_000

    case CostOptimizer.compare_agents("CLI comparison", estimated_tokens: tokens) do
      {:ok, result} ->
        lines =
          Enum.map(result.comparisons, fn c ->
            "$#{Float.round(c.estimated_cost_usd, 4)}  #{c.agent} (#{c.provider}/#{c.model})"
          end)

        savings =
          if result.savings_range > 0 do
            ["", "Potential savings: $#{Float.round(result.savings_range / 100, 2)}"]
          else
            []
          end

        {:ok, ["Agent cost comparison (#{tokens} tokens):", "" | lines] ++ savings}
    end
  end

  def run_command(%{command: :precommit_check, options: options}, project_root) do
    root = options[:project_root] || project_root
    domain_pack = options[:domain_pack]
    enforce = options[:enforce] || false

    case PreCommitHook.check(root, domain_pack: domain_pack, enforce: enforce) do
      {:ok, result} ->
        staged_count = length(Map.get(result, :staged_files, []))

        case result.decision do
          "allow" ->
            {:ok, ["No policy violations found in #{staged_count} staged file(s)."]}

          "warn" ->
            lines =
              ["#{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:ok, lines}

          "block" ->
            lines =
              ["BLOCKED: #{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:error, Enum.join(lines, "\n")}
        end
    end
  end

  def run_command(%{command: :precommit_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    enforce = options[:enforce] || false

    case PreCommitHook.install(root, enforce: enforce) do
      {:ok, :installed} ->
        {:ok, ["Pre-commit hook installed in .git/hooks/pre-commit"]}

      {:ok, :updated} ->
        {:ok, ["Pre-commit hook updated in .git/hooks/pre-commit"]}

      {:error, :hook_exists} ->
        {:error, "A non-ControlKeel pre-commit hook already exists. Remove it first."}
    end
  end

  def run_command(%{command: :precommit_uninstall, options: options}, project_root) do
    root = options[:project_root] || project_root

    case PreCommitHook.uninstall(root) do
      {:ok, :uninstalled} ->
        {:ok, ["Pre-commit hook removed."]}

      {:ok, :not_controlkeel_hook} ->
        {:error, "Existing hook is not a ControlKeel hook."}

      {:ok, :no_hook_found} ->
        {:ok, ["No pre-commit hook found."]}
    end
  end

  def run_command(%{command: :progress, options: options}, project_root) do
    session_id = options[:session_id]

    session_id =
      if session_id do
        session_id
      else
        case LocalProject.load(project_root) do
          {:ok, _binding, session} -> session.id
          _ -> nil
        end
      end

    if is_nil(session_id) do
      {:error, "No active session. Use --session-id or run from a bound project."}
    else
      case ControlKeel.Mission.Progress.compute(session_id) do
        {:ok, progress} ->
          current_task = progress.tasks.current_task

          lines = [
            "Session ##{session_id} Progress: #{progress.overall_percent}%",
            "",
            "Tasks: #{progress.tasks.done}/#{progress.tasks.total} done (#{progress.tasks.in_progress} in progress, #{progress.tasks.blocked} blocked)",
            "Findings: #{progress.findings.resolved}/#{progress.findings.total} resolved (#{progress.findings.critical_open} critical open)",
            "Budget: $#{progress.budget.spent_cents / 100} / $#{progress.budget.budget_cents / 100} (#{progress.budget.percent}%) [#{progress.budget.status}]",
            "Estimated effort: #{progress.estimated_effort.estimated_hours}h (#{progress.estimated_effort.estimated_days} days)",
            "Current task: #{(current_task && current_task.title) || "No task in progress"}"
          ]

          remaining =
            Enum.map(progress.remaining_items, fn item ->
              prefix =
                case item.type do
                  :blocker -> "BLOCKER"
                  :warning -> "WARN"
                  _ -> "INFO"
                end

              "  #{prefix}: #{item.message}"
            end)

          lines =
            if remaining != [] do
              lines ++ ["", "Remaining:"] ++ remaining
            else
              lines
            end

          {:ok, lines ++ progress_help_lines(progress, current_task)}

        {:error, :session_not_found} ->
          {:error, "Session ##{session_id} not found."}
      end
    end
  end

  def run_command(%{command: :findings_translate, options: options}, project_root) do
    session_id = options[:session_id]

    findings =
      if session_id do
        ControlKeel.Mission.list_session_findings(session_id)
      else
        case LocalProject.load(project_root) do
          {:ok, _binding, session} ->
            ControlKeel.Mission.list_session_findings(session.id)

          _ ->
            []
        end
      end

    if findings == [] do
      {:ok, ["No findings to translate."]}
    else
      translated = PlainEnglish.translate_list(findings)

      lines =
        Enum.flat_map(translated, fn t ->
          [""] ++
            ["#{t.rule_id} [#{t.severity}]: #{t.title}"] ++
            ["  #{t.category_explanation}"] ++
            if(t.fix, do: ["  Fix: #{t.fix}"], else: []) ++
            if(t.risk_if_ignored, do: ["  Risk: #{t.risk_if_ignored}"], else: [])
        end)

      {:ok, ["Findings in plain English:", "" | tl(lines)]}
    end
  end

  def run_command(%{command: :circuit_breaker_status, options: options}, _project_root) do
    agent_id = options[:agent_id]

    if agent_id do
      case CircuitBreaker.check_status(agent_id) do
        {:ok, status} ->
          lines = [
            "Agent: #{status.agent_id}",
            "Status: #{status.status}",
            "Events: #{status.event_count} (API: #{status.api_calls}, Files: #{status.file_modifications}, Errors: #{status.errors})"
          ]

          lines =
            if status.trip_reason do
              lines ++ ["Trip reason: #{status.trip_reason}"]
            else
              lines
            end

          {:ok, lines}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    else
      case CircuitBreaker.get_all_statuses() do
        {:ok, statuses} ->
          if statuses == [] do
            {:ok, ["No agents tracked by circuit breaker."]}
          else
            lines =
              Enum.map(statuses, fn s ->
                "#{s.agent_id}: #{s.status} (#{s.event_count} events)"
              end)

            {:ok, ["Circuit Breaker Status:", "" | lines]}
          end
      end
    end
  end

  def run_command(%{command: :circuit_breaker_trip, options: options}, _project_root) do
    agent_id = options[:agent_id]

    case CircuitBreaker.trip_breaker(agent_id, "manual CLI trip") do
      {:ok, _} ->
        {:ok, ["Circuit breaker tripped for agent: #{agent_id}"]}
    end
  end

  def run_command(%{command: :circuit_breaker_reset, options: options}, _project_root) do
    agent_id = options[:agent_id]

    case CircuitBreaker.reset_breaker(agent_id) do
      {:ok, _} ->
        {:ok, ["Circuit breaker reset for agent: #{agent_id}"]}
    end
  end

  def run_command(%{command: :agents_monitor, options: options}, _project_root) do
    agent_id = options[:agent_id]

    if agent_id do
      {:ok, events} = AgentMonitor.get_events(agent_id, limit: 20)

      if events == [] do
        {:ok, ["No events for agent: #{agent_id}"]}
      else
        lines =
          Enum.map(events, fn e ->
            ts = e.timestamp |> DateTime.to_iso8601()
            ts <> " " <> to_string(e.event_type) <> " " <> inspect(e.metadata)
          end)

        {:ok, ["Recent events for #{agent_id}:", "" | lines]}
      end
    else
      {:ok, agents} = AgentMonitor.get_active_agents()

      if agents == [] do
        {:ok, ["No active agents."]}
      else
        lines =
          Enum.map(agents, fn a ->
            "#{a.agent_id}: #{to_string(a.status)} (#{a.recent_events_5min} events in 5min, #{a.total_events} total)"
          end)

        {:ok, ["Active agents:", "" | lines]}
      end
    end
  end

  def run_command(%{command: :outcome_record, args: [session_id, outcome]}, _project_root) do
    with {sid, ""} <- Integer.parse(session_id),
         {:ok, outcome_atom} <-
           parse_atom_option(outcome, OutcomeTracker.valid_outcomes(), "outcome") do
      agent_id = "cli-session-#{sid}"

      case OutcomeTracker.record(sid, outcome_atom, agent_id: agent_id) do
        {:ok, result} ->
          {:ok, ["Recorded #{outcome} for session ##{session_id} (reward: #{result.reward})"]}

        {:error, {:unknown_outcome, o}} ->
          {:error,
           "Unknown outcome: #{o}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}

        {:error, reason} ->
          {:error, "Failed: " <> inspect(reason)}
      end
    else
      :error ->
        {:error, "`session_id` must be an integer"}

      {:error, _reason} ->
        {:error,
         "Unknown outcome: #{outcome}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}
    end
  end

  def run_command(%{command: :outcome_score, args: [agent_id]}, _project_root) do
    case OutcomeTracker.get_agent_score(agent_id) do
      {:ok, score} ->
        {:ok,
         [
           "Agent: #{score.agent_id}",
           "Score: #{score.score} (#{score.outcome_count} outcomes, total reward: #{score.total_reward})",
           "Window: #{score.window_days} days"
         ]}
    end
  end

  def run_command(%{command: :outcome_leaderboard}, _project_root) do
    case OutcomeTracker.get_leaderboard() do
      {:ok, []} ->
        {:ok, ["No outcomes recorded yet."]}

      {:ok, scores} ->
        lines =
          Enum.map(scores, fn s ->
            id = s.agent_id || "unknown"
            id <> ": " <> to_string(s.score) <> " (" <> to_string(s.outcome_count) <> " outcomes)"
          end)

        {:ok, ["Agent Leaderboard:", "" | lines]}
    end
  end

  defp deployment_stacks, do: [:phoenix, :react, :rails, :node, :python, :static]
  defp hosting_tiers, do: HostingCost.available_tiers() |> Map.keys()
  defp database_tiers, do: HostingCost.available_database_tiers() |> Map.keys()

  defp parse_atom_option(value, allowed, _field) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid}
  end

  defp parse_atom_option(value, allowed, field) when is_binary(value) do
    trimmed = String.trim(value)

    case Enum.find(allowed, &(to_string(&1) == trimmed)) do
      nil ->
        {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

      atom ->
        {:ok, atom}
    end
  end

  defp parse_atom_option(_value, allowed, field),
    do: {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

  defp watch_loop(session_id, seen, interval) do
    findings = Mission.list_session_findings(session_id)
    session = Mission.get_session(session_id)

    new_findings = Enum.reject(findings, fn f -> MapSet.member?(seen, f.id) end)
    updated_seen = Enum.reduce(new_findings, seen, fn f, acc -> MapSet.put(acc, f.id) end)

    Enum.each(new_findings, fn f ->
      severity_badge =
        case f.severity do
          "critical" -> "[CRITICAL]"
          "high" -> "[HIGH]    "
          "medium" -> "[MEDIUM]  "
          _ -> "[LOW]     "
        end

      status =
        case f.status do
          "blocked" -> "BLOCKED"
          "approved" -> "approved"
          "rejected" -> "rejected"
          "escalated" -> "ESCALATED"
          _ -> "open"
        end

      IO.puts("")
      IO.puts("  #{severity_badge} #{f.rule_id}  (#{status})")
      IO.puts("  #{f.plain_message || f.title}")
    end)

    if session do
      spent = session.spent_cents || 0
      budget = session.budget_cents || 0
      rolling = Budget.rolling_24h_spend_cents(session.id)
      pct = if budget > 0, do: round(spent / budget * 100), else: 0
      filled = round(pct / 5)
      bar = "[" <> String.duplicate("█", filled) <> String.duplicate("░", 20 - filled) <> "]"
      IO.puts("")

      IO.puts(
        "  Budget  #{bar}  #{format_money(spent)}/#{format_money(budget)} (#{pct}%)  · rolling 24h: #{format_money(rolling)}"
      )

      IO.puts(String.duplicate("─", 60))
    end

    Process.sleep(interval)
    watch_loop(session_id, updated_seen, interval)
  end

  defp parse_with_switches(command, argv, switches) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: command, options: options, args: []}}
    end
  end

  defp parse_attach(agent, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @attach_switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: :attach, options: options, args: [agent]}}
    end
  end

  defp parse_memory_search(query, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @memory_search_switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: :memory_search, options: options, args: [query]}}
    end
  end

  defp parse_audit_log(session_id, argv) do
    case OptionParser.parse(argv, strict: @audit_log_switches) do
      {options, [], []} ->
        {:ok, %{command: :audit_log, options: options, args: [session_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_benchmark_export(run_id, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @benchmark_export_switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: :benchmark_export, options: options, args: [run_id]}}
    end
  end

  defp parse_policy_set_apply(workspace_id, policy_set_id, argv) do
    case OptionParser.parse(argv, strict: @policy_set_apply_switches) do
      {options, [], []} ->
        {:ok,
         %{command: :policy_set_apply, options: options, args: [workspace_id, policy_set_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_default(source, argv) do
    case OptionParser.parse(argv, strict: @provider_default_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_default, options: options, args: [source]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_key(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_key_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_key, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_base_url(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_base_url_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_base_url, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_model(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_model_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_model, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_runtime_export(runtime_id, argv) do
    case OptionParser.parse(argv, strict: @runtime_export_switches) do
      {options, [], []} ->
        {:ok, %{command: :runtime_export, options: options, args: [runtime_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_review_plan_respond(review_id, argv) do
    case OptionParser.parse(argv, strict: @review_plan_respond_switches) do
      {options, [], []} ->
        {:ok, %{command: :review_plan_respond, options: options, args: [review_id]}}

      _ ->
        {:error, usage_text()}
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
          {:error, usage_text()}
      end
    else
      {:error, usage_text()}
    end
  end

  defp parse_run_command(command, id, argv) do
    case OptionParser.parse(argv, strict: @agent_run_switches) do
      {options, [], []} ->
        {:ok, %{command: command, options: options, args: [id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp required_option(options, key, flag) do
    value =
      cond do
        is_list(options) -> Keyword.get(options, key)
        is_map(options) -> Map.get(options, key)
        true -> nil
      end

    case value do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{flag} is required."}
    end
  end

  defp governance_opts(options, project_root) do
    [
      session_id: options[:session_id] || binding_session_id(project_root),
      domain_pack: options[:domain_pack],
      project_root: project_root,
      github: github_metadata_from_env()
    ]
  end

  defp release_ready_session_id(options, project_root) do
    case options[:session_id] || binding_session_id(project_root) do
      nil ->
        {:error,
         "Release readiness requires --session-id or an existing project binding in the current repo."}

      session_id ->
        {:ok, session_id}
    end
  end

  defp release_ready_opts(options, project_root) do
    %{
      sha: options[:sha],
      project_root: project_root,
      smoke: %{
        "status" => options[:smoke_status],
        "artifact_source" => options[:artifact_source]
      },
      provenance: %{
        "verified" => Keyword.get(options, :provenance_verified, false),
        "artifact_source" => options[:artifact_source]
      },
      github: github_metadata_from_env()
    }
  end

  defp patch_input(options) do
    cond do
      is_binary(options[:patch]) and options[:patch] != "" ->
        case File.read(options[:patch]) do
          {:ok, patch} -> {:ok, patch}
          {:error, reason} -> {:error, "Failed to read patch file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        {:ok, IO.read(:stdio, :eof)}

      true ->
        {:error, "Provide --patch <file> or --stdin."}
    end
  end

  defp review_submission_input(options) do
    cond do
      is_binary(options[:body_file]) and options[:body_file] != "" ->
        case File.read(options[:body_file]) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, "Failed to read plan file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        {:ok, IO.read(:stdio, :eof)}

      true ->
        {:error, "Provide --body-file <file> or --stdin."}
    end
  end

  defp review_submission_attrs(options, submission_body) do
    runtime_context = review_runtime_context_from_env()

    {:ok,
     %{
       "session_id" => options[:session_id],
       "task_id" => options[:task_id],
       "title" => options[:title],
       "review_type" => "plan",
       "submission_body" => submission_body,
       "submitted_by" => options[:submitted_by] || runtime_context["agent_id"] || "cli",
       "metadata" => %{
         "runtime_context" => runtime_context,
         "body_file" => options[:body_file]
       }
     }}
  end

  defp review_response_attrs(options, decision) do
    %{
      "decision" => decision,
      "feedback_notes" => options[:feedback_notes],
      "reviewed_by" => options[:reviewed_by] || "cli",
      "annotations" => parse_review_annotations(options[:annotations])
    }
  end

  defp parse_review_annotations(nil), do: %{}

  defp parse_review_annotations(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = annotations} -> annotations
      _ -> %{"cli_notes" => value}
    end
  end

  defp required_integer_option(options, key, flag) do
    value =
      cond do
        is_list(options) -> Keyword.get(options, key)
        is_map(options) -> Map.get(options, key)
        true -> nil
      end

    case value do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, "#{flag} is required."}
    end
  end

  defp socket_report_input(options) do
    cond do
      is_binary(options[:report]) and options[:report] != "" ->
        case File.read(options[:report]) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, %{} = payload} ->
                {:ok, payload}

              {:ok, _other} ->
                {:error, "Socket report must decode to a JSON object."}

              {:error, %Jason.DecodeError{} = error} ->
                {:error, "Socket report must be valid JSON: #{Exception.message(error)}"}
            end

          {:error, reason} ->
            {:error, "Failed to read Socket report file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        case Jason.decode(IO.read(:stdio, :eof)) do
          {:ok, %{} = payload} ->
            {:ok, payload}

          {:ok, _other} ->
            {:error, "Socket report must decode to a JSON object."}

          {:error, %Jason.DecodeError{} = error} ->
            {:error, "Socket report must be valid JSON: #{Exception.message(error)}"}
        end

      true ->
        {:error, "Provide --report <file> or --stdin."}
    end
  end

  defp plugin_target("codex"), do: {:ok, "codex-plugin"}
  defp plugin_target("claude"), do: {:ok, "claude-plugin"}
  defp plugin_target("copilot"), do: {:ok, "copilot-plugin"}
  defp plugin_target("openclaw"), do: {:ok, "openclaw-plugin"}
  defp plugin_target("augment"), do: {:ok, "augment-plugin"}
  defp plugin_target("droid"), do: {:ok, "droid-plugin"}
  defp plugin_target(_plugin), do: {:error, :unknown_plugin}

  defp plugin_mcp_hint("hosted"), do: ".mcp.hosted.json"
  defp plugin_mcp_hint(_mode), do: ".mcp.json"

  defp agent_run_opts(options, project_root) do
    []
    |> maybe_put_cli_opt(:project_root, project_root)
    |> maybe_put_cli_opt(:agent, options[:agent])
    |> maybe_put_cli_opt(:mode, options[:mode])
    |> maybe_put_cli_opt(:sandbox, options[:sandbox])
  end

  defp maybe_put_cli_opt(opts, _key, nil), do: opts
  defp maybe_put_cli_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp read_json_config(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{} = config} -> config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp maybe_cli_line(_label, nil), do: []
  defp maybe_cli_line(label, value), do: ["#{label}: #{value}"]

  defp attached_agent_status_lines(binding) do
    attached_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Enum.sort_by(fn {agent, _attrs} -> agent end)

    case attached_agents do
      [] ->
        []

      rows ->
        [
          "Attached agents:"
          | Enum.map(rows, fn {agent, attrs} ->
              version = attrs["controlkeel_version"] || "unknown"
              "  #{agent} (CK v#{version})"
            end)
        ]
    end
  end

  defp contextual_status_help_lines(_session, task, active_findings, improvement) do
    recommended_next_step =
      if is_map(improvement), do: improvement["recommended_next_step"], else: nil

    help_lines =
      []
      |> maybe_add_help_line(
        active_findings > 0,
        "Next: controlkeel findings --status open"
      )
      |> maybe_add_help_line(maybe_task_proof_hint(task))
      |> maybe_add_help_line(
        true,
        "Loop focus: #{recommended_next_step || "observe and rerun the governed loop"}"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp findings_help_lines(findings, options) do
    help_lines =
      []
      |> maybe_add_help_line(
        findings != [],
        "Next: controlkeel approve <finding_id>"
      )
      |> maybe_add_help_line(
        findings != [] and is_nil(options[:status]),
        "Next: controlkeel findings --status blocked"
      )
      |> maybe_add_help_line(
        findings == [],
        "Next: controlkeel status"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp findings_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("severity", options[:severity])
      |> maybe_add_filter("status", options[:status])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  defp proofs_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("task_id", options[:task_id])
      |> maybe_add_filter("deploy_ready", options[:deploy_ready])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  defp benchmark_filter_summary(options) do
    case options[:domain_pack] do
      nil -> ""
      "" -> ""
      domain_pack -> " (domain_pack=#{domain_pack})"
    end
  end

  defp maybe_add_filter(filters, _label, nil), do: filters
  defp maybe_add_filter(filters, _label, ""), do: filters
  defp maybe_add_filter(filters, label, value), do: filters ++ ["#{label}=#{value}"]

  defp current_session_task(session) do
    Enum.find(session.tasks, &(&1.status == "in_progress")) ||
      Enum.find(session.tasks, &(&1.status == "queued")) ||
      List.first(session.tasks)
  end

  defp proofs_help_lines(proofs, options) do
    help_lines =
      []
      |> maybe_add_help_line(
        proofs != [],
        "Next: controlkeel proof <proof_id>"
      )
      |> maybe_add_help_line(
        proofs != [] and is_nil(options[:deploy_ready]),
        "Next: controlkeel proofs --deploy-ready true"
      )
      |> maybe_add_help_line(
        proofs == [],
        "Next: controlkeel status"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp progress_help_lines(progress, current_task) do
    help_lines =
      []
      |> maybe_add_help_line(
        progress.findings.critical_open > 0 or progress.findings.blocked > 0,
        "Next: controlkeel findings --status blocked"
      )
      |> maybe_add_help_line(maybe_task_proof_hint(current_task))
      |> maybe_add_help_line(
        progress.tasks.queued > 0,
        "Next: controlkeel run task <task_id>"
      )

    case help_lines do
      [] -> []
      lines -> ["", "Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp benchmark_list_help_lines(suites, runs, subjects) do
    help_lines =
      []
      |> maybe_add_help_line(
        suites != [],
        "Next: controlkeel benchmark run --suite <suite_slug> --subjects <subject_ids>"
      )
      |> maybe_add_help_line(
        runs != [],
        "Next: controlkeel benchmark show <run_id>"
      )
      |> maybe_add_help_line(
        subjects == [],
        "Next: controlkeel benchmark import <run_id> <subject> <file>"
      )

    case help_lines do
      [] -> []
      lines -> ["", "Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp benchmark_show_help_lines(run) do
    help_lines =
      []
      |> maybe_add_help_line(
        true,
        "Next: controlkeel benchmark export #{run.id} --format csv"
      )
      |> maybe_add_help_line(
        run.status != "completed",
        "Next: controlkeel benchmark import #{run.id} <subject> <file>"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp session_workspace_context(session, project_root) do
    session
    |> WorkspaceContext.resolve_project_root(project_root)
    |> case do
      nil -> ProjectRoot.resolve(project_root)
      resolved -> resolved
    end
    |> WorkspaceContext.build()
  end

  defp augmentation_status_line(%{"available" => true} = augmentation) do
    likely_paths = augmentation["likely_paths"] |> List.wrap() |> Enum.take(3)
    search_terms = augmentation["search_terms"] |> List.wrap() |> Enum.take(3)

    summary =
      [
        truncate_cli(augmentation["objective"], 90),
        list_hint("paths", likely_paths),
        list_hint("terms", search_terms)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    if summary == "", do: "available", else: summary
  end

  defp augmentation_status_line(_augmentation), do: "not available yet"

  defp security_case_status_line(%{"case_count" => 0}), do: "0 tracked"

  defp security_case_status_line(%{"case_count" => case_count} = summary) do
    unresolved = summary["unresolved"] || 0
    critical = summary["critical_unresolved"] || 0

    "#{case_count} tracked · #{unresolved} unresolved · #{critical} critical unresolved"
  end

  defp security_case_status_line(_summary), do: "not recorded"

  defp list_hint(_label, []), do: nil
  defp list_hint(label, values), do: "#{label}: #{Enum.join(values, ", ")}"

  defp truncate_cli(nil, _limit), do: nil

  defp truncate_cli(text, limit) when is_binary(text) and byte_size(text) > limit do
    "#{binary_part(text, 0, limit)}... (#{byte_size(text)} chars)"
  end

  defp truncate_cli(text, _limit), do: text

  defp maybe_add_help_line(lines, true, line), do: lines ++ [line]
  defp maybe_add_help_line(lines, false, _line), do: lines
  defp maybe_add_help_line(lines, nil), do: lines
  defp maybe_add_help_line(lines, line) when is_binary(line), do: lines ++ [line]

  defp maybe_task_proof_hint(%{id: id}), do: "Next: controlkeel proofs --task-id #{id}"
  defp maybe_task_proof_hint(_task), do: nil

  defp agent_execution_lines(result) do
    [
      "Delegated task ##{result["task_id"]}.",
      "Agent: #{result["agent_id"]}",
      "Mode: #{result["mode"]}",
      "Status: #{result["status"]}",
      "Run package: #{result["package_root"]}"
    ] ++
      maybe_cli_line("OAuth client id", result["oauth_client_id"]) ++
      maybe_cli_line("Client secret", result["client_secret"]) ++
      maybe_cli_line("Bundle path", result["bundle_path"])
  end

  defp format_cli_error({:invalid_arguments, reason}), do: reason
  defp format_cli_error({:policy_blocked, reason}), do: reason
  defp format_cli_error(:not_found), do: "not found"
  defp format_cli_error(:invalid_id), do: "invalid id"

  defp format_cli_error({:review_denied, review}),
    do: "Plan review was denied." <> format_review_feedback_error(review)

  defp format_cli_error({:review_pending, details}),
    do:
      "Task is waiting on plan approval (review ##{details[:review_id] || "unknown"}, status #{details[:review_status] || "pending"})."

  defp format_cli_error({:timeout, review}),
    do: "Timed out waiting for plan review ##{review.id}." <> format_review_feedback_error(review)

  defp format_cli_error(reason), do: inspect(reason)

  defp review_url(review_id), do: Endpoint.url() <> "/reviews/#{review_id}"

  defp review_feedback_lines(%{feedback_notes: notes}) when is_binary(notes) and notes != "",
    do: ["Feedback: #{notes}"]

  defp review_feedback_lines(_review), do: []

  defp format_review_feedback_error(%{feedback_notes: notes})
       when is_binary(notes) and notes != "" do
    " Feedback: #{notes}"
  end

  defp format_review_feedback_error(_review), do: ""

  defp review_runtime_context_from_env do
    %{
      "session_id" => System.get_env("CONTROLKEEL_SESSION_ID"),
      "task_id" => System.get_env("CONTROLKEEL_TASK_ID"),
      "agent_id" => System.get_env("CONTROLKEEL_AGENT_ID"),
      "thread_id" => System.get_env("CONTROLKEEL_THREAD_ID"),
      "host_session_id" => System.get_env("CONTROLKEEL_HOST_SESSION_ID"),
      "project_root" => System.get_env("CONTROLKEEL_PROJECT_ROOT"),
      "browser_embed" =>
        System.get_env("CONTROLKEEL_REVIEW_EMBED") || System.get_env("CONTROLKEEL_BROWSER_EMBED")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp review_cli_payload(review, extra) do
    %{
      "review" => %{
        "id" => review.id,
        "title" => review.title,
        "status" => review.status,
        "review_type" => review.review_type,
        "session_id" => review.session_id,
        "task_id" => review.task_id,
        "feedback_notes" => review.feedback_notes,
        "submitted_by" => review.submitted_by,
        "reviewed_by" => review.reviewed_by,
        "annotations" => review.annotations
      }
    }
    |> maybe_put_agent_feedback(review)
    |> Map.merge(extra)
  end

  defp maybe_put_agent_feedback(payload, %{status: "denied"} = review) do
    Map.put(payload, "agent_feedback", ReviewBridge.agent_feedback(review))
  end

  defp maybe_put_agent_feedback(payload, _review), do: payload

  defp cli_error(prefix, reason, options, extra_payload \\ %{}) do
    message = "#{prefix}: #{format_cli_error(reason)}"

    if options[:json] do
      {:error, Jason.encode!(Map.merge(%{"error" => message}, extra_payload))}
    else
      {:error, message}
    end
  end

  defp review_lines(review, recommendation_label) do
    decision =
      case review["decision"] do
        "block" -> "blocked"
        "warn" -> "needs review"
        _ -> "allowed"
      end

    base_lines = [
      review["summary"],
      "#{String.capitalize(recommendation_label)} recommendation: #{decision}.",
      "Files reviewed: #{review["files_reviewed"]}",
      "Chunks reviewed: #{review["chunks_reviewed"]}",
      "Added lines reviewed: #{review["added_lines_reviewed"]}",
      "Findings: #{get_in(review, ["finding_totals", "total"]) || 0}"
    ]

    persisted_lines =
      case review["persisted_finding_ids"] || [] do
        [] -> []
        ids -> ["Persisted findings: #{Enum.join(Enum.map(ids, &to_string/1), ", ")}"]
      end

    finding_lines =
      Enum.map(review["findings"] || [], fn finding ->
        location =
          [finding["path"], finding["kind"]]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" / ")

        severity = "#{finding["severity"]}/#{finding["decision"]}"

        case location do
          "" -> "  [#{severity}] #{finding["rule_id"]}: #{finding["plain_message"]}"
          _ -> "  [#{severity}] #{finding["rule_id"]} @ #{location}: #{finding["plain_message"]}"
        end
      end)

    base_lines ++ persisted_lines ++ finding_lines
  end

  defp release_ready_lines(readiness) do
    base_lines = [
      "Release readiness: #{readiness["status"]}",
      readiness["summary"],
      "Session: #{readiness["session_title"]} (##{readiness["session_id"]})"
    ]

    proof_lines =
      case readiness["proof"] do
        nil ->
          ["Proof: none"]

        proof ->
          ["Proof: ##{proof["id"]} v#{proof["version"]} (deploy-ready: #{proof["deploy_ready"]})"]
      end

    findings = readiness["findings"] || %{}

    evidence_lines = [
      "Open findings: #{findings["open"] || 0}",
      "Blocked findings: #{findings["blocked"] || 0}",
      "Escalated findings: #{findings["escalated"] || 0}",
      "High/critical unresolved: #{findings["high_or_critical"] || 0}",
      "Smoke satisfied: #{get_in(readiness, ["smoke", "satisfied"]) || false}",
      "Provenance satisfied: #{get_in(readiness, ["provenance", "satisfied"]) || false}"
    ]

    reason_lines = Enum.map(readiness["reasons"] || [], &"  - #{&1}")

    base_lines ++ proof_lines ++ evidence_lines ++ reason_lines
  end

  defp binding_session_id(project_root) do
    case ProjectBinding.read_effective(project_root) do
      {:ok, binding, _mode} -> binding["session_id"]
      _ -> nil
    end
  end

  defp github_metadata_from_env do
    %{
      "event_name" => System.get_env("GITHUB_EVENT_NAME"),
      "repository" => System.get_env("GITHUB_REPOSITORY"),
      "ref" => System.get_env("GITHUB_REF"),
      "sha" => System.get_env("GITHUB_SHA"),
      "run_id" => System.get_env("GITHUB_RUN_ID"),
      "base_ref" => System.get_env("GITHUB_BASE_REF"),
      "head_ref" => System.get_env("GITHUB_HEAD_REF")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp standalone_wrapper_runtime? do
    System.get_env("__BURRITO") not in [nil, ""]
  end

  defp plain_arguments do
    plain_arguments_provider().()
    |> Enum.map(&to_string/1)
  end

  defp plain_arguments_provider do
    Application.get_env(:controlkeel, :cli_plain_arguments_provider, &:init.get_plain_arguments/0)
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp require_integer_option(nil, option), do: {:error, {:missing_option, option}}
  defp require_integer_option(value, _option) when is_integer(value), do: {:ok, value}

  defp require_integer_option(value, _option) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp require_string_option(nil, option), do: {:error, {:missing_option, option}}
  defp require_string_option("", option), do: {:error, {:missing_option, option}}
  defp require_string_option(value, _option), do: {:ok, to_string(value)}

  defp selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  defp selected_base_url(_status), do: "default"

  defp ensure_attach_project(project_root, overrides) do
    ensure_local_project(project_root, overrides, sync_attached_agents: false)
  end

  defp ensure_local_project(project_root, overrides \\ %{}, opts \\ []) do
    project_root = ProjectRoot.resolve(project_root)
    sync_attached_agents? = Keyword.get(opts, :sync_attached_agents, true)

    with {:ok, binding, session, mode} <-
           LocalProject.load_or_bootstrap(project_root, overrides, ephemeral_ok: true) do
      if sync_attached_agents? do
        case AttachedAgentSync.sync(binding, project_root, mode: mode) do
          {:ok, synced_binding, _changes} -> {:ok, synced_binding, session, mode}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, binding, session, mode}
      end
    end
  end

  defp binding_write_mode(binding) do
    case get_in(binding, ["bootstrap", "mode"]) do
      "ephemeral" -> :ephemeral
      _ -> :project
    end
  end

  defp bootstrap_lines(project_root) do
    snapshot = SetupAdvisor.snapshot(project_root)
    status = ProviderBroker.status(project_root)
    bootstrap = status["bootstrap"]

    [
      "Project root: #{snapshot["project_root"]}.",
      SetupAdvisor.detected_hosts_line(snapshot),
      "Bootstrap mode: #{bootstrap["mode"]}.",
      "Provider source: #{status["selected_source"]}.",
      "Provider: #{status["selected_provider"]}.",
      "Auth mode: #{status["selected_auth_mode"]}.",
      "Auth owner: #{status["selected_auth_owner"]}.",
      "Core loop: #{SetupAdvisor.core_loop()}."
    ]
  end

  defp load_rules_payload(nil), do: {:ok, []}

  defp load_rules_payload(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      case decoded do
        %{"entries" => _entries} = wrapped -> {:ok, wrapped}
        entries when is_list(entries) -> {:ok, entries}
        other -> {:error, {:invalid_rules_payload, other}}
      end
    else
      {:error, :enoent} ->
        {:error, :rules_file_not_found}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp format_ms(nil), do: "Not recorded"
  defp format_ms(value), do: "#{value}ms"

  defp format_active_artifact(nil), do: "heuristic"
  defp format_active_artifact(artifact), do: "v#{artifact.version} (##{artifact.id})"

  defp format_provider_bridge(%{supported: true, provider: provider, mode: mode}),
    do: "#{mode}: #{provider}"

  defp format_provider_bridge(%{supported: true, mode: mode}), do: mode
  defp format_provider_bridge(%{mode: "ck_owned"}), do: "ck-owned"
  defp format_provider_bridge(%{mode: "none"}), do: "none"
  defp format_provider_bridge(_bridge), do: "none"

  defp emit_attach_succeeded(binding, project_root, attached_agent) do
    root = Path.expand(project_root)

    if is_integer(binding["session_id"]) do
      _ = Mission.attach_session_runtime_context(binding["session_id"], %{"project_root" => root})

      _ =
        ControlKeel.SessionTranscript.record(%{
          session_id: binding["session_id"],
          event_type: "session.attach",
          actor: "cli",
          summary: "Attached #{attached_agent["server_name"] || "agent"} to ControlKeel.",
          body: "Project root: #{root}",
          payload: %{
            "project_root" => root,
            "server_name" => attached_agent["server_name"],
            "scope" => attached_agent["scope"]
          }
        })
    end

    :telemetry.execute(
      [:controlkeel, :claude, :attach, :succeeded],
      %{count: 1},
      %{
        session_id: binding["session_id"],
        workspace_id: binding["workspace_id"],
        project_root: root,
        server_name: attached_agent["server_name"],
        scope: attached_agent["scope"]
      }
    )
  end

  defp attach_guidance_lines(agent) do
    case AgentIntegration.get(agent) do
      nil ->
        Distribution.current_install_lines()

      integration ->
        [
          integration.preferred_target && "Companion target: #{integration.preferred_target}.",
          "Support class: #{integration.support_class}.",
          "Supported scope: #{Enum.join(integration.supported_scopes, ", ")}.",
          "Required CK tools: #{Enum.join(integration.required_mcp_tools, ", ")}.",
          "Auto-bootstrap: #{if(integration.auto_bootstrap, do: "enabled", else: "disabled")}.",
          "Auth mode: #{integration.auth_mode}.",
          "Auth owner: #{AgentIntegration.auth_owner(integration)}.",
          "MCP mode: #{integration.mcp_mode}.",
          "Skills mode: #{integration.skills_mode}.",
          "Provider bridge: #{format_provider_bridge(integration.provider_bridge)}.",
          "Core loop: #{SetupAdvisor.core_loop()}.",
          "Next: controlkeel status.",
          integration.upstream_docs_url && "Upstream docs: #{integration.upstream_docs_url}"
        ]
        |> Enum.reject(&is_nil/1)
        |> Kernel.++(Distribution.current_install_lines())
    end
  end

  defp resolve_project_root(options, project_root) do
    options[:project_root] ||
      project_root
      |> ProjectRoot.resolve()
  end

  defp maybe_line(nil, _prefix), do: []
  defp maybe_line(line, prefix), do: ["#{prefix}#{line}"]

  defp native_attach_lines("claude-code", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("claude-standalone", project_root,
             scope: attach_scope("claude-code", options)
           ) do
        {:ok, %{destination: destination, agent_destination: agent_destination}} ->
          [
            "Installed Claude native skills at #{destination}.",
            "Installed Claude companion agent at #{agent_destination}."
          ]

        {:error, reason} ->
          ["Native Claude skills were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines("cline", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("cline-native", project_root, scope: attach_scope("cline", options)) do
        {:ok, %{destination: destination} = result} ->
          [
            "Installed Cline skills at #{destination}."
          ] ++
            maybe_attach_line(
              "Installed Cline MCP companion",
              Map.get(result, :agent_destination)
            ) ++
            maybe_attach_line("Installed Cline rules", Map.get(result, :rules_destination)) ++
            maybe_attach_line(
              "Installed Cline workflows",
              Map.get(result, :workflows_destination)
            )

        {:error, reason} ->
          ["Native Cline files were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines("goose", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("goose-native", project_root, scope: "project") do
        {:ok, %{destination: destination} = result} ->
          [
            "Installed Goose project hints at #{destination}."
          ] ++
            maybe_attach_line(
              "Installed Goose workflow recipes",
              Map.get(result, :workflows_destination)
            ) ++
            maybe_attach_line(
              "Installed Goose companion bundle",
              Map.get(result, :agent_destination)
            )

        {:error, reason} ->
          ["Native Goose files were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines(agent, project_root, options)
       when agent in [
              "cursor",
              "windsurf",
              "kiro",
              "kilo",
              "amp",
              "augment",
              "opencode",
              "gemini-cli",
              "continue",
              "aider"
            ] do
    if native_attach_skipped?(options) do
      []
    else
      target =
        %{
          "cursor" => "cursor-native",
          "windsurf" => "windsurf-native",
          "kiro" => "kiro-native",
          "kilo" => "kilo-native",
          "amp" => "amp-native",
          "augment" => "augment-native",
          "opencode" => "opencode-native",
          "gemini-cli" => "gemini-cli-native",
          "continue" => "continue-native",
          "aider" => "instructions-only"
        }[agent]

      case if(target,
             do: Skills.install(target, project_root, scope: "project"),
             else: Skills.export("instructions-only", project_root, scope: "export")
           ) do
        {:ok, %{destination: destination}} ->
          [
            "Prepared native companion files for #{display_attach_agent(agent)}.",
            "Destination: #{destination}"
          ]

        {:ok, plan} ->
          [
            "Prepared native instruction snippets for #{display_attach_agent(agent)}.",
            "Instructions bundle: #{plan.output_dir}"
          ]

        {:error, reason} ->
          ["Instruction bundle was not prepared: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines(_agent, _project_root, _options), do: []

  defp native_attach_skipped?(options) do
    Keyword.get(options, :mcp_only, false) or Keyword.get(options, :no_native, false)
  end

  defp maybe_install_codex_native(project_root, scope, options) do
    if native_attach_skipped?(options) do
      {:ok, nil}
    else
      Skills.install("codex", project_root, scope: scope)
    end
  end

  defp codex_attach_install_lines(nil), do: []

  defp codex_attach_install_lines(install_result) do
    lines = [
      "Installed Codex skills at #{install_result[:destination]}.",
      "Installed Codex companion agent at #{install_result[:agent_destination]}.",
      "Installed Codex review commands at #{install_result[:commands_destination]}."
    ]

    compat_destination = install_result[:compat_destination]

    cond do
      is_nil(compat_destination) ->
        lines

      compat_destination == install_result[:destination] ->
        lines

      true ->
        lines ++ ["Installed open-standard compatibility skills at #{compat_destination}."]
    end
  end

  defp attach_scope("claude-code", options), do: options[:scope] || "user"
  defp attach_scope("codex-cli", options), do: options[:scope] || "user"
  defp attach_scope("hermes-agent", options), do: options[:scope] || "user"
  defp attach_scope("forge", options), do: options[:scope] || "user"
  defp attach_scope(_agent, options), do: options[:scope] || "project"

  defp display_attach_agent(agent), do: AgentIntegration.label(agent)

  # ─── IDE MCP attachment helpers ──────────────────────────────────────────────

  defp attach_to_cursor(command_spec) do
    config_path = cursor_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "cursor")
  end

  defp attach_to_windsurf(command_spec) do
    config_path = windsurf_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "windsurf")
  end

  defp cursor_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([
          System.get_env("APPDATA") || home,
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      {:unix, :darwin} ->
        Path.join([
          home,
          "Library",
          "Application Support",
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      _ ->
        Path.join([home, ".config", "Cursor", "User", "globalStorage", "cursor.mcp.json"])
    end
  end

  defp windsurf_mcp_config_path do
    home = user_home()
    Path.join([home, ".codeium", "windsurf", "mcp_config.json"])
  end

  defp write_ide_mcp_config(config_path, server_name, command_spec, ide_key) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing =
      case File.read(config_path) do
        {:ok, contents} ->
          case Jason.decode(contents) do
            {:ok, %{} = decoded} -> decoded
            _ -> %{}
          end

        _ ->
          %{}
      end || %{}

    updated =
      if ide_key in ["opencode", "kilo"] do
        mcp = Map.get(existing, "mcp", %{})

        entry = %{
          "type" => "local",
          "command" => [command | args]
        }

        entry =
          if ide_key == "kilo" do
            Map.put(entry, "enabled", true)
          else
            entry
          end

        Map.put(
          existing,
          "mcp",
          Map.put(mcp, server_name, entry)
        )
      else
        mcpServers = Map.get(existing, "mcpServers", %{})

        Map.put(
          existing,
          "mcpServers",
          Map.put(mcpServers, server_name, %{
            "command" => command,
            "args" => args
          })
        )
      end

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => ide_key,
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  # ── Additional IDE MCP config paths ──────────────────────────────────────────

  defp kiro_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, ".kiro", "settings", "mcp.json"])

      _ ->
        Path.join([home, ".kiro", "settings", "mcp.json"])
    end
  end

  defp kilo_config_path do
    Path.join([user_home(), ".config", "kilo", "kilo.json"])
  end

  defp amp_mcp_config_path do
    Path.join([user_home(), ".config", "amp", "mcp.json"])
  end

  defp augment_mcp_config_path do
    Path.join([user_home(), ".augment", "settings.json"])
  end

  defp opencode_mcp_config_path do
    Path.join([user_home(), ".config", "opencode", "config.json"])
  end

  defp gemini_cli_config_path do
    Path.join([user_home(), ".gemini", "settings.json"])
  end

  defp cline_mcp_config_path do
    base = System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
    Path.join([base, "data", "settings", "cline_mcp_settings.json"])
  end

  defp continue_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, "Roaming", "Continue", "config.json"])

      _ ->
        Path.join([home, ".continue", "config.json"])
    end
  end

  # Continue uses an array-based mcpServers format, unlike Cursor/Windsurf dict format
  defp write_continue_mcp_config(config_path, server_name, command_spec) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing =
      case File.read(config_path) do
        {:ok, c} -> Jason.decode(c) |> elem(1)
        _ -> %{}
      end || %{}

    servers = Map.get(existing, "mcpServers", [])
    filtered = Enum.reject(servers, &(Map.get(&1, "name") == server_name))
    new_entry = %{"name" => server_name, "command" => command, "args" => args}
    updated = Map.put(existing, "mcpServers", filtered ++ [new_entry])

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => "continue",
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  # Aider uses a YAML config file (.aider.conf.yml) at the project root
  defp attach_to_aider(command_spec, project_root) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []
    config_path = Path.join(project_root, ".aider.conf.yml")

    existing =
      case File.read(config_path) do
        {:ok, c} -> c
        _ -> ""
      end

    # Remove any prior controlkeel block, then append the new one
    cleaned =
      Regex.replace(
        ~r/\nmcpservers:(\n  controlkeel:[^\n]*(\n    [^\n]+)*)+/,
        existing,
        ""
      )

    args_line =
      case args do
        [] -> ""
        values -> "    args: [#{Enum.map_join(values, ", ", &~s(\"#{&1}\"))}]\n"
      end

    entry = "\nmcpservers:\n  controlkeel:\n    command: #{command}\n" <> args_line

    with :ok <- File.write(config_path, String.trim_trailing(cleaned) <> entry) do
      {:ok,
       %{
         "server_name" => "controlkeel",
         "ide" => "aider",
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp goose_config_path do
    Path.join([user_home(), ".config", "goose", "config.yaml"])
  end

  defp attach_to_goose(command_spec, project_root) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []
    config_path = goose_config_path()

    existing = read_yaml_file(config_path)

    extension =
      %{
        "enabled" => true,
        "type" => "stdio",
        "name" => "ControlKeel",
        "description" => "ControlKeel governance MCP server",
        "cmd" => command,
        "args" => args,
        "timeout" => 300
      }

    updated =
      Map.put(
        existing,
        "extensions",
        existing
        |> Map.get("extensions", %{})
        |> normalize_yaml_map()
        |> Map.put("controlkeel", extension)
      )

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, yaml_document(updated)) do
      {:ok,
       %{
         "server_name" => "controlkeel",
         "ide" => "goose",
         "config_path" => config_path,
         "project_root" => Path.expand(project_root),
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp read_yaml_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  defp normalize_yaml_map(value) when is_map(value), do: value
  defp normalize_yaml_map(_value), do: %{}

  defp yaml_document(value) do
    yaml_encode(value, 0)
  end

  defp yaml_encode(value, indent) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("", fn {key, nested} ->
      yaml_key_value(to_string(key), nested, indent)
    end)
  end

  defp yaml_encode(value, indent) when is_list(value) do
    Enum.map_join(value, "", fn
      nested when is_map(nested) ->
        "#{String.duplicate(" ", indent)}-\n" <> yaml_encode(nested, indent + 2)

      nested ->
        "#{String.duplicate(" ", indent)}- #{yaml_scalar(nested)}\n"
    end)
  end

  defp yaml_key_value(key, value, indent) when is_map(value) do
    if map_size(value) == 0 do
      "#{String.duplicate(" ", indent)}#{key}: {}\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) when is_list(value) do
    if value == [] do
      "#{String.duplicate(" ", indent)}#{key}: []\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) do
    "#{String.duplicate(" ", indent)}#{key}: #{yaml_scalar(value)}\n"
  end

  defp yaml_scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_scalar(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp auto_attach_claude_code(project_root) do
    claude_dir = Path.join(user_home(), ".claude")
    command_spec = ProjectBinding.mcp_command_spec(project_root)

    cond do
      not File.dir?(claude_dir) ->
        {:skip, "claude-code not found on this system"}

      true ->
        case ClaudeCLI.attach_local(project_root, command_spec.command, command_spec.args) do
          {:ok, result} ->
            _ = Skills.install("claude-standalone", project_root, scope: "user")

            emit_attach_succeeded(
              %{"session_id" => nil, "workspace_id" => nil},
              project_root,
              result
            )

            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  defp format_domain_packs(packs) when is_binary(packs), do: format_domain_packs([packs])

  defp format_domain_packs(packs) when is_list(packs) do
    packs
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&Intent.pack_label/1)
    |> Enum.join(", ")
  end

  defp format_money(nil), do: "unlimited"
  defp format_money(cents), do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()
  defp format_duration(nil), do: "not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  defp github_repo_attached_agent(agent, scope, %{destination: destination}) do
    %{
      "target" => "github-repo",
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp github_repo_attached_agent(agent, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => plan.target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp attach_bundle_target(target, project_root, scope, options) do
    if native_attach_skipped?(options) do
      Skills.export(target, project_root, scope: "export")
    else
      Skills.install(target, project_root, scope: scope)
    end
  end

  defp bundled_attached_agent(agent, target, scope, %{destination: destination} = result) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "config_destination" => Map.get(result, :agent_destination),
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp bundled_attached_agent(agent, target, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp bundle_attach_lines(agent, %{destination: destination} = result) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Installed bundle at #{destination}."
    ] ++
      if(Map.has_key?(result, :agent_destination),
        do: ["Config destination: #{result.agent_destination}."],
        else: []
      )
  end

  defp bundle_attach_lines(agent, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Output: #{plan.output_dir}"
    ]
  end

  defp maybe_attach_line(_label, nil), do: []
  defp maybe_attach_line(label, path), do: ["#{label} at #{path}."]
end
