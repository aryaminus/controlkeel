defmodule ControlKeel.CLI do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.Intent
  alias ControlKeel.LocalProject
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.PolicyTraining
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Proxy
  alias ControlKeel.Skills

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
  @proofs_switches [session_id: :integer, task_id: :integer, deploy_ready: :boolean]
  @mcp_switches [project_root: :string]
  @memory_search_switches [session_id: :integer, type: :string]
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

      ["attach", agent | rest] ->
        if agent in AgentIntegration.ids() do
          parse_attach(agent, rest)
        else
          {:error, usage_text()}
        end

      ["status"] ->
        {:ok, %{command: :status, options: %{}, args: []}}

      ["findings" | rest] ->
        parse_with_switches(:findings, rest, @findings_switches)

      ["approve", finding_id] ->
        {:ok, %{command: :approve, options: %{}, args: [finding_id]}}

      ["proofs" | rest] ->
        parse_with_switches(:proofs, rest, @proofs_switches)

      ["proof", id] ->
        {:ok, %{command: :proof, options: %{}, args: [id]}}

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

      ["mcp" | rest] ->
        parse_with_switches(:mcp, rest, @mcp_switches)

      ["watch" | rest] ->
        parse_with_switches(:watch, rest, @watch_switches)

      ["help"] ->
        {:ok, %{command: :help, options: %{}, args: []}}

      ["version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      _ ->
        {:error, usage_text()}
    end
  end

  def app_required?(%{command: command}) when command in [:help, :version], do: false
  def app_required?(_parsed), do: true

  def server_mode?(%{command: :serve}), do: true
  def server_mode?(_parsed), do: false

  def execute(parsed, opts \\ []) do
    printer = Keyword.get(opts, :printer, &IO.puts/1)
    error_printer = Keyword.get(opts, :error_printer, fn line -> IO.puts(:stderr, line) end)
    project_root = Keyword.get(opts, :project_root, File.cwd!())

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

  def usage_text do
    """
    ControlKeel CLI

    Commands:
      controlkeel                     Start the web app
      controlkeel serve               Start the web app
      controlkeel init [options]      Initialize ControlKeel in the current project
      controlkeel attach <agent>      Register ControlKeel MCP server with your coding tool
                                      Native skills install by default unless --mcp-only
                                      Flags: --mcp-only, --no-native, --with-skills,
                                             --scope user|project
                                      Supported: #{supported_attach_agents_text()}
      controlkeel status              Show current session status
      controlkeel findings [options]  List findings for the current session
      controlkeel approve <id>        Approve a finding in the current session
      controlkeel proofs [options]    List proof bundles for the current session
      controlkeel proof <id>          Show a proof bundle by proof id or task id
      controlkeel pause <task-id>     Pause a task and capture a resume packet
      controlkeel resume <task-id>    Resume a paused or blocked task
      controlkeel memory search <q>   Search typed memory for the current session
      controlkeel skills list         List skills, diagnostics, and compatibility targets
      controlkeel skills validate     Validate the catalog for the current project
      controlkeel skills export       Export native skill/plugin bundles
      controlkeel skills install      Install skills for a native target
      controlkeel skills doctor       Show trust, catalog, and install health
      controlkeel benchmark list [--domain-pack pack]
                                      List built-in suites and recent runs
      controlkeel benchmark run [options]
                                      Run a benchmark suite and persist the matrix
      controlkeel benchmark show <id> Show a benchmark run with subject summaries
      controlkeel benchmark import <run-id> <subject> <json-file>
                                      Import manual benchmark output for a subject
      controlkeel benchmark export <run-id> [--format json|csv]
                                      Export a benchmark run
      controlkeel policy list         List recent policy artifacts and training runs
      controlkeel policy train --type router|budget_hint
                                      Train a new policy artifact
      controlkeel policy show <id>    Show a policy artifact
      controlkeel policy promote <id> Promote a policy artifact if gates pass
      controlkeel policy archive <id> Archive a policy artifact
      controlkeel watch [--interval N]
                                      Stream findings and budget live (default: 2000ms)
      controlkeel mcp [--project-root /abs/path]
                                      Run the MCP server for a project
      controlkeel help                Show this help
      controlkeel version             Show the current version
    """
  end

  def run_command(%{command: :serve}, _project_root), do: :ok
  def run_command(%{command: :help}, _project_root), do: {:ok, [usage_text()]}
  def run_command(%{command: :version}, _project_root), do: {:ok, ["ControlKeel #{version()}"]}

  def run_command(%{command: :init, options: options}, project_root) do
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

  def run_command(%{command: :attach, args: ["claude-code"], options: options}, project_root) do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, attached_agent} <- ClaudeCLI.attach_local(project_root, wrapper_path),
         updated_binding <-
           ProjectBinding.update_attached_agent(binding, "claude_code", attached_agent),
         {:ok, _binding} <- ProjectBinding.write(updated_binding, project_root) do
      emit_attach_succeeded(binding, project_root, attached_agent)

      {:ok,
       [
         "Attached ControlKeel to Claude Code.",
         "Verified with `claude mcp get controlkeel`."
       ] ++ native_attach_lines("claude-code", project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error,
         "Missing `#{wrapper_path}`. Run `controlkeel init` before attaching ControlKeel to Claude Code."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to Claude Code."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["cursor"], options: options}, project_root) do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, attached} <- attach_to_cursor(wrapper_path),
         updated <- ProjectBinding.update_attached_agent(binding, "cursor", attached),
         {:ok, _} <- ProjectBinding.write(updated, project_root) do
      {:ok,
       [
         "Attached ControlKeel to Cursor.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Cursor to activate."
       ] ++ native_attach_lines("cursor", project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error, "Missing `#{wrapper_path}`. Run `controlkeel init` first."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to Cursor."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Cursor: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["windsurf"], options: options}, project_root) do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, attached} <- attach_to_windsurf(wrapper_path),
         updated <- ProjectBinding.update_attached_agent(binding, "windsurf", attached),
         {:ok, _} <- ProjectBinding.write(updated, project_root) do
      {:ok,
       [
         "Attached ControlKeel to Windsurf.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Windsurf to activate."
       ] ++ native_attach_lines("windsurf", project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error, "Missing `#{wrapper_path}`. Run `controlkeel init` first."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to Windsurf."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Windsurf: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["kiro", "amp", "opencode", "gemini-cli", "codex-cli"] do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    config_path_fn = %{
      "kiro" => &kiro_mcp_config_path/0,
      "amp" => &amp_mcp_config_path/0,
      "opencode" => &opencode_mcp_config_path/0,
      "gemini-cli" => &gemini_cli_config_path/0,
      "codex-cli" => &codex_cli_config_path/0
    }

    display_name = %{
      "kiro" => "Kiro",
      "amp" => "Amp",
      "opencode" => "OpenCode",
      "gemini-cli" => "Gemini CLI",
      "codex-cli" => "Codex CLI"
    }

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         config_path <- config_path_fn[agent].(),
         {:ok, attached} <- write_ide_mcp_config(config_path, "controlkeel", wrapper_path, agent),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached),
         {:ok, _} <- ProjectBinding.write(updated, project_root) do
      {:ok,
       [
         "Attached ControlKeel to #{display_name[agent]}.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart #{display_name[agent]} to activate."
       ] ++ native_attach_lines(agent, project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error, "Missing `#{wrapper_path}`. Run `controlkeel init` first."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to #{display_name[agent]}."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to #{display_name[agent]}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["continue"], options: options}, project_root) do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, attached} <-
           write_continue_mcp_config(continue_config_path(), "controlkeel", wrapper_path),
         updated <- ProjectBinding.update_attached_agent(binding, "continue", attached),
         {:ok, _} <- ProjectBinding.write(updated, project_root) do
      {:ok,
       [
         "Attached ControlKeel to Continue.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Continue to activate."
       ] ++ native_attach_lines("continue", project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error, "Missing `#{wrapper_path}`. Run `controlkeel init` first."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to Continue."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Continue: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["aider"], options: options}, project_root) do
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    with true <- File.exists?(wrapper_path) || {:error, :wrapper_missing},
         {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, attached} <- attach_to_aider(wrapper_path, project_root),
         updated <- ProjectBinding.update_attached_agent(binding, "aider", attached),
         {:ok, _} <- ProjectBinding.write(updated, project_root) do
      {:ok,
       [
         "Attached ControlKeel to Aider.",
         "MCP config written to #{attached["config_path"]}."
       ] ++ native_attach_lines("aider", project_root, options)}
    else
      {:error, :wrapper_missing} ->
        {:error, "Missing `#{wrapper_path}`. Run `controlkeel init` first."}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before attaching ControlKeel to Aider."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Aider: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["vscode", "copilot"] do
    scope = attach_scope(agent, options)

    with {:ok, binding} <- ProjectBinding.read(project_root),
         {:ok, install_result} <- Skills.install("github-repo", project_root, scope: scope),
         attached_agent <- github_repo_attached_agent(agent, scope, install_result),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <- ProjectBinding.write(updated, project_root) do
      lines =
        case install_result do
          %{destination: destination} ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Installed project bundle at #{destination}.",
              "Repository MCP config written under .github and .vscode."
            ]

          %ControlKeel.Skills.SkillExportPlan{} = plan ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Output: #{plan.output_dir}"
            ]
        end

      {:ok, lines}
    else
      {:error, :not_found} ->
        {:error,
         "Run `controlkeel init` before attaching ControlKeel to #{display_attach_agent(agent)}."}

      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :status}, project_root) do
    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
        metrics = Analytics.session_metrics(session.id) || %{}
        rolling_24h = Budget.rolling_24h_spend_cents(session.id)

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
           "Funnel stage: #{Analytics.stage_label(metrics[:funnel_stage])}",
           "Time to first finding: #{format_duration(metrics[:time_to_first_finding_seconds])}",
           "Total findings: #{metrics[:total_findings] || 0}",
           "Blocked findings: #{metrics[:blocked_findings_total] || 0}",
           "OpenAI responses: #{Proxy.url(session, :openai, "/v1/responses")}",
           "OpenAI chat: #{Proxy.url(session, :openai, "/v1/chat/completions")}",
           "OpenAI realtime: #{Proxy.realtime_url(session, :openai, "/v1/realtime")}",
           "Anthropic messages: #{Proxy.url(session, :anthropic, "/v1/messages")}"
         ]}

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before checking status."}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :findings, options: options}, project_root) do
    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
        findings =
          Mission.list_session_findings(session.id, %{
            severity: options[:severity],
            status: options[:status]
          })

        if findings == [] do
          {:ok, ["No findings matched the current filters."]}
        else
          {:ok,
           Enum.map(findings, fn finding ->
             "##{finding.id} [#{finding.severity}/#{finding.status}] #{finding.title} (#{finding.rule_id})"
           end)}
        end

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before listing findings."}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :approve, args: [finding_id]}, project_root) do
    with {:ok, _binding, session} <- LocalProject.load(project_root),
         {:ok, parsed_id} <- parse_id(finding_id),
         finding when not is_nil(finding) <- Mission.get_finding(parsed_id),
         true <- finding.session_id == session.id || {:error, :wrong_session},
         {:ok, updated} <- Mission.approve_finding(finding) do
      {:ok, ["Approved finding ##{updated.id}: #{updated.title}"]}
    else
      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before approving findings."}

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
    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
        browser =
          Mission.browse_proof_bundles(%{
            session_id: options[:session_id] || session.id,
            task_id: options[:task_id],
            deploy_ready: options[:deploy_ready]
          })

        if browser.entries == [] do
          {:ok, ["No proof bundles matched the current filters."]}
        else
          {:ok,
           Enum.map(browser.entries, fn proof ->
             deploy = if proof.deploy_ready, do: "deploy-ready", else: "review-required"

             "##{proof.id} v#{proof.version} [#{proof.status}] #{proof.task.title} (risk #{proof.risk_score}, #{deploy})"
           end)}
        end

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before listing proofs."}

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

  def run_command(%{command: :benchmark_list, options: options}, project_root) do
    filter_opts = benchmark_filter_opts(options[:domain_pack])
    suites = Benchmark.list_suites(filter_opts)
    runs = Benchmark.list_recent_runs(filter_opts)
    subjects = Benchmark.available_subjects(project_root)

    suite_lines =
      if suites == [] do
        ["No benchmark suites are available."]
      else
        [
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

    {:ok, suite_lines ++ subject_lines ++ run_lines}
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
       ]}
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

  def run_command(%{command: :pause, args: [task_id]}, project_root) do
    with {:ok, _binding, session} <- LocalProject.load(project_root),
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
      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before pausing tasks."}

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
    with {:ok, _binding, session} <- LocalProject.load(project_root),
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
      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before resuming tasks."}

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
    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
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

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before searching memory."}

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

    native_first =
      integrations
      |> Enum.filter(&(&1.category in ["native-first", "repo-native"]))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    mcp_fallback =
      integrations
      |> Enum.filter(&(&1.category == "mcp-plus-instructions"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    {:ok,
     [
       "Project root: #{Path.expand(root)}",
       "Trusted project skills: #{if(analysis.trusted_project?, do: "yes", else: "no")}",
       "Catalog size: #{length(analysis.skills)}",
       "Native-first agents: #{native_first}",
       "MCP + instructions agents: #{mcp_fallback}"
     ] ++
       Enum.map(analysis.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :watch, options: options}, project_root) do
    interval = Keyword.get(options, :interval, 2_000)

    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
        IO.puts("")
        IO.puts("ControlKeel Watch — session ##{session.id}: #{session.title}")
        IO.puts("  Polling every #{interval}ms  ·  Ctrl+C to exit")
        IO.puts(String.duplicate("─", 60))
        watch_loop(session.id, MapSet.new(), interval)

      {:error, :not_found} ->
        {:error, "Run `controlkeel init` before watching."}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :mcp, options: options}, project_root) do
    root = Path.expand(options[:project_root] || project_root)

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
  end

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

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp format_ms(nil), do: "Not recorded"
  defp format_ms(value), do: "#{value}ms"

  defp format_active_artifact(nil), do: "heuristic"
  defp format_active_artifact(artifact), do: "v#{artifact.version} (##{artifact.id})"

  defp emit_attach_succeeded(binding, project_root, attached_agent) do
    :telemetry.execute(
      [:controlkeel, :claude, :attach, :succeeded],
      %{count: 1},
      %{
        session_id: binding["session_id"],
        workspace_id: binding["workspace_id"],
        project_root: Path.expand(project_root),
        server_name: attached_agent["server_name"],
        scope: attached_agent["scope"]
      }
    )
  end

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

  defp native_attach_lines("codex-cli", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("codex", project_root, scope: attach_scope("codex-cli", options)) do
        {:ok, %{destination: destination, agent_destination: agent_destination}} ->
          [
            "Installed Codex skills at #{destination}.",
            "Installed Codex companion agent at #{agent_destination}."
          ]

        {:error, reason} ->
          ["Native Codex skills were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines(agent, project_root, options)
       when agent in [
              "cursor",
              "windsurf",
              "kiro",
              "amp",
              "opencode",
              "gemini-cli",
              "continue",
              "aider"
            ] do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.export("instructions-only", project_root, scope: "export") do
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

  defp attach_scope("claude-code", options), do: options[:scope] || "user"
  defp attach_scope("codex-cli", options), do: options[:scope] || "user"
  defp attach_scope(_agent, options), do: options[:scope] || "project"

  defp display_attach_agent(agent), do: AgentIntegration.label(agent)

  # ─── IDE MCP attachment helpers ──────────────────────────────────────────────

  defp attach_to_cursor(wrapper_path) do
    config_path = cursor_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", wrapper_path, "cursor")
  end

  defp attach_to_windsurf(wrapper_path) do
    config_path = windsurf_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", wrapper_path, "windsurf")
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

  defp write_ide_mcp_config(config_path, server_name, command_path, ide_key) do
    existing =
      case File.read(config_path) do
        {:ok, contents} -> Jason.decode(contents) |> elem(1)
        _ -> %{}
      end || %{}

    mcpServers = Map.get(existing, "mcpServers", %{})

    updated =
      Map.put(
        existing,
        "mcpServers",
        Map.put(mcpServers, server_name, %{
          "command" => command_path,
          "args" => []
        })
      )

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => ide_key,
         "config_path" => config_path,
         "command" => command_path,
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

  defp amp_mcp_config_path do
    Path.join([user_home(), ".config", "amp", "mcp.json"])
  end

  defp opencode_mcp_config_path do
    Path.join([user_home(), ".config", "opencode", "config.json"])
  end

  defp gemini_cli_config_path do
    Path.join([user_home(), ".gemini", "settings.json"])
  end

  defp codex_cli_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, ".codex", "config.json"])

      _ ->
        Path.join([home, ".codex", "config.json"])
    end
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
  defp write_continue_mcp_config(config_path, server_name, command_path) do
    existing =
      case File.read(config_path) do
        {:ok, c} -> Jason.decode(c) |> elem(1)
        _ -> %{}
      end || %{}

    servers = Map.get(existing, "mcpServers", [])
    filtered = Enum.reject(servers, &(Map.get(&1, "name") == server_name))
    new_entry = %{"name" => server_name, "command" => command_path, "args" => []}
    updated = Map.put(existing, "mcpServers", filtered ++ [new_entry])

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => "continue",
         "config_path" => config_path,
         "command" => command_path,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  # Aider uses a YAML config file (.aider.conf.yml) at the project root
  defp attach_to_aider(wrapper_path, project_root) do
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

    entry = "\nmcpservers:\n  controlkeel:\n    command: #{wrapper_path}\n"

    with :ok <- File.write(config_path, String.trim_trailing(cleaned) <> entry) do
      {:ok,
       %{
         "server_name" => "controlkeel",
         "ide" => "aider",
         "config_path" => config_path,
         "command" => wrapper_path,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp auto_attach_claude_code(project_root) do
    claude_dir = Path.join(user_home(), ".claude")
    wrapper_path = ProjectBinding.mcp_wrapper_path(project_root)

    cond do
      not File.dir?(claude_dir) ->
        {:skip, "claude-code not found on this system"}

      not File.exists?(wrapper_path) ->
        {:skip, "wrapper not yet written"}

      true ->
        case ClaudeCLI.attach_local(project_root, wrapper_path) do
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

  defp supported_attach_agents_text do
    Skills.agent_integrations()
    |> Enum.map(& &1.id)
    |> Enum.join(", ")
  end
end
