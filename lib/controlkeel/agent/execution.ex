defmodule ControlKeel.Agent.Execution do
  @moduledoc false

  require Logger

  alias ControlKeel.Agent.Integration
  alias ControlKeel.Agent.Router
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Intent
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Project.Root
  alias ControlKeel.Project.Binding
  alias ControlKeel.Mcp.ProtocolAccess
  alias ControlKeel.Governance.SecurityWorkflow
  alias ControlKeel.Mission.SessionTranscript
  alias ControlKeel.Skills

  @direct_executable_candidates %{
    "claude-code" => ["claude"],
    "claude-dispatch" => ["claude"],
    "codex-cli" => ["codex", "codex-cli"],
    "codex-app-server" => ["codex", "codex-cli"],
    "t3code" => ["t3", "t3code", "codex", "codex-cli"],
    "copilot" => ["copilot"],
    "copilot-cli" => ["copilot"],
    "cline" => ["cline"],
    "continue" => ["continue"],
    "opencode" => ["opencode"]
  }

  def list_agents(project_root \\ File.cwd!()) do
    project_root = Root.resolve(project_root)
    attached = attached_agent_ids(project_root)

    Skills.agent_integrations()
    |> Enum.map(fn integration ->
      executable_path = executable_path(integration.id)
      configured_command = configured_command(integration.id)

      %{
        id: integration.id,
        label: integration.label,
        support_class: integration.support_class,
        preferred_target: integration.preferred_target,
        agent_uses_ck_via: integration.agent_uses_ck_via || [],
        ck_runs_agent_via: integration.ck_runs_agent_via,
        execution_support: integration.execution_support,
        autonomy_mode: integration.autonomy_mode,
        attached: integration.id in attached,
        direct_command_configured: configured_command != nil,
        executable_path: executable_path,
        runnable:
          runnable?(
            integration.execution_support,
            configured_command,
            executable_path,
            integration
          ),
        requires_human_intervention:
          integration.execution_support in ["handoff", "runtime", "inbound_only"]
      }
    end)
  end

  def doctor(project_root \\ File.cwd!()) do
    project_root = Root.resolve(project_root)
    attached = attached_agent_ids(project_root)
    agents = list_agents(project_root)

    %{
      "project_root" => Path.expand(project_root),
      "attached_agents" => attached,
      "agents" => agents,
      "direct_ready" => Enum.filter(agents, &(&1.execution_support == "direct" and &1.runnable)),
      "handoff_ready" => Enum.filter(agents, &(&1.execution_support == "handoff")),
      "runtime_ready" => Enum.filter(agents, &(&1.execution_support == "runtime")),
      "execution_sandbox" => ExecutionSandbox.supported_adapters()
    }
  end

  def run_task(task_id, opts \\ []) do
    project_root = Path.expand(Keyword.get(opts, :project_root, File.cwd!()))
    sandbox = Keyword.get(opts, :sandbox)
    if sandbox, do: Process.put(:ck_execution_sandbox, sandbox)

    result =
      with %{} = task <- Mission.get_task(task_id),
           :ok <- ensure_review_gate(task),
           %{} = session <- Mission.get_session_context(task.session_id),
           {:ok, integration} <- resolve_integration(task, project_root, opts),
           {:ok, execution_mode} <- resolve_execution_mode(integration, opts),
           :ok <-
             attach_runtime_contexts(task, session, integration, execution_mode, project_root),
           {:ok, package_root} <-
             prepare_run_package(project_root, session, task, integration, execution_mode),
           :ok <- record_delegate_prepared(task, integration, execution_mode, package_root),
           {:ok, service_account_context} <- maybe_create_service_account(session, execution_mode),
           {:ok, service_account_context} <-
             prepare_support_assets(
               package_root,
               project_root,
               integration,
               execution_mode,
               service_account_context
             ),
           claim_metadata <-
             base_run_metadata(integration, execution_mode, package_root, service_account_context),
           {:ok, _task_run} <-
             Platform.claim_task(task.id, service_account_context[:service_account], %{
               execution_mode: task_run_execution_mode(execution_mode),
               metadata: claim_metadata
             }),
           :ok <-
             maybe_policy_gate(
               task,
               session,
               service_account_context[:service_account],
               claim_metadata
             ) do
        dispatch_run(
          task,
          session,
          integration,
          execution_mode,
          package_root,
          service_account_context
        )
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    Process.delete(:ck_execution_sandbox)
    result
  end

  def run_session(session_id, opts \\ []) do
    project_root = Path.expand(Keyword.get(opts, :project_root, File.cwd!()))

    with %{} = session <- Mission.get_session_context(session_id),
         {:ok, _graph} <- Platform.execute_session(session_id) do
      tasks =
        session_id
        |> Mission.get_session_context()
        |> Map.get(:tasks, [])
        |> Enum.filter(&(&1.status in ["ready", "queued"]))
        |> Enum.sort_by(& &1.position)

      # Accumulate {result_ref => package_root} as tasks complete so
      # downstream aggregate tasks can reference prior outputs.
      {results, _ref_map} =
        Enum.reduce(tasks, {[], %{}}, fn task, {acc, ref_map} ->
          task = maybe_inject_input_refs(task, ref_map)

          result =
            case run_task(task.id, Keyword.put(opts, :project_root, project_root)) do
              {:ok, r} ->
                r

              {:error, reason} ->
                %{"task_id" => task.id, "status" => "failed", "error" => inspect(reason)}
            end

          new_ref_map = maybe_persist_output_ref(task, result, ref_map)
          {acc ++ [result], new_ref_map}
        end)

      {:ok,
       %{
         "session_id" => session.id,
         "project_root" => project_root,
         "task_count" => length(tasks),
         "results" => results
       }}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  # If this task is an aggregate (or already has input_refs), stamp all
  # accumulated refs into its input_refs and metadata before execution so
  # task.json contains the full ref map the agent needs.
  defp maybe_inject_input_refs(task, ref_map) when map_size(ref_map) == 0, do: task

  defp maybe_inject_input_refs(%{metadata: meta} = task, ref_map) do
    is_aggregate = Map.get(meta || %{}, "aggregate_task") == true
    has_refs = task.input_refs != []

    if is_aggregate or has_refs do
      new_refs = Map.keys(ref_map) |> Enum.sort()
      new_meta = Map.put(meta || %{}, "input_ref_map", ref_map)

      case Mission.update_task(task, %{input_refs: new_refs, metadata: new_meta}) do
        {:ok, updated} -> updated
        _ -> task
      end
    else
      task
    end
  end

  # After an embedded run completes, persist output_ref and accumulate the
  # ref → package_root mapping for downstream tasks.
  defp maybe_persist_output_ref(task, %{"result_ref" => ref, "package_root" => pkg}, ref_map)
       when is_binary(ref) do
    _ = Mission.update_task(task, %{output_ref: ref})
    Map.put(ref_map, ref, pkg)
  end

  defp maybe_persist_output_ref(_task, _result, ref_map), do: ref_map

  def delegate(arguments, project_root \\ File.cwd!()) when is_map(arguments) do
    opts =
      []
      |> maybe_put_opt(:project_root, project_root)
      |> maybe_put_opt(:agent, Map.get(arguments, "agent"))
      |> maybe_put_opt(:mode, Map.get(arguments, "mode"))

    cond do
      Map.has_key?(arguments, "task_id") ->
        arguments
        |> Map.get("task_id")
        |> Arguments.normalize_integer("task_id")
        |> case do
          {:ok, task_id} -> run_task(task_id, opts)
          {:error, _reason} = error -> error
        end

      Map.has_key?(arguments, "session_id") ->
        arguments
        |> Map.get("session_id")
        |> Arguments.normalize_integer("session_id")
        |> case do
          {:ok, session_id} -> run_session(session_id, opts)
          {:error, _reason} = error -> error
        end

      true ->
        {:error, {:invalid_arguments, "task_id or session_id is required"}}
    end
  end

  defp resolve_integration(task, project_root, opts) do
    requested =
      opts
      |> Keyword.get(:agent)
      |> normalize_requested_agent()

    integration =
      cond do
        is_binary(requested) ->
          Integration.canonical(requested)

        true ->
          resolve_auto_integration(task, project_root)
      end

    case integration do
      %Integration{} = found -> {:ok, found}
      _ -> {:error, :unknown_agent}
    end
  end

  defp resolve_auto_integration(task, project_root) do
    with {:ok, binding, _mode} <- Binding.read_effective(project_root),
         attached when is_map(attached) <- Map.get(binding, "attached_agents", %{}),
         {agent_id, _attrs} <- Enum.at(attached, 0),
         %Integration{} = integration <- Integration.canonical(agent_id) do
      integration
    else
      _ ->
        case Router.route(task.title, []) do
          {:ok, %{agent: agent_id}} -> Integration.canonical(agent_id)
          _ -> Integration.canonical("claude-code")
        end
    end
  end

  defp resolve_execution_mode(%Integration{} = integration, opts) do
    case normalize_requested_mode(Keyword.get(opts, :mode)) do
      "auto" ->
        case integration.execution_support do
          "direct" ->
            if direct_command_available?(integration.id) do
              {:ok, "embedded"}
            else
              {:ok, "handoff"}
            end

          "handoff" ->
            {:ok, "handoff"}

          "runtime" ->
            {:ok, "runtime"}

          _ ->
            {:error, :unsupported_execution_mode}
        end

      "embedded" ->
        if integration.execution_support == "direct" do
          {:ok, "embedded"}
        else
          {:error, :unsupported_execution_mode}
        end

      "handoff" ->
        {:ok, "handoff"}

      "runtime" ->
        {:ok, "runtime"}
    end
  end

  defp ensure_review_gate(%{id: task_id} = task) do
    if Mission.execution_ready?(task) do
      :ok
    else
      review = Mission.latest_review_for_task(task_id, "plan")

      # Distinguish between a genuinely pending review and a plan that isn't
      # execution-ready despite having an approved review.  Previously this
      # branch always returned :review_pending, which produced confusing
      # error messages like "review_pending, status: approved".
      error_type =
        case review && review.status do
          "approved" -> :execution_not_ready
          _ -> :review_pending
        end

      {:error,
       {error_type,
        %{
          task_id: task_id,
          review_id: review && review.id,
          review_status: review && review.status
        }}}
    end
  end

  defp maybe_policy_gate(task, session, service_account, claim_metadata) do
    case security_policy_gate_reason(task, session, claim_metadata) || policy_gate_reason(session) do
      nil ->
        :ok

      reason ->
        _ =
          Platform.record_task_checks(task.id, service_account, [
            %{
              check_type: "policy_gate",
              status: "blocked",
              summary: reason,
              payload: %{"reason" => reason},
              metadata: %{"autonomy_mode" => "policy_gated"}
            }
          ])

        case Platform.report_task(task.id, service_account, %{
               status: "blocked",
               output: %{},
               metadata:
                 Map.merge(claim_metadata, %{
                   "policy_gate" => "blocked",
                   "policy_gate_reason" => reason
                 })
             }) do
          {:ok, _run} ->
            _ =
              SessionTranscript.record(%{
                session_id: session.id,
                task_id: task.id,
                event_type: "delegate.blocked",
                actor: "controlkeel",
                summary: "Delegated execution was blocked by policy.",
                body: reason,
                payload: %{"reason" => reason}
              })

            {:error, {:policy_blocked, reason}}

          {:error, :proof_not_ready, detail} ->
            {:error, {:proof_not_ready, detail}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp security_policy_gate_reason(task, session, claim_metadata) do
    if SecurityWorkflow.security_domain?(session) and
         SecurityWorkflow.task_requires_verified_research?(task) do
      access_mode = SecurityWorkflow.session_cyber_access_mode(session)

      cond do
        access_mode != "verified_research" ->
          "Reproduction-phase security work requires verified_research mode."

        SecurityWorkflow.isolated_runtime_required?(task) and
            not SecurityWorkflow.isolated_runtime_path?(claim_metadata) ->
          "Reproduction-phase security work must run through an isolated runtime path."

        true ->
          nil
      end
    end
  end

  # Make unsandboxed host execution VISIBLE without gating delivery: when embedded
  # execution resolves to the local (host) adapter, log a warning. Refusing host is
  # opt-in via ExecutionSandbox.enforce_sandbox? (which blocks at the run boundary);
  # this is just the signal so operators can see a run had no isolation. Non-gating by
  # design — host execution is allowed unless the operator has enabled enforce_sandbox,
  # so it must not create an open finding that would block complete_task.
  defp maybe_flag_host_execution(task, _session, sandbox_choice) do
    if ExecutionSandbox.adapter_name(sandbox: sandbox_choice) in [nil, "local"] do
      Logger.warning(
        "[execution_sandbox] embedded agent execution for task #{task.id} ran on the host " <>
          "(local adapter) with no isolation. Set execution_sandbox=docker or enable " <>
          "enforce_sandbox to require an isolated runtime."
      )
    end

    :ok
  end

  defp dispatch_run(task, session, integration, "embedded", package_root, service_account_context) do
    sandbox_choice = Process.get(:ck_execution_sandbox)
    _ = maybe_flag_host_execution(task, session, sandbox_choice)

    result_path = Path.join(package_root, "result.json")
    heartbeat_path = Path.join(package_root, "progress.json")

    with {:ok, command, args} <- direct_command(integration.id),
         sandbox_opts = direct_run_env(task, session, integration, package_root, result_path),
         {:ok, run_result} <-
           ExecutionSandbox.run(command, args,
             env: sandbox_opts,
             sandbox: sandbox_choice,
             timeout_ms: executor_timeout_ms(),
             result_path: result_path,
             heartbeat_path: heartbeat_path
           ),
         %{output: output, exit_status: exit_status} = run_result do
      payload = direct_result_payload(output, result_path)
      validation = validate_result_payload(payload, session, task)
      status = direct_result_status(exit_status, validation)

      _ =
        Platform.record_task_checks(
          task.id,
          service_account_context[:service_account],
          [
            %{
              check_type: "executor",
              status: if(exit_status == 0, do: "passed", else: "failed"),
              summary: "Executor command exited with status #{exit_status}.",
              payload: %{
                "command" => command,
                "args" => args,
                "output" => String.slice(output, 0, 4_000)
              },
              metadata:
                %{"transport" => "embedded"}
                |> Map.put("timed_out", Map.get(run_result, :timed_out, false))
                |> Map.put("killed_on_result", Map.get(run_result, :killed_on_result, false))
            }
          ] ++ validation_checks(validation)
        )

      result_ref = write_stdout_ref(package_root, output)
      maybe_emit_loop_finding(task, session, output)

      case Platform.report_task(task.id, service_account_context[:service_account], %{
             status: status,
             output: Map.merge(payload, %{"stdout" => String.slice(output, 0, 8_000)}),
             metadata: %{
               "executor_mode" => "embedded",
               "command" => [command | args],
               "validation" => validation,
               "result_ref" => result_ref,
               "heartbeat_path" => heartbeat_path,
               "timed_out" => Map.get(run_result, :timed_out, false),
               "killed_on_result" => Map.get(run_result, :killed_on_result, false),
               "execution_sandbox" =>
                 ExecutionSandbox.adapter_name(sandbox: Process.get(:ck_execution_sandbox))
             }
           }) do
        {:ok, _run} ->
          _ =
            record_delegate_result(task, integration, status, %{
              "mode" => "embedded",
              "package_root" => package_root,
              "command" => [command | args],
              "result_ref" => result_ref
            })

          {:ok,
           %{
             "task_id" => task.id,
             "session_id" => session.id,
             "agent_id" => integration.id,
             "mode" => "embedded",
             "status" => status,
             "package_root" => package_root,
             "result_ref" => result_ref,
             "result_length" => byte_size(output),
             "command" => [command | args],
             "validation" => validation,
             "metadata" => %{
               "execution_sandbox" =>
                 ExecutionSandbox.adapter_name(sandbox: Process.get(:ck_execution_sandbox))
             }
           }}

        {:error, :proof_not_ready, detail} ->
          _ =
            record_delegate_result(task, integration, "failed", %{
              "mode" => "embedded",
              "package_root" => package_root,
              "error" => "proof_not_ready: #{detail}"
            })

          {:error, {:proof_not_ready, detail}}

        {:error, reason} ->
          _ =
            record_delegate_result(task, integration, "failed", %{
              "mode" => "embedded",
              "package_root" => package_root,
              "error" => inspect(reason)
            })

          {:error, reason}
      end
    else
      {:error, :missing_direct_command} ->
        _ =
          record_delegate_result(task, integration, "failed", %{
            "mode" => "embedded",
            "error" => "missing_direct_command"
          })

        {:error, :missing_direct_command}
    end
  end

  defp dispatch_run(task, session, integration, mode, package_root, service_account_context)
       when mode in ["handoff", "runtime"] do
    service_account = service_account_context[:service_account]

    _ =
      Platform.record_task_checks(task.id, service_account, [
        %{
          check_type: mode,
          status: "passed",
          summary: "Prepared a governed #{mode} package for #{integration.label}.",
          payload: %{
            "package_root" => package_root,
            "preferred_target" => integration.preferred_target
          },
          metadata: %{"transport" => mode}
        }
      ])

    metadata =
      %{
        "executor_mode" => mode,
        "package_root" => package_root,
        "oauth_client_id" => service_account_context[:oauth_client_id],
        "preferred_target" => integration.preferred_target
      }
      |> maybe_put_map_value("bundle_path", service_account_context[:bundle_path])
      |> maybe_put_map_value("service_account_id", service_account && service_account.id)

    case Platform.report_task(task.id, service_account, %{
           status: "waiting_callback",
           output: %{"package_root" => package_root},
           metadata: metadata
         }) do
      {:ok, _run} ->
        _ =
          record_delegate_result(task, integration, "waiting_callback", %{
            "mode" => mode,
            "package_root" => package_root
          })

        {:ok,
         %{
           "task_id" => task.id,
           "session_id" => session.id,
           "agent_id" => integration.id,
           "mode" => mode,
           "status" => "waiting_callback",
           "package_root" => package_root,
           "bundle_path" => service_account_context[:bundle_path],
           "oauth_client_id" => service_account_context[:oauth_client_id],
           "client_secret" => service_account_context[:client_secret]
         }}

      {:error, :proof_not_ready, detail} ->
        _ =
          record_delegate_result(task, integration, "failed", %{
            "mode" => mode,
            "package_root" => package_root,
            "error" => "proof_not_ready: #{detail}"
          })

        {:error, {:proof_not_ready, detail}}

      {:error, reason} ->
        _ =
          record_delegate_result(task, integration, "failed", %{
            "mode" => mode,
            "package_root" => package_root,
            "error" => inspect(reason)
          })

        {:error, reason}
    end
  end

  defp prepare_run_package(project_root, session, task, integration, execution_mode) do
    root =
      Path.join([
        Path.expand(project_root),
        "controlkeel",
        "runs",
        "task-#{task.id}-#{System.unique_integer([:positive])}"
      ])

    brief = session.execution_brief || %{}
    boundary_summary = Intent.boundary_summary(brief)
    workspace_context = Mission.workspace_context(session, fallback_root: project_root)
    recent_events = Mission.list_session_events(session.id)

    with :ok <- File.mkdir_p(root),
         :ok <-
           File.write(
             Path.join(root, "TASK.md"),
             task_markdown(task, session, integration, execution_mode)
           ),
         :ok <-
           File.write(
             Path.join(root, "task.json"),
             Jason.encode!(task_payload(task, integration, execution_mode), pretty: true) <> "\n"
           ),
         :ok <-
           File.write(
             Path.join(root, "session.json"),
             Jason.encode!(
               %{
                 "id" => session.id,
                 "workspace_id" => session.workspace_id,
                 "title" => session.title,
                 "objective" => session.objective,
                 "risk_tier" => session.risk_tier,
                 "execution_brief" => brief,
                 "boundary_summary" => boundary_summary,
                 "workspace_context_cache_key" => workspace_context["cache_key"]
               },
               pretty: true
             ) <> "\n"
           ),
         :ok <-
           File.write(
             Path.join(root, "workspace_context.json"),
             Jason.encode!(workspace_context, pretty: true) <> "\n"
           ),
         :ok <-
           File.write(
             Path.join(root, "recent_events.json"),
             Jason.encode!(recent_events, pretty: true) <> "\n"
           ) do
      {:ok, root}
    end
  end

  defp maybe_create_service_account(_session, "embedded"),
    do: {:ok, %{service_account: nil, oauth_client_id: nil, client_secret: nil, bundle_path: nil}}

  defp maybe_create_service_account(session, mode) when mode in ["handoff", "runtime"] do
    with {:ok, %{service_account: account, token: token}} <-
           Platform.create_service_account(session.workspace_id, %{
             "name" => "executor-#{mode}-session-#{session.id}",
             "scopes" => Enum.join(hosted_scopes(), " "),
             "metadata" => %{
               "cyber_access_mode" => SecurityWorkflow.session_cyber_access_mode(session)
             }
           }) do
      {:ok,
       %{
         service_account: account,
         oauth_client_id: ProtocolAccess.oauth_client_id(account),
         client_secret: token,
         bundle_path: nil
       }}
    end
  end

  defp prepare_support_assets(package_root, project_root, integration, execution_mode, context)
       when execution_mode in ["handoff", "runtime"] do
    bundle_path = export_bundle_into_package(package_root, project_root, integration)
    write_credentials_file(package_root, execution_mode, context)

    {:ok, Map.put(context, :bundle_path, bundle_path)}
  end

  defp prepare_support_assets(
         _package_root,
         _project_root,
         _integration,
         _execution_mode,
         context
       ),
       do: {:ok, context}

  defp base_run_metadata(integration, execution_mode, package_root, service_account_context) do
    %{
      "agent_id" => integration.id,
      "agent_label" => integration.label,
      "execution_support" => integration.execution_support,
      "executor_mode" => execution_mode,
      "package_root" => package_root,
      "autonomy_mode" => integration.autonomy_mode
    }
    |> maybe_put_map_value("oauth_client_id", service_account_context[:oauth_client_id])
    |> maybe_put_map_value("preferred_target", integration.preferred_target)
  end

  defp task_markdown(task, session, integration, execution_mode) do
    """
    # #{task.title}

    - Session: ##{session.id} — #{session.title}
    - Agent: #{integration.label} (#{integration.id})
    - Execution mode: #{execution_mode}
    - Validation gate: #{task.validation_gate}
    - Risk tier: #{session.risk_tier}

    ## Objective

    #{session.objective || "No objective recorded."}
    """
  end

  defp task_payload(task, integration, execution_mode) do
    %{
      "id" => task.id,
      "title" => task.title,
      "status" => task.status,
      "position" => task.position,
      "estimated_cost_cents" => task.estimated_cost_cents,
      "validation_gate" => task.validation_gate,
      "session_id" => task.session_id,
      "agent_id" => integration.id,
      "execution_mode" => execution_mode,
      "trust_policy" => task.trust_policy || "full",
      "input_refs" => task.input_refs || [],
      "output_ref" => task.output_ref,
      "input_ref_map" => get_in(task.metadata || %{}, ["input_ref_map"]) || %{}
    }
  end

  defp validation_checks(nil), do: []

  defp validation_checks(validation) do
    [
      %{
        check_type: "validation",
        status: if(validation["allowed"], do: "passed", else: "failed"),
        summary: validation["summary"],
        payload: validation,
        metadata: %{"decision" => validation["decision"]}
      }
    ]
  end

  defp validate_result_payload(%{"content" => content} = payload, session, task)
       when is_binary(content) and content != "" do
    arguments = %{
      "content" => content,
      "kind" => Map.get(payload, "kind", "text"),
      "session_id" => session.id,
      "task_id" => task.id,
      "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
    }

    case CkValidate.call(arguments) do
      {:ok, validation} -> validation
      _ -> nil
    end
  end

  defp validate_result_payload(_payload, _session, _task), do: nil

  defp direct_result_status(_exit_status, %{"allowed" => false}), do: "blocked"
  defp direct_result_status(0, _validation), do: "done"
  defp direct_result_status(_status, _validation), do: "failed"

  defp direct_result_payload(output, result_path) do
    payload =
      case File.read(result_path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, decoded} when is_map(decoded) -> decoded
            _ -> %{}
          end

        _ ->
          %{}
      end

    Map.put_new(payload, "output_preview", String.slice(output, 0, 2_000))
  end

  defp direct_run_env(task, session, integration, package_root, result_path) do
    project_root =
      get_in(session.metadata || %{}, ["runtime_context", "project_root"]) ||
        Path.expand(Path.join(package_root, "../../.."))

    [
      {"CONTROLKEEL_TASK_ID", to_string(task.id)},
      {"CONTROLKEEL_SESSION_ID", to_string(session.id)},
      {"CONTROLKEEL_AGENT_ID", integration.id},
      {"CONTROLKEEL_PROJECT_ROOT", Path.expand(project_root)},
      {"CONTROLKEEL_RUN_PACKAGE", package_root},
      {"CONTROLKEEL_TASK_JSON", Path.join(package_root, "task.json")},
      {"CONTROLKEEL_SESSION_JSON", Path.join(package_root, "session.json")},
      {"CONTROLKEEL_WORKSPACE_CONTEXT_JSON", Path.join(package_root, "workspace_context.json")},
      {"CONTROLKEEL_RECENT_EVENTS_JSON", Path.join(package_root, "recent_events.json")},
      {"CONTROLKEEL_RESULT_PATH", result_path},
      {"CONTROLKEEL_INPUT_REFS", build_input_refs_env(task)}
    ]
  end

  defp build_input_refs_env(%{input_refs: []}), do: "[]"

  defp build_input_refs_env(%{input_refs: refs, metadata: meta}) do
    ref_map = get_in(meta || %{}, ["input_ref_map"]) || %{}

    entries =
      Enum.map(refs, fn ref ->
        pkg = Map.get(ref_map, ref)

        %{
          "ref" => ref,
          "package_root" => pkg,
          "stdout_path" => pkg && Path.join(pkg, "stdout.txt")
        }
      end)

    Jason.encode!(entries)
  end

  defp build_input_refs_env(_task), do: "[]"

  # Hard deadline for headless agent-CLI sub-workers (agy -p, claude -p, codex
  # exec, …). These CLIs can idle after delivering their result; the streaming
  # Local adapter kills on result delivery and enforces this deadline as a
  # backstop. Override per deployment with CONTROLKEEL_EXECUTOR_TIMEOUT_MS.
  defp executor_timeout_ms do
    case System.get_env("CONTROLKEEL_EXECUTOR_TIMEOUT_MS") do
      nil ->
        600_000

      raw ->
        case Integer.parse(raw) do
          {ms, ""} when ms > 0 -> ms
          _ -> 600_000
        end
    end
  end

  defp direct_command_available?(agent_id) do
    configured_command(agent_id) != nil
  end

  defp direct_command(agent_id) do
    case configured_command(agent_id) do
      nil ->
        {:error, :missing_direct_command}

      command ->
        case OptionParser.split(command) do
          [cmd | args] -> {:ok, cmd, args}
          _ -> {:error, :missing_direct_command}
        end
    end
  end

  defp configured_command(agent_id) do
    agent_id
    |> String.upcase()
    |> String.replace("-", "_")
    |> then(&System.get_env("CONTROLKEEL_EXECUTOR_#{&1}_CMD"))
    |> case do
      "" -> nil
      nil -> nil
      command -> command
    end
  end

  defp executable_path(agent_id) do
    agent_id
    |> then(&Map.get(@direct_executable_candidates, &1, []))
    |> Enum.find_value(&System.find_executable/1)
  end

  defp runnable?("direct", configured_command, _executable_path, _integration),
    do: configured_command != nil

  defp runnable?("handoff", _configured_command, _executable_path, %Integration{
         preferred_target: target
       }),
       do: is_binary(target)

  defp runnable?("runtime", _configured_command, _executable_path, %Integration{}), do: true
  defp runnable?(_, _configured_command, _executable_path, _integration), do: false

  defp policy_gate_reason(session) do
    blocked_findings? =
      session.findings
      |> List.wrap()
      |> Enum.any?(&(&1.status in ["blocked", "escalated"]))

    boundary = Intent.boundary_summary(session.execution_brief || %{})

    manual_gate? =
      boundary
      |> Map.get("constraints", [])
      |> Enum.any?(&String.match?(String.downcase(&1), ~r/(human|manual)\s+approval/))

    cond do
      blocked_findings? ->
        "Blocked or escalated findings require human review before delegated execution."

      manual_gate? ->
        "The current execution brief requires explicit human approval before delegated execution."

      true ->
        nil
    end
  end

  defp normalize_requested_agent(nil), do: nil
  defp normalize_requested_agent(""), do: nil
  defp normalize_requested_agent("auto"), do: nil
  defp normalize_requested_agent(value), do: value

  defp normalize_requested_mode(nil), do: "auto"
  defp normalize_requested_mode(""), do: "auto"
  defp normalize_requested_mode("direct"), do: "embedded"
  defp normalize_requested_mode(value), do: value

  defp task_run_execution_mode("embedded"), do: "local"
  defp task_run_execution_mode("handoff"), do: "external"
  defp task_run_execution_mode("runtime"), do: "cloud"

  defp attach_runtime_contexts(task, session, integration, execution_mode, project_root) do
    runtime_context = %{
      "project_root" => Path.expand(project_root),
      "agent_id" => integration.id,
      "execution_mode" => execution_mode
    }

    with {:ok, _task} <- Mission.attach_task_runtime_context(task.id, runtime_context),
         {:ok, _session} <- Mission.attach_session_runtime_context(session.id, runtime_context) do
      :ok
    else
      _ -> :ok
    end
  end

  defp record_delegate_prepared(task, integration, execution_mode, package_root) do
    SessionTranscript.record(%{
      session_id: task.session_id,
      task_id: task.id,
      event_type: "delegate.prepared",
      actor: integration.id,
      summary: "Prepared a governed run package for #{integration.label}.",
      body: "Execution mode: #{execution_mode}",
      payload: %{
        "agent_id" => integration.id,
        "execution_mode" => execution_mode,
        "package_root" => package_root
      }
    })

    :ok
  end

  defp record_delegate_result(task, integration, status, payload) do
    event_type =
      case status do
        "waiting_callback" -> "delegate.waiting"
        "done" -> "delegate.done"
        "blocked" -> "delegate.blocked"
        _ -> "delegate.failed"
      end

    SessionTranscript.record(%{
      session_id: task.session_id,
      task_id: task.id,
      event_type: event_type,
      actor: integration.id,
      summary: "Delegated execution is #{String.replace(status, "_", " ")}.",
      body: "Task #{task.title}",
      payload:
        Map.merge(%{"agent_id" => integration.id, "status" => status}, stringify_payload(payload))
    })

    :ok
  end

  defp attached_agent_ids(project_root) do
    with {:ok, binding, _mode} <- Binding.read_effective(project_root),
         attached when is_map(attached) <- Map.get(binding, "attached_agents", %{}) do
      Enum.map(Map.keys(attached), &String.replace(to_string(&1), "_", "-"))
    else
      _ -> []
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_map_value(map, _key, nil), do: map
  defp maybe_put_map_value(map, key, value), do: Map.put(map, key, value)

  defp export_bundle_into_package(package_root, project_root, %Integration{
         preferred_target: target
       })
       when is_binary(target) do
    case Skills.export(target, project_root, scope: "export") do
      {:ok, plan} ->
        destination = Path.join(package_root, "bundle")
        File.mkdir_p!(destination)
        copy_tree_contents(plan.output_dir, destination)
        destination

      _ ->
        nil
    end
  end

  defp export_bundle_into_package(_package_root, _project_root, _integration), do: nil

  defp write_credentials_file(package_root, execution_mode, context) do
    credentials =
      %{
        "mode" => execution_mode,
        "oauth_client_id" => context[:oauth_client_id],
        "client_secret" => context[:client_secret],
        "token_endpoint" => "/oauth/token",
        "mcp_resource" => "/mcp",
        "a2a_resource" => "/a2a"
      }

    File.write!(
      Path.join(package_root, "credentials.json"),
      Jason.encode!(credentials, pretty: true) <> "\n"
    )
  end

  defp copy_tree_contents(source_root, destination_root) do
    File.mkdir_p!(destination_root)

    source_root
    |> File.ls!()
    |> Enum.each(fn entry ->
      source = Path.join(source_root, entry)
      destination = Path.join(destination_root, entry)
      File.rm_rf!(destination)
      File.cp_r!(source, destination)
    end)
  end

  defp stringify_payload(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp hosted_scopes do
    ["a2a:access" | ControlKeel.Mcp.ProtocolInterop.hosted_mcp_scopes()]
  end

  # Writes the full stdout to package_root/stdout.txt and returns a
  # content-addressed ref (first 16 hex chars of SHA256).
  defp write_stdout_ref(package_root, output) when is_binary(output) and output != "" do
    ref =
      output
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    path = Path.join(package_root, "stdout.txt")
    _ = File.write(path, output)
    ref
  end

  defp write_stdout_ref(_package_root, _output), do: nil

  # Emits an agent-loop finding when stdout shows repetitive verification
  # patterns (≥3 occurrences of "verify" or "check" in close succession).
  @loop_verify_threshold 3

  defp maybe_emit_loop_finding(task, session, output) when is_binary(output) do
    verify_count =
      output
      |> String.downcase()
      |> then(fn s ->
        length(Regex.scan(~r/\b(verify|re-verify|re_verify|double.check)\b/, s))
      end)

    if verify_count >= @loop_verify_threshold do
      _ =
        Mission.create_finding(%{
          title: "Verification loop detected in embedded agent output",
          severity: "high",
          category: "agent-loop",
          rule_id: "rlm.verification_loop",
          plain_message:
            "Agent output contains #{verify_count} verification signals. " <>
              "This matches the RLM verification-loop failure pattern: the agent may be re-verifying " <>
              "instead of committing to a result. Surface the last partial result and terminate if looping continues.",
          status: "open",
          auto_resolved: false,
          metadata: %{
            "verify_count" => verify_count,
            "task_id" => task.id,
            "source" => "rlm_loop_detector"
          },
          session_id: session.id
        })
    end

    :ok
  end

  defp maybe_emit_loop_finding(_task, _session, _output), do: :ok
end
