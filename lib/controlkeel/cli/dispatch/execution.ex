defmodule ControlKeel.CLI.Dispatch.Execution do
  @moduledoc false

  alias ControlKeel.Agent.Execution
  alias ControlKeel.Agent.Router
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(
        %{command: :run_cloud_agent, options: options, args: [task_id_str]},
        project_root
      ) do
    alias ControlKeel.Cloud.RuntimeContext
    alias ControlKeel.Mission

    with {:ok, task_id} <- parse_integer_arg(task_id_str, "task-id"),
         {:ok, runtime} <- require_string_option(options[:runtime], "runtime"),
         :ok <- validate_runtime_target(runtime),
         {:ok, budget} <- validate_budget_cents(options[:budget_cents]),
         %{} = task <- Mission.get_task(task_id) do
      session = Mission.get_session(task.session_id)
      workspace_id = session && session.workspace_id

      cond do
        workspace_id == nil ->
          {:error, "Task #{task_id} has no associated workspace"}

        true ->
          root = options[:project_root] || project_root
          git = capture_git_metadata(root, options)

          attrs =
            %{
              workspace_id: workspace_id,
              session_id: session.id,
              task_id: task.id,
              runtime_target: runtime,
              budget_cents_allocated: budget,
              scopes: parse_scopes(options[:scopes]),
              payload: build_cloud_payload(task, options),
              user_id: options[:user_id]
            }
            |> Map.merge(git)

          case RuntimeContext.create_package(attrs) do
            {:ok, package, raw_token} ->
              dispatch? = options[:dispatch] == true

              {final_package, dispatch_lines} =
                if dispatch? do
                  case RuntimeContext.dispatch_package(package, raw_token) do
                    {:ok, dispatched} ->
                      meta = get_in(dispatched.payload, ["dispatch_metadata"]) || %{}

                      {dispatched,
                       [
                         "Dispatched via: #{Map.get(meta, "mode", "(unknown)")}",
                         "Dispatch note: #{Map.get(meta, "note", "")}"
                       ]}

                    {:error, reason} ->
                      {package, ["Dispatch failed: #{inspect(reason)}"]}
                  end
                else
                  {package, []}
                end

              {:ok,
               [
                 "Cloud run package created",
                 "Package: #{final_package.external_id}",
                 "Task: #{task.id} — #{task.title}",
                 "Runtime: #{final_package.runtime_target}",
                 "Budget allocated (cents): #{final_package.budget_cents_allocated}",
                 "Scopes: #{final_package.scopes || "(none)"}",
                 "Repo: #{final_package.repo_url || "(none)"}",
                 "Branch: #{final_package.branch || "(none)"}",
                 "Commit: #{final_package.commit_sha || "(none)"}",
                 "Callback token (deliver out of band): #{raw_token}",
                 "Status: #{final_package.status}"
               ] ++ dispatch_lines}

            {:error, :unauthorized} ->
              {:error,
               "Cloud execution unauthorized: workspace belongs to an org and no valid membership was found. Provide --user-id with an active org member."}

            {:error, :org_suspended} ->
              {:error, "Cloud execution unauthorized: workspace org is suspended."}

            {:error, :unbound_workspace} ->
              {:error,
               "Cloud execution requires an organization-bound workspace. Use a task in a workspace that belongs to an organization."}

            {:error, :not_found} ->
              {:error, "Cloud execution unauthorized: workspace not found."}

            {:error, changeset} ->
              {:error, "Failed to create package: #{format_changeset_errors(changeset)}"}
          end
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      {:error, msg} when is_binary(msg) -> {:error, msg}
      nil -> {:error, "Task not found: #{task_id_str}"}
    end
  end

  def run_command(%{command: :route_agent, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, task_title} <- require_string_option(options[:task], "task"),
         {:ok, risk_tier} <- optional_risk_tier(options[:risk_tier]) do
      router_opts =
        []
        |> maybe_put_cli_opt(:risk_tier, risk_tier)
        |> maybe_put_cli_opt(:budget_remaining_cents, options[:budget_remaining_cents])
        |> maybe_put_cli_opt(:allowed_agents, parse_allowed_agents(options[:allowed_agents]))
        |> maybe_put_cli_opt(:domain_pack, options[:domain_pack])

      case Router.route(task_title, router_opts) do
        {:ok, recommendation} ->
          render_format(format, %{"recommendation" => recommendation}, fn _p ->
            [
              "Recommended agent: #{recommendation.agent}",
              "Task type: #{recommendation.task_type}",
              "Rationale: #{Enum.join(recommendation.rationale || [], " | ")}",
              if((recommendation.warnings || []) == [],
                do: "Warnings: none",
                else: "Warnings: #{Enum.join(recommendation.warnings, " | ")}"
              )
            ]
          end)

        {:error, :no_suitable_agent, message} ->
          {:error, message}
      end
    end
  end

  def run_command(%{command: :task_complete, args: [task_id]}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, updated_task} <- Mission.complete_task(task) do
      {:ok,
       ["Completed task ##{updated_task.id}: #{updated_task.title} (#{updated_task.status})"]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task not found."}

      {:error, :unresolved_findings, findings} ->
        {:error,
         "Task has #{length(findings)} unresolved findings; resolve or approve them before completing."}

      {:error, :proof_not_ready, reason} ->
        {:error, "Proof not ready: #{reason}"}

      {:error, :budget_exhausted} ->
        {:error,
         "Budget exhausted: cannot claim/complete without headroom. Use --force to bypass."}

      {:error, reason} ->
        {:error, "Failed to complete task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :proof_verify, args: [target]}, _project_root) do
    result =
      case Integer.parse(target) do
        {id, ""} ->
          case Mission.get_proof_bundle(id) do
            nil ->
              case Mission.latest_proof_bundle_for_task(id) do
                nil -> {:error, :not_found}
                proof -> Mission.verify_proof_bundle(proof)
              end

            proof ->
              Mission.verify_proof_bundle(proof)
          end

        _ ->
          {:error, :invalid_id}
      end

    case result do
      {:ok, :verified, meta} ->
        {:ok, ["Proof verified: #{inspect(meta)}"]}

      {:error, :bundle_hash_mismatch} ->
        {:error, "Proof bundle hash mismatch (detached bundle_sha256 does not match computed)."}

      {:error, :artifact_hash_mismatch} ->
        {:error, "Proof artifact hash mismatch."}

      {:error, :not_found} ->
        {:error, "Proof not found for #{target}."}

      {:error, reason} ->
        {:error, "Proof verify failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :task_claim, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, task_run} <-
           Platform.claim_task(task.id, nil, %{
             "execution_mode" => normalize_task_execution_mode(options[:execution_mode])
           }) do
      {:ok, ["Claimed task ##{task.id}: run ##{task_run.id} is #{task_run.status}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task not found."}

      {:error, reason} ->
        {:error, "Failed to claim task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_heartbeat, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, task_run} <-
           Platform.heartbeat_task(task.id, nil, %{
             "progress" => options[:progress],
             "note" => options[:note]
           }) do
      {:ok, ["Heartbeat recorded for task ##{task.id}: run ##{task_run.id}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to record heartbeat: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_checks, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, checks} <- decode_required_json_list(options[:checks], "checks"),
         {:ok, results} <- Platform.record_task_checks(task.id, nil, checks) do
      {:ok, ["Recorded #{length(results)} check result(s) for task ##{task.id}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to record checks: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_report, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, output} <- decode_optional_json_map(options[:output], "output"),
         {:ok, metadata} <- decode_optional_json_map(options[:metadata], "metadata"),
         {:ok, task_run} <-
           Platform.report_task(task.id, nil, %{
             "status" => options[:status] || "done",
             "output" => output,
             "metadata" => metadata
           }) do
      {:ok, ["Reported task ##{task.id}: run ##{task_run.id} now #{task_run.status}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to report task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :run_task, args: [task_id], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, parsed_id} <- parse_id(task_id),
         {:ok, result} <- Execution.run_task(parsed_id, agent_run_opts(options, root)) do
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
         {:ok, result} <- Execution.run_session(parsed_id, agent_run_opts(options, root)) do
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
end
