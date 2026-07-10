defmodule ControlKeel.CLI do
  @moduledoc false

  # IMPORTANT: run_command/2 clauses are intentionally organized by functionality
  # (skills, deploy, observability, etc.) rather than grouped together for maintainability.
  # The compiler warning about clause grouping is expected and acceptable.
  # Grouping all run_command clauses together would harm maintainability.

  require Logger

  alias ControlKeel.Agent.Integration
  alias ControlKeel.Agent.AttachedSync
  alias ControlKeel.Budget
  alias ControlKeel.CLI.Claude
  alias ControlKeel.Ops.Distribution
  alias ControlKeel.Ops.HostingCost
  alias ControlKeel.Governance
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.CLI.Parser
  alias ControlKeel.CLI.Help
  alias ControlKeel.Intent
  alias ControlKeel.Project.Local
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Project.Binding
  alias ControlKeel.Project.Root
  alias ControlKeel.Mission.ReviewBridge
  alias ControlKeel.CLI.SetupAdvisor
  alias ControlKeel.Skills
  alias ControlKeel.Project.WorkspaceContext
  alias ControlKeel.Utils.Yaml, as: UtilsYaml
  alias ControlKeelWeb.Endpoint

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

  def parse(argv), do: Parser.parse(argv)

  defdelegate render_format(format, payload, text_fn), to: ControlKeel.CLI.Output

  def app_required?(%{command: command}) when command in [:help, :version], do: false
  def app_required?(_parsed), do: true

  def server_mode?(%{command: :serve}), do: true
  def server_mode?(_parsed), do: false

  def execute(parsed, opts \\ []) do
    if json_mode?(parsed) do
      Logger.configure(level: :error)
    end

    printer = Keyword.get(opts, :printer, &IO.puts/1)
    error_printer = Keyword.get(opts, :error_printer, fn line -> IO.puts(:stderr, line) end)
    json_error_printer = Keyword.get(opts, :json_error_printer, &IO.puts/1)

    project_root =
      opts
      |> Keyword.get(:project_root, File.cwd!())
      |> Root.resolve()

    case run_command(parsed, project_root) do
      {:ok, lines} ->
        lines = maybe_wrap_success_envelope(parsed, lines)
        Enum.each(List.wrap(lines), printer)
        0

      :ok ->
        0

      {:error, message} ->
        if json_mode?(parsed) do
          entry = Catalog.for_command(parsed.command)
          json_error_printer.(ControlKeel.CLI.Output.error_json(message, :command_error, entry))
        else
          error_printer.(message)
        end

        1

      {:error, _reason, detail} when is_binary(detail) ->
        if json_mode?(parsed) do
          entry = Catalog.for_command(parsed.command)
          json_error_printer.(ControlKeel.CLI.Output.error_json(detail, :command_error, entry))
        else
          error_printer.("Failed: #{detail}")
        end

        1

      {:error, reason, _extra} ->
        if json_mode?(parsed) do
          entry = Catalog.for_command(parsed.command)

          json_error_printer.(
            ControlKeel.CLI.Output.error_json(inspect(reason), :command_error, entry)
          )
        else
          error_printer.("Failed: #{inspect(reason)}")
        end

        1
    end
  end

  def json_mode?(parsed) do
    options = Map.get(parsed, :options, %{})
    options[:json] == true or options[:format] in ["json", "JSON"]
  end

  # Commands whose JSON output is machine-to-machine data (export/import round-trips)
  # and should NOT be wrapped in the success envelope.
  @skip_envelope_commands ~w(obs_export obs_import audit_export)a

  def maybe_wrap_success_envelope(parsed, lines) do
    options = Map.get(parsed, :options, %{})
    json? = options[:json] == true or options[:format] == "json"
    skip? = parsed.command in @skip_envelope_commands

    if json? and not skip? and is_list(lines) and length(lines) == 1 do
      [line] = lines

      if is_binary(line) and String.starts_with?(line, "{") do
        case Jason.decode(line) do
          {:ok, %{"status" => status, "data" => _}} when status in ["ok", "error"] ->
            lines

          {:ok, payload} ->
            command_path = catalog_path_for_command(parsed.command)
            [ControlKeel.CLI.Output.success_json(command_path, payload, version: version())]

          {:error, _} ->
            lines
        end
      else
        lines
      end
    else
      lines
    end
  end

  def catalog_path_for_command(command) when is_atom(command) do
    case Catalog.for_command(command) do
      nil -> command |> Atom.to_string() |> String.replace("_", " ")
      entry -> entry.path
    end
  end

  def version do
    Application.spec(:controlkeel, :vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  def usage_text, do: Help.usage_text()

  def run_command(%{command: command} = parsed, project_root) do
    case ControlKeel.CLI.Catalog.for_command(command) do
      %{family: family} ->
        module = Map.fetch!(dispatch_modules(), family)
        module.run_command(parsed, project_root)

      nil ->
        {:error, "Unknown command: #{command}"}
    end
  end

  def run_command(_parsed, _project_root) do
    {:error, "Invalid command payload"}
  end

  def dispatch_modules do
    %{
      core: ControlKeel.CLI.Dispatch.Core,
      attach_hosts: ControlKeel.CLI.Dispatch.AttachHosts,
      governance: ControlKeel.CLI.Dispatch.Governance,
      review: ControlKeel.CLI.Dispatch.Review,
      execution: ControlKeel.CLI.Dispatch.Execution,
      observability: ControlKeel.CLI.Dispatch.Observability,
      memory_continuity: ControlKeel.CLI.Dispatch.MemoryContinuity,
      mcp_tools: ControlKeel.CLI.Dispatch.McpTools,
      skills_plugins_hooks: ControlKeel.CLI.Dispatch.SkillsPluginsHooks,
      cloud_selfhost: ControlKeel.CLI.Dispatch.CloudSelfhost,
      providers_budget: ControlKeel.CLI.Dispatch.ProvidersBudget,
      sandbox_security_code_mode: ControlKeel.CLI.Dispatch.SandboxSecurityCodeMode,
      benchmarks_harness: ControlKeel.CLI.Dispatch.BenchmarksHarness,
      deployment_portability: ControlKeel.CLI.Dispatch.DeploymentPortability,
      learning_loop: ControlKeel.CLI.Dispatch.LearningLoop
    }
  end

  def format_default_branch(nil), do: ""
  def format_default_branch(""), do: ""
  def format_default_branch(branch), do: " (default branch: #{branch})"

  def format_installation(nil), do: ""
  def format_installation(""), do: ""
  def format_installation(id), do: " (installation #{id})"

  def maybe_put_kw(opts, _key, nil), do: opts
  def maybe_put_kw(opts, _key, ""), do: opts
  def maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  def response_summary(%{status: status, body: body}) when is_map(body) do
    "#{status} workspace=#{Map.get(body, "workspace_id") || Map.get(body, :workspace_id) || "?"}"
  end

  def response_summary(%{status: status}), do: "#{status}"

  def enroll_remote(identity, base_url, opts) do
    alias ControlKeel.Cloud.Enrollment

    register_url = String.trim_trailing(base_url, "/") <> "/cloud/v1/workspaces/register"

    with {:ok, envelope} <- Enrollment.build(identity, opts),
         {:ok, response} <- post_enrollment(register_url, envelope) do
      {:ok,
       [
         "Enrolled with: #{base_url}",
         "Server response: #{response_summary(response)}"
       ]}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def post_enrollment(url, envelope) do
    http_module = Application.get_env(:controlkeel, :cloud_enrollment_http_module, Req)

    case http_module.post(url, json: envelope, receive_timeout: 10_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "server returned #{status}: #{inspect(body)}"}

      {:error, %{__exception__: true} = error} ->
        {:error, Exception.message(error)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def skills_list_payload(root, selected_target, skills, diagnostics) do
    %{
      "project_root" => Path.expand(root),
      "target" => selected_target,
      "skills" => Enum.map(skills, &skill_payload/1),
      "diagnostics" => Enum.map(diagnostics, &skill_diagnostic_payload/1)
    }
  end

  def skill_payload(skill) do
    %{
      "name" => skill.name,
      "description" => skill.description,
      "path" => skill.path,
      "scope" => skill.scope,
      "compatibility_targets" => skill.compatibility_targets || [],
      "required_mcp_tools" => skill.required_mcp_tools || []
    }
  end

  def skill_diagnostic_payload(diagnostic) do
    %{
      "level" => diagnostic.level,
      "code" => diagnostic.code,
      "message" => diagnostic.message,
      "path" => diagnostic.path,
      "skill_name" => diagnostic.skill_name
    }
  end

  def format_skills_list(skills, diagnostics) do
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
      if diagnostics == [] do
        []
      else
        ["", "Diagnostics:"] ++
          Enum.map(diagnostics, fn diagnostic ->
            "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
          end)
      end

    lines ++ diagnostic_lines
  end

  def format_token_audit(result, mode, "text") do
    case mode do
      "full" ->
        rule_files = result["rule_files"] || []
        skills = result["effective_skills"] || result["skills"] || []
        installed_skill_copies = result["installed_skill_copies"] || length(skills)
        duplicates = result["skill_duplicates"] || result["duplicates"] || []

        recommendations =
          (result["recommendations"] || []) ++ (result["skill_recommendations"] || [])

        [
          "Token Audit Results",
          "===================",
          "",
          "Project root: #{result["project_root"]}",
          "Total estimated tokens: #{result["estimated_tokens"]}",
          "Rule files: #{length(rule_files)}",
          "Effective skills: #{length(skills)}",
          "Installed skill copies: #{installed_skill_copies}",
          "Skill tokens: #{result["total_skill_tokens"] || 0}",
          "Duplicate skill groups: #{length(duplicates)}",
          "Duplicate skill tokens: #{result["duplicate_token_count"] || 0}",
          "",
          "Rule files:"
        ] ++
          Enum.map(rule_files, fn rf -> "  - #{rf["path"]} (#{token_count(rf)} tokens)" end) ++
          [
            "",
            "Skills:"
          ] ++
          Enum.map(skills, fn s -> "  - #{s["name"]} (#{token_count(s)} tokens)" end) ++
          [
            "",
            "Duplicate skill groups:"
          ] ++
          Enum.map(duplicates, &format_skill_duplicate/1) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(recommendations, fn r -> "  - #{r}" end)

      "rules" ->
        rule_files = result["rule_files"] || []

        [
          "Token Audit - Rule Files",
          "=========================",
          "",
          "Project root: #{result["project_root"]}",
          "Total rule tokens: #{result["estimated_tokens"]}",
          "Rule files: #{length(rule_files)}",
          ""
        ] ++
          Enum.map(rule_files, fn rf -> "  - #{rf["path"]} (#{token_count(rf)} tokens)" end)

      "skills" ->
        skills = result["effective_skills"] || result["skills"] || []
        installed_skill_copies = result["installed_skill_copies"] || length(skills)
        duplicates = result["duplicates"] || []

        [
          "Token Audit - Skills",
          "====================",
          "",
          "Project root: #{result["project_root"]}",
          "Total skill tokens: #{result["total_skill_tokens"] || result["estimated_tokens"] || 0}",
          "Duplicate skill tokens: #{result["duplicate_token_count"] || 0}",
          "Effective skills: #{length(skills)}",
          "Installed skill copies: #{installed_skill_copies}",
          "Duplicate skill groups: #{length(duplicates)}",
          ""
        ] ++
          Enum.map(skills, fn s -> "  - #{s["name"]} (#{token_count(s)} tokens)" end) ++
          [
            "",
            "Duplicate skill groups:"
          ] ++
          Enum.map(duplicates, &format_skill_duplicate/1) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(result["recommendations"] || [], fn r -> "  - #{r}" end)

      "tools" ->
        tools = result["tools"] || []

        [
          "Token Audit - Tools",
          "===================",
          "",
          "Project root: #{result["project_root"]}",
          "Total tool tokens: #{result["total_tokens"] || result["estimated_tokens"] || 0}",
          "Tools: #{length(tools)}",
          ""
        ] ++
          Enum.map(tools, fn t -> "  - #{t["name"]} (#{token_count(t)} tokens)" end) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(result["recommendations"] || [], fn r -> "  - #{r}" end)
    end
  end

  def format_token_audit(result, _mode, "json") do
    [Jason.encode!(result, pretty: true)]
  end

  def token_count(item) when is_map(item) do
    item["tokens"] || item["estimated_tokens"] || item["total_tokens"] || 0
  end

  def format_skill_duplicate(%{"name" => name} = duplicate) do
    locations =
      duplicate
      |> Map.get("locations", [])
      |> Enum.join(", ")

    "  - #{name}: #{duplicate["count"] || 0} copies, #{duplicate["total_tokens"] || 0} tokens (#{locations})"
  end

  def format_skill_duplicate(duplicate) when is_map(duplicate) do
    "  - #{duplicate["path"] || "unknown"} (duplicate of #{duplicate["original"] || "unknown"})"
  end

  def format_tool_groups_suggest(groups, reason, stats, "text") do
    [
      "Tool Groups Suggestion:",
      "  Suggested groups: #{inspect(groups)}",
      "  Reason: #{reason}",
      "  Usage stats:",
      "    Total calls: #{stats.total_calls}",
      "    Unique tools: #{stats.unique_tools}",
      "",
      "To apply this suggestion to your project, run:",
      "  controlkeel tool groups suggest --apply"
    ]
  end

  def format_tool_groups_suggest(groups, reason, stats, "json") do
    Jason.encode!(
      %{
        suggested: groups,
        reason: reason,
        usage_stats: stats
      },
      pretty: true
    )
    |> then(&[&1])
  end

  def deployment_stacks, do: [:phoenix, :react, :rails, :node, :python, :static]
  def hosting_tiers, do: HostingCost.available_tiers() |> Map.keys()
  def database_tiers, do: HostingCost.available_database_tiers() |> Map.keys()

  def parse_atom_option(value, allowed, _field) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid}
  end

  def parse_atom_option(value, allowed, field) when is_binary(value) do
    trimmed = String.trim(value)

    case Enum.find(allowed, &(to_string(&1) == trimmed)) do
      nil ->
        {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

      atom ->
        {:ok, atom}
    end
  end

  def parse_atom_option(_value, allowed, field),
    do: {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

  def watch_loop(session_id, seen, interval) do
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
        "  Budget  #{bar}  #{format_money(spent)}/#{format_money(budget)} (#{pct}%)  | rolling 24h: #{format_money(rolling)}"
      )

      IO.puts(String.duplicate("─", 60))
    end

    Process.sleep(interval)
    watch_loop(session_id, updated_seen, interval)
  end

  def required_option(options, key, flag) do
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

  def governance_opts(options, project_root) do
    [
      session_id: options[:session_id] || binding_session_id(project_root),
      domain_pack: options[:domain_pack],
      project_root: project_root,
      github: github_metadata_from_env()
    ]
  end

  def release_ready_session_id(options, project_root) do
    case options[:session_id] || binding_session_id(project_root) do
      nil ->
        {:error,
         "Release readiness requires --session-id or an existing project binding in the current repo."}

      session_id ->
        {:ok, session_id}
    end
  end

  def release_ready_opts(options, project_root) do
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

  def patch_input(options) do
    cond do
      is_binary(options[:url]) and options[:url] != "" ->
        Governance.review_pr_url(
          options[:url],
          governance_opts(options, options[:project_root] || File.cwd!())
        )

      is_binary(options[:patch]) and options[:patch] != "" ->
        case File.read(options[:patch]) do
          {:ok, patch} -> {:ok, patch}
          {:error, reason} -> {:error, "Failed to read patch file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        {:ok, IO.read(:stdio, :eof)}

      true ->
        {:error, "Provide --url <github-pr>, --patch <file>, or --stdin."}
    end
  end

  def review_pr_input(options, project_root) do
    root = options[:project_root] || project_root

    case patch_input(Keyword.put(options, :project_root, root)) do
      {:ok, %{} = review} ->
        {:ok, review}

      {:ok, patch} when is_binary(patch) ->
        Governance.review_patch(patch, governance_opts(options, root))

      {:error, reason} ->
        {:error, reason}
    end
  end

  def review_submission_input(options) do
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

  def review_submission_attrs(options, submission_body, project_root) do
    runtime_context = review_runtime_context_from_env()
    effective_project_root = review_scope_project_root(project_root, runtime_context)

    inferred_scope =
      cond do
        is_integer(options[:task_id]) ->
          %{task_id: options[:task_id], session_id: options[:session_id], source: "explicit"}

        is_integer(options[:session_id]) ->
          %{task_id: nil, session_id: options[:session_id], source: "explicit"}

        true ->
          infer_review_scope(runtime_context, effective_project_root)
      end

    {:ok,
     %{
       "session_id" => options[:session_id] || inferred_scope.session_id,
       "task_id" => options[:task_id] || inferred_scope.task_id,
       "title" => options[:title],
       "review_type" => "plan",
       "submission_body" => submission_body,
       "submitted_by" => options[:submitted_by] || runtime_context["agent_id"] || "cli",
       "metadata" => %{
         "runtime_context" => runtime_context,
         "body_file" => options[:body_file],
         "inferred_scope" => %{
           "task_id" => inferred_scope.task_id,
           "session_id" => inferred_scope.session_id,
           "source" => inferred_scope.source
         },
         "effective_project_root" => effective_project_root
       }
     }}
  end

  def review_response_attrs(options, decision) do
    %{
      "decision" => decision,
      "feedback_notes" => options[:feedback_notes],
      "reviewed_by" => options[:reviewed_by] || "cli",
      "annotations" => parse_review_annotations(options[:annotations])
    }
  end

  def infer_review_scope(runtime_context, project_root) do
    runtime_task_id = parse_optional_integer(runtime_context["task_id"])
    runtime_session_id = parse_optional_integer(runtime_context["session_id"])

    cond do
      is_integer(runtime_task_id) ->
        %{task_id: runtime_task_id, session_id: runtime_session_id, source: "runtime_context"}

      is_integer(runtime_session_id) ->
        %{task_id: nil, session_id: runtime_session_id, source: "runtime_context"}

      true ->
        infer_review_scope_from_binding(project_root)
    end
  end

  def infer_review_scope_from_binding(project_root) do
    resolved_root = Root.resolve(project_root)

    case Local.load(resolved_root) do
      {:ok, _binding, session} ->
        task = current_session_task(session)

        %{
          task_id: task && task.id,
          session_id: session.id,
          source: "project_binding"
        }

      _ ->
        %{task_id: nil, session_id: nil, source: "none"}
    end
  end

  def review_scope_project_root(project_root, runtime_context) do
    runtime_root = Map.get(runtime_context, "project_root")

    candidate =
      cond do
        is_binary(project_root) and project_root != "" -> project_root
        is_binary(runtime_root) and runtime_root != "" -> runtime_root
        true -> File.cwd!()
      end

    Root.resolve(candidate)
  end

  def parse_optional_integer(value) when is_integer(value), do: value

  def parse_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  def parse_optional_integer(_value), do: nil

  def task_in_current_session(project_root, task_id) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session} do
      {:ok, task}
    else
      {:error, :wrong_session} -> {:error, :wrong_session}
      {:error, :invalid_id} -> {:error, :invalid_id}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  def optional_risk_tier(nil), do: {:ok, nil}
  def optional_risk_tier(""), do: {:ok, nil}

  def optional_risk_tier(value) when value in ["low", "medium", "high", "critical"],
    do: {:ok, value}

  def optional_risk_tier(_value),
    do: {:error, "--risk-tier must be one of low, medium, high, critical"}

  def parse_allowed_agents(nil), do: nil
  def parse_allowed_agents(""), do: nil

  def parse_allowed_agents(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def normalize_task_execution_mode(nil), do: "local"
  def normalize_task_execution_mode(""), do: "local"
  def normalize_task_execution_mode("agent"), do: "local"
  def normalize_task_execution_mode("human"), do: "local"
  def normalize_task_execution_mode("runtime"), do: "external"

  def normalize_task_execution_mode(value) when value in ["local", "cloud", "external"],
    do: value

  def normalize_task_execution_mode(_value), do: "local"

  def decode_required_json_list(nil, option), do: {:error, {:missing_option, option}}
  def decode_required_json_list("", option), do: {:error, {:missing_option, option}}

  def decode_required_json_list(value, option) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) ->
        {:ok, list}

      {:ok, _other} ->
        {:error, "--#{option} must decode to a JSON array"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "--#{option} must be valid JSON: #{Exception.message(error)}"}
    end
  end

  def decode_optional_json_map(nil, _option), do: {:ok, %{}}
  def decode_optional_json_map("", _option), do: {:ok, %{}}

  def decode_optional_json_map(value, option) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = map} ->
        {:ok, map}

      {:ok, _other} ->
        {:error, "--#{option} must decode to a JSON object"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "--#{option} must be valid JSON: #{Exception.message(error)}"}
    end
  end

  def parse_review_annotations(nil), do: %{}

  def parse_review_annotations(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = annotations} -> annotations
      _ -> %{"cli_notes" => value}
    end
  end

  def required_integer_option(options, key, flag) do
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

  def socket_report_input(options) do
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

  def plugin_target("codex"), do: {:ok, "codex-plugin"}
  def plugin_target("claude"), do: {:ok, "claude-plugin"}
  def plugin_target("copilot"), do: {:ok, "copilot-plugin"}
  def plugin_target("openclaw"), do: {:ok, "openclaw-plugin"}
  def plugin_target("augment"), do: {:ok, "augment-plugin"}
  def plugin_target("droid"), do: {:ok, "droid-plugin"}
  def plugin_target(_plugin), do: {:error, :unknown_plugin}

  def plugin_mcp_hint("hosted"), do: ".mcp.hosted.json"
  def plugin_mcp_hint(_mode), do: ".mcp.json"

  def agent_run_opts(options, project_root) do
    []
    |> maybe_put_cli_opt(:project_root, project_root)
    |> maybe_put_cli_opt(:agent, options[:agent])
    |> maybe_put_cli_opt(:mode, options[:mode])
    |> maybe_put_cli_opt(:sandbox, options[:sandbox])
  end

  def maybe_put_cli_opt(opts, _key, nil), do: opts
  def maybe_put_cli_opt(opts, key, value), do: Keyword.put(opts, key, value)

  def read_json_config(path) do
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

  def maybe_cli_line(_label, nil), do: []
  def maybe_cli_line(label, value), do: ["#{label}: #{value}"]

  def attached_agent_status_lines(binding) do
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

  def contextual_status_help_lines(_session, task, active_findings, improvement) do
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

  def findings_help_lines(findings, options) do
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

  def findings_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("severity", options[:severity])
      |> maybe_add_filter("status", options[:status])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  def effective_cli_format(options) when is_list(options) do
    if Keyword.get(options, :json) == true do
      {:ok, "json"}
    else
      cli_output_format(options)
    end
  end

  def effective_cli_format(options) when is_map(options) do
    if Map.get(options, :json) == true or Map.get(options, "json") == true do
      {:ok, "json"}
    else
      cli_output_format(options)
    end
  end

  def maybe_put_tool_int(map, _key, nil), do: map

  def maybe_put_tool_int(map, key, id) when is_integer(id), do: Map.put(map, key, id)

  def maybe_put_tool_string(map, _key, nil), do: map
  def maybe_put_tool_string(map, _key, ""), do: map

  def maybe_put_tool_string(map, key, path) when is_binary(path), do: Map.put(map, key, path)

  def cli_output_format(options) when is_list(options) do
    case options[:format] do
      nil ->
        {:ok, "text"}

      "text" ->
        {:ok, "text"}

      "json" ->
        {:ok, "json"}

      other ->
        {:error, {:invalid_output_format, "Output format must be text or json, got #{other}."}}
    end
  end

  def cli_output_format(options) when is_map(options) do
    case Map.get(options, :format) || Map.get(options, "format") do
      nil ->
        {:ok, "text"}

      "text" ->
        {:ok, "text"}

      "json" ->
        {:ok, "json"}

      other ->
        {:error, {:invalid_output_format, "Output format must be text or json, got #{other}."}}
    end
  end

  def cli_output_format(_options), do: {:ok, "text"}

  def observability_loop_status_lines(loop) do
    [
      "Observability learning loop: #{loop.health}",
      "Mode: #{loop.learning_loop.mode}",
      "Read-only: #{loop.read_only} | Mutation: #{loop.mutation}",
      "Automatic benchmark execution: #{loop.learning_loop.automatic_benchmark_execution}",
      "Automatic promotion: #{loop.learning_loop.automatic_promotion}",
      "Problems: #{loop.active_problems.count} group(s) / #{loop.active_problems.total_findings} finding(s)",
      "Evals: #{loop.evals.derived} derived / #{loop.evals.saved} saved",
      "Benchmarks: #{loop.benchmarks.drafts} draft(s), #{loop.benchmarks.scenarios} scenario(s), readiness #{loop.benchmarks.history_readiness.status}",
      "Promotions: #{loop.promotions.count} candidate(s), readiness #{format_frequency(loop.promotions.by_readiness)}",
      "Blockers:"
    ] ++
      Enum.map(loop.blockers, &"- #{&1.id}: #{&1.reason}") ++
      ["Next actions:"] ++
      Enum.map(loop.next_actions, fn action ->
        "- [#{action.priority}] #{action.title}: #{action.suggested_action}"
      end) ++
      ["Recommendations:"] ++ Enum.map(loop.recommendations, &"- #{&1}")
  end

  def observability_problem_lines(problems) do
    [
      "Observability problems: #{problems.count} grouped / #{problems.total_findings} active finding(s)",
      "Health: #{problems.health}",
      "Recommendations:"
    ] ++
      Enum.map(problems.recommendations, &"- #{&1}") ++
      Enum.flat_map(problems.problems, fn problem ->
        [
          "",
          "[#{problem.health}] #{problem.rule_id} (#{problem.category})",
          "  Severity: #{problem.severity} | Count: #{problem.count} | Sessions: #{problem.affected_session_count}",
          "  Last seen: #{problem.last_seen || "unknown"}",
          "  Next: #{problem.recommendation}",
          "  Feedback loop: #{problem.feedback_loop.eval_candidate_title}",
          "  Eval action: #{problem.feedback_loop.suggested_action}",
          "  Benchmark hint: #{problem.feedback_loop.benchmark_hint}",
          "  Human gate required: #{problem.feedback_loop.human_gate_required}"
        ]
      end)
  end

  def observability_export_lines(envelope) do
    session = envelope.session_run.session
    integrity = envelope.integrity

    [
      "Observability export preview: #{session.title} (##{session.id})",
      "Schema: #{envelope.schema_version}",
      "Exported at: #{envelope.exported_at}",
      "Health: #{integrity.health}",
      "Timeline events: #{integrity.timeline_events}",
      "Active findings: #{integrity.active_findings}",
      "Problem groups: #{integrity.problem_groups}",
      "Redaction: #{envelope.redaction.policy} (raw context/memory/tool inputs excluded)",
      "Integrity: import mutation allowed = #{integrity.import_mutation_allowed}",
      "Use --format json to write a portable envelope."
    ]
  end

  def observability_import(file_path, options, project_root) do
    cond do
      options[:persist] == true ->
        ObservabilityTelemetry.import_persist(file_path, observability_import_opts(project_root))

      options[:dry_run] == true ->
        ObservabilityTelemetry.import_preview(file_path, dry_run: true)

      true ->
        {:error, :dry_run_required}
    end
  end

  def observability_import_opts(project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        [workspace_id: session.workspace_id, session_id: session.id]

      _other ->
        []
    end
  end

  def observability_import_lines(%{dry_run: true} = preview) do
    [
      "Observability import dry-run:",
      "Schema: #{preview.schema_version}",
      "Exported at: #{preview.exported_at}",
      "Session: #{preview.session_title || "unknown"} (##{preview.session_id || "unknown"})",
      "Health: #{preview.health || "unknown"}",
      "Problem groups: #{preview.problem_groups}",
      "Total problem findings: #{preview.total_problem_findings}",
      "Redaction: #{preview.redaction_policy || "unknown"}",
      "Integrity: #{preview.integrity_status || "unknown"}",
      "Mutation: #{preview.mutation}"
    ]
  end

  def observability_import_lines(result) do
    [
      "Observability import persisted:",
      "Status: #{result.status}",
      "Record: ##{result.id}",
      "Schema: #{result.schema_version}",
      "Exported at: #{result.exported_at}",
      "Imported at: #{result.imported_at}",
      "Session: #{result.session_title || "unknown"} (##{result.session_id || "unknown"})",
      "Health: #{result.health || "unknown"}",
      "Problem groups: #{result.problem_groups}",
      "Total problem findings: #{result.total_problem_findings}",
      "Redaction: #{result.redaction_policy || "unknown"}",
      "Integrity: #{result.integrity_status || "unknown"}",
      "Mutation: #{result.mutation}"
    ]
  end

  def observability_memory_quality_lines(quality) do
    totals = quality.totals

    [
      "Observability memory quality: #{totals.records} record(s)",
      "Active: #{totals.active} / Archived: #{totals.archived}",
      "Stale candidates: #{totals.stale_candidates} (threshold #{quality.stale_days} day(s))",
      "Duplicate clusters: #{totals.duplicate_clusters}",
      "Contradiction candidates: #{totals.contradiction_candidates}",
      "Missed-memory sessions: #{totals.missed_memory_sessions}",
      "Types: #{format_frequency(quality.distributions.by_type)}",
      "Sources: #{format_frequency(quality.distributions.by_source)}",
      "Recommendations:"
    ] ++
      Enum.map(quality.recommendations, &"- #{&1}") ++
      ["Stale memory:"] ++
      Enum.map(quality.stale_candidates, fn record ->
        "- ##{record.id} #{record.title} (#{record.age_days || 0} day(s), #{record.record_type})"
      end) ++
      ["Duplicate clusters:"] ++
      Enum.map(quality.duplicate_clusters, fn cluster ->
        "- #{cluster.key}: #{cluster.count} record(s)"
      end) ++
      ["Missed-memory sessions:"] ++
      Enum.map(quality.missed_memory_sessions, fn session ->
        "- ##{session.id} #{session.title}: #{session.findings} finding(s), #{session.reviews} review(s), #{session.invocations} invocation(s)"
      end)
  end

  def observability_trend_lines(trends) do
    totals = trends.totals

    [
      "Observability trends: #{trends.start_date} to #{trends.end_date} (#{trends.days} day(s))",
      "Runs: #{totals.runs} total (#{totals.red_runs} red / #{totals.yellow_runs} yellow / #{totals.green_runs} green)",
      "Findings: #{totals.active_findings} active / #{totals.blocked_findings} blocked",
      "Estimated spend: #{format_money(totals.estimated_cost_cents)}",
      "Imports: #{totals.imports} persisted (#{totals.verified_imports} verified / #{totals.non_verified_imports} non-verified)",
      "Daily series:"
    ] ++
      Enum.map(trends.series, fn day ->
        "- #{day.date}: #{day.runs} run(s), red #{day.health.red}, yellow #{day.health.yellow}, green #{day.health.green}, findings #{day.active_findings}/#{day.blocked_findings} blocked, cost #{format_money(day.estimated_cost_cents)}, imports #{day.imports}"
      end) ++
      ["Recommendations:"] ++ Enum.map(trends.recommendations, &"- #{&1}")
  end

  def observability_import_list_lines(imports) do
    [
      "Observability imports: #{imports.count} persisted snapshot(s)",
      "Integrity: #{format_frequency(imports.by_integrity)}",
      "Health: #{format_frequency(imports.by_health)}",
      "Recent imports:"
    ] ++
      Enum.map(imports.recent, fn imported ->
        "- ##{imported.id} #{imported.original_session_title || "unknown"} (session ##{imported.original_session_id || "unknown"}): #{imported.health}, #{imported.problem_groups} problem group(s), integrity #{imported.integrity_status}, hash #{imported.payload_fingerprint || "unknown"}"
      end) ++
      ["Recommendations:"] ++ Enum.map(imports.recommendations, &"- #{&1}")
  end

  def observability_cost_lines(costs) do
    totals = costs.totals

    [
      "Observability costs: #{totals.invocations} invocation(s) across #{totals.sessions} session(s)",
      "Estimated spend: #{format_money(totals.estimated_cost_cents)}",
      "Tokens: #{totals.input_tokens} input / #{totals.cached_input_tokens} cached / #{totals.output_tokens} output",
      "Grouped by: #{costs.by}",
      "Groups:"
    ] ++
      Enum.map(costs.groups, fn group ->
        "- #{group.name}: #{group.invocations} call(s), #{format_money(group.estimated_cost_cents)}, #{group.input_tokens} input, #{group.output_tokens} output"
      end) ++
      ["Recommendations:"] ++ Enum.map(costs.recommendations, &"- #{&1}")
  end

  def observability_recommendation_lines(recommendations) do
    [
      "Observability recommendations: #{recommendations.count} action(s)",
      "Health: #{recommendations.health}",
      "Categories: #{Enum.join(recommendations.categories, ", ")}"
    ] ++
      Enum.flat_map(recommendations.actions, fn action ->
        [
          "",
          "[#{action.priority}] #{action.title}",
          "  Category: #{action.category} | Source: #{action.source}",
          "  Evidence: #{action.evidence}",
          "  Next: #{action.suggested_action}",
          "  Link: #{action.link}",
          "  Human gate required: #{action.human_gate_required}"
        ]
      end)
  end

  def observability_eval_candidate_lines(eval_candidates) do
    [
      "Observability eval candidates: #{eval_candidates.count} candidate(s)",
      "Health: #{eval_candidates.health}",
      "Recommendations:"
    ] ++
      Enum.map(eval_candidates.recommendations, &"- #{&1}") ++
      Enum.flat_map(eval_candidates.candidates, fn candidate ->
        [
          "",
          "[#{candidate.priority}] #{candidate.title}",
          "  Rule: #{candidate.rule_id} | Category: #{candidate.category} | Severity: #{candidate.severity}",
          "  Evidence: #{candidate.evidence_summary}",
          "  Benchmark hint: #{candidate.benchmark_hint}",
          "  Example session: #{candidate.example_session_id || "unknown"}",
          "  Human gate required: #{candidate.human_gate_required}"
        ]
      end)
  end

  def observability_eval_save_lines(result) do
    [
      "Observability eval candidates saved:",
      "Source candidates: #{result.source_count}",
      "Stored: #{result.stored}",
      "Existing: #{result.existing}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.candidates, fn candidate ->
        "- ##{candidate.id} [#{candidate.priority}] #{candidate.title} (#{candidate.status})"
      end)
  end

  def observability_saved_eval_lines(saved) do
    [
      "Saved observability eval candidates: #{saved.count}",
      "Status: #{format_frequency(saved.by_status)}",
      "Priority: #{format_frequency(saved.by_priority)}",
      "Recommendations:"
    ] ++
      Enum.map(saved.recommendations, &"- #{&1}") ++
      ["Candidates:"] ++
      Enum.map(saved.candidates, fn candidate ->
        "- ##{candidate.id} [#{candidate.priority}/#{candidate.status}] #{candidate.title}: #{candidate.evidence_summary}"
      end)
  end

  def observability_benchmark_draft_result_lines(result) do
    [
      "Observability benchmark drafts generated:",
      "Source candidates: #{result.source_count}",
      "Stored: #{result.stored}",
      "Existing: #{result.existing}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.drafts, fn draft ->
        "- ##{draft.id} [#{draft.status}] #{draft.title} (#{draft.suite_slug})"
      end)
  end

  def observability_benchmark_draft_lines(drafts) do
    [
      "Observability benchmark drafts: #{drafts.count}",
      "Status: #{format_frequency(drafts.by_status)}",
      "Suites: #{format_frequency(drafts.by_suite)}",
      "Recommendations:"
    ] ++
      Enum.map(drafts.recommendations, &"- #{&1}") ++
      ["Drafts:"] ++
      Enum.map(drafts.drafts, fn draft ->
        "- ##{draft.id} [#{draft.status}] #{draft.title}: #{draft.expected_behavior}"
      end)
  end

  def benchmark_status_for_command(:obs_benchmark_approve), do: "approved"
  def benchmark_status_for_command(:obs_benchmark_reject), do: "rejected"
  def benchmark_status_for_command(:obs_benchmark_archive), do: "archived"

  def observability_promotion_lines(promotions) do
    [
      "Observability promotion candidates: #{promotions.count}",
      "Promotion execution: #{promotions.promotion_execution}",
      "Readiness: #{format_frequency(promotions.by_readiness)}",
      "Recommendations:"
    ] ++
      Enum.map(promotions.recommendations, &"- #{&1}") ++
      ["Candidates:"] ++
      Enum.map(promotions.candidates, fn candidate ->
        "- ##{candidate.id} #{candidate.rule_id}: #{candidate.readiness} — #{candidate.suggested_action}"
      end)
  end

  def observability_benchmark_history_lines(history) do
    latest = history.latest_run

    [
      "Observability benchmark history:",
      "Readiness: #{history.readiness.status} — #{history.readiness.reason}",
      "Saved eval candidates: #{history.coverage.saved_eval_candidates}",
      "Benchmark drafts: #{history.coverage.benchmark_drafts}",
      "Approved drafts: #{history.coverage.approved_drafts}",
      "Materialized scenarios: #{history.coverage.materialized_scenarios}",
      "Covered scenarios: #{history.coverage.covered_scenarios}",
      "Benchmark runs: #{history.coverage.benchmark_runs}",
      "Latest run: #{if latest, do: "##{latest.id} #{latest.status} catch #{latest.catch_rate}%", else: "none"}",
      "Recommendations:"
    ] ++
      Enum.map(history.recommendations, &"- #{&1}") ++
      ["Recent runs:"] ++
      Enum.map(history.runs, fn run ->
        "- ##{run.id} #{run.suite}: #{run.status}, catch #{run.catch_rate}%, rule-hit #{run.expected_rule_hit_rate}%"
      end)
  end

  def observability_benchmark_dry_run?(options) do
    if Map.has_key?(options, :dry_run),
      do: options[:dry_run] == true,
      else: options[:execute] != true
  end

  def observability_benchmark_run_options(options, workspace_id) do
    [
      workspace_id: workspace_id,
      suite: options[:suite],
      subjects: options[:subjects],
      baseline_subject: options[:baseline_subject],
      scenario_slugs: options[:scenario_slugs],
      dry_run: observability_benchmark_dry_run?(options),
      execute: options[:execute] == true
    ]
  end

  def observability_benchmark_run_lines(%{benchmark_execution: true} = result) do
    [
      "Observability benchmark run ##{result.run_id} completed.",
      "Suite: #{result.suite}",
      "Subjects: #{Enum.join(result.subjects, ", ")}",
      "Status: #{result.status}",
      "Total scenarios: #{result.total_scenarios}",
      "Catch rate: #{result.catch_rate}%",
      "Block rate: #{result.block_rate}%",
      "Expected rule hit rate: #{result.expected_rule_hit_rate}%",
      "Mutation: #{result.mutation}"
    ]
  end

  def observability_benchmark_run_lines(preview) do
    [
      "Observability benchmark run preview:",
      "Suite: #{preview.suite || "choose one"}",
      "Available suites: #{Enum.join(preview.suites, ", ")}",
      "Subjects: #{preview.subjects || "<required>"}",
      "Scenarios: #{Enum.join(preview.scenario_slugs, ", ")}",
      "Executable: #{preview.executable}",
      "Benchmark execution: #{preview.benchmark_execution}",
      "Command: #{preview.command || "materialize scenarios first"}",
      "Recommendations:"
    ] ++ Enum.map(preview.recommendations, &"- #{&1}")
  end

  def observability_benchmark_materialize_lines(result) do
    [
      "Observability benchmark scenarios materialized:",
      "Source drafts: #{result.source_count}",
      "Materialized: #{result.materialized}",
      "Existing: #{result.existing}",
      "Benchmark execution: #{result.benchmark_execution}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.scenarios, fn scenario ->
        "- ##{scenario.id} #{scenario.name} (#{scenario.suite_slug}/#{scenario.slug})"
      end)
  end

  def observability_benchmark_scenario_lines(scenarios) do
    [
      "Observability benchmark scenarios: #{scenarios.count}",
      "Suites: #{format_frequency(scenarios.by_suite)}",
      "Recommendations:"
    ] ++
      Enum.map(scenarios.recommendations, &"- #{&1}") ++
      ["Scenarios:"] ++
      Enum.map(scenarios.scenarios, fn scenario ->
        "- ##{scenario.id} #{scenario.name}: #{Enum.join(scenario.expected_rules, ", ")}"
      end)
  end

  def observability_benchmark_status_lines(result) do
    draft = result.draft

    [
      "Observability benchmark draft updated:",
      "Draft: ##{draft.id} #{draft.title}",
      "Status: #{result.status}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ]
  end

  def observability_regression_lines(regressions) do
    [
      "Observability regressions: #{regressions.health.status}",
      "Window: #{regressions.days} day(s)",
      "Reason: #{regressions.health.reason}",
      "Benchmark runs: #{regressions.benchmark_runs.count}",
      "Average catch rate: #{Float.round(regressions.benchmark_runs.average_catch_rate || 0.0, 3)}",
      "Run status: #{format_frequency(regressions.benchmark_runs.by_status)}",
      "Run suites: #{format_frequency(regressions.benchmark_runs.by_suite)}",
      "Saved eval candidates: #{regressions.draft_coverage.saved_eval_candidates}",
      "Benchmark drafts: #{regressions.draft_coverage.benchmark_drafts}",
      "Recommendations:"
    ] ++
      Enum.map(regressions.recommendations, &"- #{&1}") ++
      ["Recent runs:"] ++
      Enum.map(regressions.benchmark_runs.recent, fn run ->
        "- ##{run.id} #{run.suite} #{run.status}: catch #{Float.round(run.catch_rate || 0.0, 3)} (#{run.caught_count}/#{run.total_scenarios})"
      end)
  end

  def observability_comparison_lines(comparison) do
    [
      "Observability comparison by #{comparison.by}: #{comparison.totals.invocations} invocation(s)",
      "Estimated spend: #{format_money(comparison.totals.estimated_cost_cents)}",
      "Groups:"
    ] ++
      Enum.map(comparison.groups, fn group ->
        "- #{group.name}: #{group.invocations} call(s), #{format_money(group.estimated_cost_cents)}, #{group.cost_per_call_cents} cent(s)/call, #{group.tokens_per_call} token(s)/call, decisions #{inspect(group.decisions)}"
      end) ++
      ["Recommendations:"] ++ Enum.map(comparison.recommendations, &"- #{&1}")
  end

  def render_observability_timeline(session_id, limit, format) do
    case Observability.timeline(session_id, limit: limit) do
      {:ok, timeline} ->
        render_format(format, timeline, &observability_timeline_lines/1)

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  def observability_timeline_lines(timeline) do
    [
      "Observability timeline: #{timeline.session.title} (##{timeline.session.id})",
      "Events: #{timeline.count} recent / limit #{timeline.limit}",
      "Event types: #{format_frequency(timeline.by_event_type)}",
      "Actors: #{format_frequency(timeline.by_actor)}",
      "Timeline:"
    ] ++
      Enum.map(timeline.events, fn event ->
        "- #{event.inserted_at || "unknown time"} #{event.event_type} by #{event.actor}: #{event.summary}"
      end)
  end

  def render_observability_memory(session_id, limit, format) do
    case Observability.memory_context(session_id, limit: limit) do
      {:ok, memory_context} ->
        render_format(format, memory_context, &observability_memory_lines/1)

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  def observability_memory_lines(memory_context) do
    memory = memory_context.memory
    context = memory_context.context

    [
      "Observability memory: #{memory_context.session.title} (##{memory_context.session.id})",
      "Context: #{context.tasks} task(s), #{context.findings} finding(s), #{context.reviews} review(s), #{context.invocations} invocation(s)",
      "Memory: #{memory.active} active / #{memory.archived} archived / #{memory.count} recent",
      "Types: #{format_frequency(memory.by_type)}",
      "Sources: #{format_frequency(memory.by_source)}",
      "Recent memory:"
    ] ++
      Enum.map(memory.recent, fn record ->
        archived = if record.archived, do: "archived", else: "active"
        "- [#{record.record_type}] #{record.title} (#{archived}) — #{record.summary}"
      end) ++
      ["Recommendations:"] ++ Enum.map(memory_context.recommendations, &"- #{&1}")
  end

  def format_frequency(map) when map == %{}, do: "none"

  def format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  def render_observability(session_id, format) do
    case Observability.session_run(session_id) do
      {:ok, run} ->
        render_format(format, run, &observability_lines/1)

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  def observability_lines(run) do
    session = run.session
    health = run.health
    budget = run.budget
    findings = run.findings
    tasks = run.tasks
    gates = run.gates
    timeline = run.timeline
    memory = run.memory
    proofs = run.proofs
    host_metrics = run.hosts_models_tools

    [
      "Observability: #{session.title} (##{session.id})",
      "Health: #{health.status} — #{health.label}",
      "Reasons: #{Enum.join(health.reasons, "; ")}",
      "Budget: #{format_money(budget["spent_cents"] || 0)} / #{format_money(budget["session_budget_cents"] || 0)} used (#{budget["decision"] || "unknown"})",
      "Findings: #{findings.active} active / #{findings.total} total (#{findings.critical} critical, #{findings.high} high, #{findings.blocked} blocked)",
      "Tasks: #{tasks.active} active / #{tasks.total} total",
      "Gates: #{gates.pending_reviews} pending review(s) / #{gates.total_reviews} total",
      "Timeline: #{timeline.count} recent event(s)",
      "Memory: #{memory.records} active record(s)",
      "Proof bundles: #{proofs.count}",
      "Invocations: #{host_metrics.invocations} call(s), #{format_money(host_metrics.estimated_cost_cents)} estimated",
      "Recommendations:"
    ] ++ Enum.map(run.recommendations, &"- #{&1}")
  end

  def proofs_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("task_id", options[:task_id])
      |> maybe_add_filter("deploy_ready", options[:deploy_ready])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  def benchmark_filter_summary(options) do
    case options[:domain_pack] do
      nil -> ""
      "" -> ""
      domain_pack -> " (domain_pack=#{domain_pack})"
    end
  end

  def maybe_add_filter(filters, _label, nil), do: filters
  def maybe_add_filter(filters, _label, ""), do: filters
  def maybe_add_filter(filters, label, value), do: filters ++ ["#{label}=#{value}"]

  def current_session_task(session) do
    Enum.find(session.tasks, &(&1.status == "in_progress")) ||
      Enum.find(session.tasks, &(&1.status == "queued")) ||
      List.first(session.tasks)
  end

  def current_task_payload(nil), do: nil

  def current_task_payload(task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "status" => task.status
    }
  end

  def proofs_help_lines(proofs, options) do
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

  def progress_help_lines(progress, current_task) do
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

  def benchmark_list_help_lines(suites, runs, subjects) do
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

  def benchmark_show_help_lines(run) do
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

  def session_workspace_context(session, project_root) do
    session
    |> WorkspaceContext.resolve_project_root(project_root)
    |> case do
      nil -> Root.resolve(project_root)
      resolved -> resolved
    end
    |> WorkspaceContext.build()
  end

  def augmentation_status_line(%{"available" => true} = augmentation) do
    likely_paths = augmentation["likely_paths"] |> List.wrap() |> Enum.take(3)
    search_terms = augmentation["search_terms"] |> List.wrap() |> Enum.take(3)

    summary =
      [
        truncate_cli(augmentation["objective"], 90),
        list_hint("paths", likely_paths),
        list_hint("terms", search_terms)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")

    if summary == "", do: "available", else: summary
  end

  def augmentation_status_line(_augmentation), do: "not available yet"

  def security_case_status_line(%{"case_count" => 0}), do: "0 tracked"

  def security_case_status_line(%{"case_count" => case_count} = summary) do
    unresolved = summary["unresolved"] || 0
    critical = summary["critical_unresolved"] || 0

    "#{case_count} tracked | #{unresolved} unresolved | #{critical} critical unresolved"
  end

  def security_case_status_line(_summary), do: "not recorded"

  def list_hint(_label, []), do: nil
  def list_hint(label, values), do: "#{label}: #{Enum.join(values, ", ")}"

  def truncate_cli(nil, _limit), do: nil

  def truncate_cli(text, limit) when is_binary(text) and byte_size(text) > limit do
    "#{binary_part(text, 0, limit)}... (#{byte_size(text)} chars)"
  end

  def truncate_cli(text, _limit), do: text

  def attached_agent_status_payload(binding) do
    binding
    |> Map.get("attached_agents", %{})
    |> Enum.sort_by(fn {agent, _attrs} -> agent end)
    |> Enum.map(fn {agent, attrs} ->
      %{
        "agent" => agent,
        "controlkeel_version" => attrs["controlkeel_version"] || "unknown"
      }
    end)
  end

  def help_lines_to_values(lines) do
    lines
    |> Enum.reject(&(&1 == "Suggested next steps:" or &1 == ""))
    |> Enum.map(&String.trim/1)
  end

  def maybe_add_help_line(lines, true, line), do: lines ++ [line]
  def maybe_add_help_line(lines, false, _line), do: lines
  def maybe_add_help_line(lines, nil), do: lines
  def maybe_add_help_line(lines, line) when is_binary(line), do: lines ++ [line]

  def maybe_task_proof_hint(%{id: id}), do: "Next: controlkeel proofs --task-id #{id}"
  def maybe_task_proof_hint(_task), do: nil

  def agent_execution_lines(result) do
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

  def format_cli_error({:invalid_arguments, reason}), do: reason
  def format_cli_error({:policy_blocked, reason}), do: reason
  def format_cli_error(:not_found), do: "not found"
  def format_cli_error(:invalid_id), do: "invalid id"

  def format_cli_error({:review_denied, review}),
    do: "Plan review was denied." <> format_review_feedback_error(review)

  def format_cli_error({:review_pending, details}),
    do:
      "Task is waiting on plan approval (review ##{details[:review_id] || "unknown"}, status #{details[:review_status] || "pending"})."

  def format_cli_error({:execution_not_ready, details}),
    do:
      "Plan is approved (review ##{details[:review_id] || "unknown"}) but execution is not ready. Refine the plan to reach execution-ready phase, or approve a deeper plan phase."

  def format_cli_error({:timeout, review}),
    do: "Timed out waiting for plan review ##{review.id}." <> format_review_feedback_error(review)

  def format_cli_error(reason), do: inspect(reason)

  def review_url(review_id), do: Endpoint.url() <> "/reviews/#{review_id}"

  def manual_approval_lines(review, %{server_serving: false}) do
    [
      "Manual approval fallback: review server is not reachable from this CLI session.",
      "Approve from CLI after explicit human approval: controlkeel review plan respond --id #{review.id} --decision approved --feedback-notes \"User approved in chat; review server unavailable\""
    ]
  end

  def manual_approval_lines(_review, %{opened: false}) do
    [
      "Manual approval fallback: browser did not open automatically; ask for explicit approval in chat or open the URL manually."
    ]
  end

  def manual_approval_lines(_review, _review_open), do: []

  def review_feedback_lines(%{feedback_notes: notes}) when is_binary(notes) and notes != "",
    do: ["Feedback: #{notes}"]

  def review_feedback_lines(_review), do: []

  def format_review_feedback_error(%{feedback_notes: notes})
      when is_binary(notes) and notes != "" do
    " Feedback: #{notes}"
  end

  def format_review_feedback_error(_review), do: ""

  def review_runtime_context_from_env do
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

  def review_cli_payload(review, extra) do
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

  def maybe_put_agent_feedback(payload, %{status: "denied"} = review) do
    Map.put(payload, "agent_feedback", ReviewBridge.agent_feedback(review))
  end

  def maybe_put_agent_feedback(payload, _review), do: payload

  def cli_error(prefix, reason, options, extra_payload \\ %{}) do
    message = "#{prefix}: #{format_cli_error(reason)}"

    if options[:json] do
      {:error, Jason.encode!(Map.merge(%{"error" => message}, extra_payload))}
    else
      {:error, message}
    end
  end

  def review_lines(review, recommendation_label) do
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

  def release_ready_lines(readiness) do
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

  def binding_session_id(project_root) do
    case Binding.read_effective(project_root) do
      {:ok, binding, _mode} -> binding["session_id"]
      _ -> nil
    end
  end

  def github_metadata_from_env do
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

  def standalone_wrapper_runtime? do
    System.get_env("__BURRITO") not in [nil, ""]
  end

  def plain_arguments do
    plain_arguments_provider().()
    |> Enum.map(&to_string/1)
  end

  def plain_arguments_provider do
    Application.get_env(:controlkeel, :cli_plain_arguments_provider, &:init.get_plain_arguments/0)
  end

  def parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  def require_integer_option(nil, option), do: {:error, {:missing_option, option}}
  def require_integer_option(value, _option) when is_integer(value), do: {:ok, value}

  def require_integer_option(value, _option) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  def require_string_option(nil, option), do: {:error, {:missing_option, option}}
  def require_string_option("", option), do: {:error, {:missing_option, option}}
  def require_string_option(value, _option), do: {:ok, to_string(value)}

  def parse_telemetry_level(value) do
    case ControlKeel.Cloud.Telemetry.Config.parse_level(value) do
      {:ok, :disabled} -> {:error, :invalid_level}
      {:ok, level} -> {:ok, level}
      :error -> {:error, :invalid_level}
    end
  end

  def maybe_render_compliance_template(bundle, nil), do: {:ok, bundle}
  def maybe_render_compliance_template(bundle, ""), do: {:ok, bundle}

  def maybe_render_compliance_template(bundle, template) do
    ControlKeel.Cloud.ComplianceTemplate.render(bundle, template)
  end

  def maybe_sign_audit_export(payload, %{sign: true} = options) do
    case options[:signing_key_env] do
      nil ->
        {:error, :missing_signing_key_env}

      "" ->
        {:error, :missing_signing_key_env}

      env ->
        case System.get_env(env) do
          nil -> {:error, {:missing_signing_key, env}}
          "" -> {:error, {:missing_signing_key, env}}
          key -> {:ok, ControlKeel.Cloud.Audit.ExportSigner.sign(payload, key, key_id: env)}
        end
    end
  end

  def maybe_sign_audit_export(payload, _options), do: {:ok, payload}

  def baseline_tool_count(baseline) do
    baseline
    |> ControlKeel.Cloud.Workspace.Baseline.decode()
    |> map_size()
  end

  def format_repo_error(nil), do: ""
  def format_repo_error(msg), do: " — " <> msg

  def format_value_hint(nil), do: ""
  def format_value_hint(hint), do: " " <> hint

  def resolve_audit_scope(options) do
    workspace_slug = options[:workspace]
    org_slug = options[:org]

    cond do
      workspace_slug && org_slug ->
        {:error, :scope_conflict}

      workspace_slug ->
        case ControlKeel.Repo.get_by(ControlKeel.Mission.Workspace, slug: workspace_slug) do
          nil -> {:error, :unknown_workspace}
          ws -> {:ok, [workspace_id: ws.id]}
        end

      org_slug ->
        case ControlKeel.Accounts.get_org_by_slug(org_slug) do
          nil -> {:error, :unknown_org}
          org -> {:ok, [org_id: org.id]}
        end

      true ->
        {:error, :scope_required}
    end
  end

  def parse_optional_datetime(nil, _name), do: {:ok, nil}
  def parse_optional_datetime("", _name), do: {:ok, nil}

  def parse_optional_datetime(value, name) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> {:error, {:invalid_datetime, name}}
    end
  end

  def maybe_append(opts, _key, nil), do: opts
  def maybe_append(opts, key, value), do: Keyword.put(opts, key, value)

  def parse_integer_arg(value, name) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "Invalid #{name}: #{value}"}
    end
  end

  def validate_runtime_target(runtime) do
    if runtime in ControlKeel.Cloud.RunPackage.valid_runtimes() do
      :ok
    else
      {:error,
       "Unknown runtime '#{runtime}'. Valid runtimes: " <>
         Enum.join(ControlKeel.Cloud.RunPackage.valid_runtimes(), ", ")}
    end
  end

  def validate_budget_cents(nil), do: {:ok, 0}
  def validate_budget_cents(n) when is_integer(n) and n >= 0, do: {:ok, n}
  def validate_budget_cents(_), do: {:error, "--budget-cents must be a non-negative integer"}

  def parse_scopes(nil), do: nil
  def parse_scopes(""), do: nil
  def parse_scopes(value) when is_binary(value), do: value

  def build_cloud_payload(task, options) do
    base = %{
      "task_title" => task.title,
      "validation_gate" => task.validation_gate,
      "note" => options[:note]
    }

    base = Enum.reject(base, fn {_k, v} -> v in [nil, ""] end) |> Map.new()

    case cloud_github_bindings(task) do
      [] -> base
      bindings -> Map.put(base, "github_repos", bindings)
    end
  end

  def cloud_github_bindings(task) do
    alias ControlKeel.Mission

    case Mission.get_session(task.session_id) do
      %{workspace_id: ws_id} when is_integer(ws_id) ->
        ws_id
        |> Mission.list_github_repos()
        |> Enum.map(fn b ->
          %{
            "owner" => b.owner,
            "repo" => b.repo,
            "default_branch" => b.default_branch,
            "installation_id" => b.installation_id,
            "url" => "https://github.com/#{b.owner}/#{b.repo}"
          }
          |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
          |> Map.new()
        end)

      _ ->
        []
    end
  end

  @doc false
  # Capture git remote/branch/commit_sha for the cloud handoff.
  #
  # Explicit CLI overrides win. Otherwise we shell out to git in the given
  # project_root. Missing or non-git roots return nil for each field — the
  # cloud server treats nil as "no provable revision" and the operator can
  # decide whether to accept that for their runtime.
  def capture_git_metadata(project_root, options) do
    %{
      repo_url: options[:repo_url] || detect_git_remote(project_root),
      branch: options[:branch] || detect_git_branch(project_root),
      commit_sha: options[:commit_sha] || detect_git_commit_sha(project_root)
    }
  end

  def detect_git_remote(nil), do: nil

  def detect_git_remote(project_root) do
    case System.cmd("git", ["remote", "get-url", "origin"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {url, 0} -> String.trim(url)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def detect_git_branch(nil), do: nil

  def detect_git_branch(project_root) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {branch, 0} ->
        case String.trim(branch) do
          "" -> nil
          "HEAD" -> nil
          name -> name
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def detect_git_commit_sha(nil), do: nil

  def detect_git_commit_sha(project_root) do
    case System.cmd("git", ["rev-parse", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {sha, 0} ->
        case String.trim(sha) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join("; ")
  end

  def format_changeset_errors(other), do: inspect(other)

  def format_url(nil), do: ""
  def format_url(url), do: "  url=#{url}"

  def format_note(nil), do: ""
  def format_note(""), do: ""
  def format_note(note), do: "  note=#{note}"

  def telemetry_level_list_text do
    ControlKeel.Cloud.Telemetry.Config.opt_in_levels()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(" | ")
  end

  def selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  def selected_base_url(_status), do: "default"

  def ensure_attach_project(project_root, overrides) do
    ensure_local_project(project_root, overrides, sync_attached_agents: false)
  end

  def ensure_local_project(project_root, overrides \\ %{}, opts \\ []) do
    project_root = Root.resolve(project_root)
    sync_attached_agents? = Keyword.get(opts, :sync_attached_agents, true)

    with {:ok, binding, session, mode} <-
           Local.load_or_bootstrap(project_root, overrides, ephemeral_ok: true) do
      if sync_attached_agents? do
        case AttachedSync.sync(binding, project_root, mode: mode) do
          {:ok, synced_binding, _changes} -> {:ok, synced_binding, session, mode}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, binding, session, mode}
      end
    end
  end

  def binding_write_mode(binding) do
    case get_in(binding, ["bootstrap", "mode"]) do
      "ephemeral" -> :ephemeral
      _ -> :project
    end
  end

  def bootstrap_lines(project_root) do
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

  def load_rules_payload(nil), do: {:ok, []}

  def load_rules_payload(path) do
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

  def format_percent(nil), do: "Not recorded"
  def format_percent(value) when is_integer(value), do: "#{value}%"
  def format_percent(value), do: "#{Float.round(value, 1)}%"

  def format_ms(nil), do: "Not recorded"
  def format_ms(value), do: "#{value}ms"

  def format_provider_bridge(%{supported: true, provider: provider, mode: mode}),
    do: "#{mode}: #{provider}"

  def format_provider_bridge(%{supported: true, mode: mode}), do: mode
  def format_provider_bridge(%{mode: "ck_owned"}), do: "ck-owned"
  def format_provider_bridge(%{mode: "none"}), do: "none"
  def format_provider_bridge(_bridge), do: "none"

  def emit_attach_succeeded(binding, project_root, attached_agent) do
    root = Path.expand(project_root)

    if is_integer(binding["session_id"]) do
      _ = Mission.attach_session_runtime_context(binding["session_id"], %{"project_root" => root})

      _ =
        ControlKeel.Mission.SessionTranscript.record(%{
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

  def attach_guidance_lines(agent) do
    case Integration.get(agent) do
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
          "Auth owner: #{Integration.auth_owner(integration)}.",
          "MCP mode: #{integration.mcp_mode}.",
          "Skills mode: #{integration.skills_mode}.",
          "Provider bridge: #{format_provider_bridge(integration.provider_bridge)}.",
          "Core loop: #{SetupAdvisor.core_loop()}.",
          "Next: controlkeel status.",
          integration.upstream_docs_url && "Upstream docs: #{integration.upstream_docs_url}"
        ]
        |> Enum.reject(&is_nil/1)
        |> Kernel.++(cloud_guidance_lines())
        |> Kernel.++(Distribution.current_install_lines())
    end
  end

  def cloud_guidance_lines do
    case ControlKeel.Cloud.Workspace.Identity.load() do
      {:ok, identity} ->
        [
          "",
          "Cloud — already connected (workspace #{identity.workspace_id}).",
          "  controlkeel cloud doctor              # verify the cloud-mode boundary",
          "  controlkeel telemetry status          # check sync state and queue depth"
        ]

      _ ->
        [
          "",
          "Cloud — optional next step (sync findings, proofs, and approvals across a team):",
          "  controlkeel cloud connect --enroll https://controlkeel.com",
          "  # or your self-host URL, e.g. https://govern.acme.com (see docs/self-hosting.md)",
          "  controlkeel cloud doctor              # verify the cloud-mode boundary"
        ]
    end
  end

  def resolve_project_root(options, project_root) do
    options[:project_root] ||
      project_root
      |> Root.resolve()
  end

  def maybe_line(nil, _prefix), do: []
  def maybe_line(line, prefix), do: ["#{prefix}#{line}"]

  def native_attach_lines("claude-code", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("claude-standalone", project_root,
             scope: attach_scope("claude-code", options)
           ) do
        {:ok, %{destination: destination, agent_destination: agent_destination} = result} ->
          settings_line =
            case Map.get(result, :settings_destination) do
              nil -> []
              path -> ["Installed Claude hooks at #{path}."]
            end

          instructions_line =
            case Map.get(result, :instructions_destination) do
              nil -> []
              false -> []
              path -> ["Installed CLAUDE.md at #{path}."]
            end

          [
            "Installed Claude native skills at #{destination}.",
            "Installed Claude companion agent at #{agent_destination}."
          ] ++ settings_line ++ instructions_line

        {:error, reason} ->
          ["Native Claude skills were not installed: #{inspect(reason)}"]
      end
    end
  end

  def native_attach_lines("cline", project_root, options) do
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

  def native_attach_lines("goose", project_root, options) do
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

  def native_attach_lines(agent, project_root, options)
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

  def native_attach_lines(_agent, _project_root, _options), do: []

  def native_attach_skipped?(options) when is_list(options) do
    Keyword.get(options, :mcp_only, false) or Keyword.get(options, :no_native, false)
  end

  def native_attach_skipped?(options) when is_map(options) do
    Map.get(options, "mcp_only", false) or Map.get(options, "no_native", false) or
      Map.get(options, :mcp_only, false) or Map.get(options, :no_native, false)
  end

  def native_attach_skipped?(_), do: false

  def maybe_install_codex_native(project_root, scope, options) do
    if native_attach_skipped?(options) do
      {:ok, nil}
    else
      Skills.install("codex", project_root, scope: scope)
    end
  end

  def codex_attach_install_lines(nil), do: []

  def codex_attach_install_lines(install_result) do
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

  def attach_scope(agent, options) do
    options[:scope] ||
      case Integration.get(agent) do
        %Integration{default_scope: scope} when is_binary(scope) -> scope
        _ -> "project"
      end
  end

  def validate_attach_scope(agent, options) do
    scope = attach_scope(agent, options)

    case Integration.get(agent) do
      %Integration{supported_scopes: scopes, label: label}
      when is_list(scopes) and scopes != [] ->
        if scope in scopes do
          {:ok, scope}
        else
          {:error,
           "Unsupported scope `#{scope}` for #{label}. Supported scopes: #{Enum.join(scopes, ", ")}."}
        end

      _ ->
        {:ok, scope}
    end
  end

  def display_attach_agent(agent), do: Integration.label(agent)

  # ─── IDE MCP attachment helpers ──────────────────────────────────────────────

  def attach_to_cursor(command_spec) do
    config_path = cursor_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "cursor")
  end

  def attach_to_windsurf(command_spec) do
    config_path = windsurf_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "windsurf")
  end

  def cursor_mcp_config_path do
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

  def windsurf_mcp_config_path do
    home = user_home()
    Path.join([home, ".codeium", "windsurf", "mcp_config.json"])
  end

  def write_ide_mcp_config(config_path, server_name, command_spec, ide_key) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing = read_json_map(config_path)

    updated =
      if ide_key in ["opencode", "kilo"] do
        mcp = Map.get(existing, "mcp", %{})

        entry = %{
          "type" => "local",
          "command" => [command | args],
          "enabled" => true
        }

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

  def read_json_map(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{} = decoded} -> decoded
          _ -> %{}
        end

      _ ->
        %{}
    end || %{}
  end

  def ensure_stdio_server_running(timeout_ms) do
    case wait_for_stdio_server(timeout_ms) do
      pid when is_pid(pid) ->
        pid

      nil ->
        _ = maybe_start_stdio_server_child()
        wait_for_stdio_server(timeout_ms)
    end
  end

  def maybe_start_stdio_server_child do
    opts = [
      name: ControlKeel.MCP.Server.stdio_registered_name(),
      input: :stdio,
      output: :stdio
    ]

    case Process.whereis(ControlKeel.Supervisor) do
      pid when is_pid(pid) ->
        child = {ControlKeel.MCP.Server, opts}

        case Supervisor.start_child(ControlKeel.Supervisor, child) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          :ignore -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :error
        end

      nil ->
        case ControlKeel.MCP.Server.start_link(opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :error
        end
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  def wait_for_stdio_server(timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_stdio_server_until(deadline)
  end

  def wait_for_stdio_server_until(deadline_ms) do
    case Process.whereis(ControlKeel.MCP.Server.stdio_registered_name()) do
      pid when is_pid(pid) ->
        pid

      nil ->
        if System.monotonic_time(:millisecond) < deadline_ms do
          Process.sleep(25)
          wait_for_stdio_server_until(deadline_ms)
        else
          nil
        end
    end
  end

  # ── Additional IDE MCP config paths ──────────────────────────────────────────

  def kiro_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, ".kiro", "settings", "mcp.json"])

      _ ->
        Path.join([home, ".kiro", "settings", "mcp.json"])
    end
  end

  def kilo_config_path do
    Path.join([user_home(), ".config", "kilo", "kilo.json"])
  end

  def amp_mcp_config_path do
    Path.join([user_home(), ".config", "amp", "mcp.json"])
  end

  def augment_mcp_config_path do
    Path.join([user_home(), ".augment", "settings.json"])
  end

  def opencode_mcp_config_path do
    Path.join([user_home(), ".config", "opencode", "opencode.json"])
  end

  def gemini_cli_config_path do
    Path.join([user_home(), ".gemini", "settings.json"])
  end

  def cline_mcp_config_path do
    base = System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
    Path.join([base, "data", "settings", "cline_mcp_settings.json"])
  end

  def continue_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, "Roaming", "Continue", "config.json"])

      _ ->
        Path.join([home, ".continue", "config.json"])
    end
  end

  # Continue uses an array-based mcpServers format, unlike Cursor/Windsurf dict format
  def write_continue_mcp_config(config_path, server_name, command_spec) do
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
  def attach_to_aider(command_spec, project_root) do
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

  def goose_config_path do
    Path.join([user_home(), ".config", "goose", "config.yaml"])
  end

  def attach_to_goose(command_spec, project_root) do
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
         :ok <- File.write(config_path, UtilsYaml.document(updated)) do
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

  def read_yaml_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  def normalize_yaml_map(value) when is_map(value), do: value
  def normalize_yaml_map(_value), do: %{}

  def auto_attach_claude_code(project_root) do
    claude_dir = Path.join(user_home(), ".claude")
    command_spec = Binding.mcp_command_spec(project_root)

    cond do
      not File.dir?(claude_dir) ->
        {:skip, "claude-code not found on this system"}

      true ->
        case Claude.attach_local(project_root, command_spec.command, command_spec.args) do
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

  def benchmark_filter_opts(nil), do: []
  def benchmark_filter_opts(""), do: []
  def benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  def format_domain_packs(packs) when is_binary(packs), do: format_domain_packs([packs])

  def format_domain_packs(packs) when is_list(packs) do
    packs
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&Intent.pack_label/1)
    |> Enum.join(", ")
  end

  def format_money(nil), do: "unlimited"
  def format_money(cents), do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()
  def format_duration(nil), do: "not recorded"
  def format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  def format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  def format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  def user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  def github_repo_attached_agent(agent, scope, %{destination: destination}) do
    %{
      "target" => "github-repo",
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  def github_repo_attached_agent(agent, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => plan.target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  def attach_bundle_target(target, project_root, scope, options) do
    if native_attach_skipped?(options) do
      Skills.export(target, project_root, scope: "export")
    else
      Skills.install(target, project_root, scope: scope)
    end
  end

  def bundled_attached_agent(agent, target, scope, %{destination: destination} = result) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "config_destination" => Map.get(result, :agent_destination),
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  def bundled_attached_agent(agent, target, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  def bundle_attach_lines(agent, %{destination: destination} = result) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Installed bundle at #{destination}."
    ] ++
      if(Map.has_key?(result, :agent_destination),
        do: ["Config destination: #{result.agent_destination}."],
        else: []
      )
  end

  def bundle_attach_lines(agent, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Output: #{plan.output_dir}"
    ]
  end

  def maybe_attach_line(_label, nil), do: []
  def maybe_attach_line(label, path), do: ["#{label} at #{path}."]
end
