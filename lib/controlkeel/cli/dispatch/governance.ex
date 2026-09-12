defmodule ControlKeel.CLI.Dispatch.Governance do
  @moduledoc false

  alias ControlKeel.Governance
  alias ControlKeel.Mission.FindingPlainEnglish, as: PlainEnglish
  alias ControlKeel.Project.Local
  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Project.Root
  import ControlKeel.CLI, except: [run_command: 2]

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

  def run_command(%{command: :context, options: options}, project_root) do
    project_root_resolved = resolve_project_root(options, project_root)

    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <- ensure_local_project(project_root_resolved) do
      session_id = options[:session_id] || default_session.id

      args =
        %{
          "session_id" => session_id,
          "project_root" => Root.resolve(project_root_resolved)
        }
        |> maybe_put_tool_int("task_id", options[:task_id])

      case CkContext.call(args) do
        {:ok, payload} ->
          render_format(format, payload, fn p -> [inspect(p, pretty: true, limit: :infinity)] end)

        {:error, {:invalid_arguments, msg}} when is_binary(msg) ->
          {:error, msg}

        {:error, {:invalid_arguments, reason}} ->
          {:error, format_cli_error(reason)}

        {:error, reason} ->
          {:error, "Failed to load context: #{format_cli_error(reason)}"}
      end
    end
  end

  def run_command(%{command: :validate, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <-
           ensure_local_project(options[:project_root] || project_root) do
      content = options[:content]

      if not is_binary(content) or String.trim(content) == "" do
        {:error, "`--content` is required for controlkeel validate."}
      else
        args =
          %{
            "content" => content,
            "kind" => options[:kind] || "code",
            "session_id" => options[:session_id] || default_session.id
          }
          |> maybe_put_tool_int("task_id", options[:task_id])
          |> maybe_put_tool_string("path", options[:path])

        case CkValidate.call(args) do
          {:ok, payload} ->
            render_format(format, payload, fn p ->
              [inspect(p, pretty: true, limit: :infinity)]
            end)

          {:error, {:invalid_arguments, msg}} when is_binary(msg) ->
            {:error, msg}
        end
      end
    end
  end

  def run_command(%{command: :findings, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <-
           ensure_local_project(options[:project_root] || project_root) do
      findings =
        Mission.list_session_findings(session.id, %{
          severity: options[:severity],
          status: options[:status]
        })

      security_summary = Mission.security_case_summary(findings)

      active_total =
        Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))

      filter_summary = findings_filter_summary(options)
      help_lines = findings_help_lines(findings, options)

      payload = %{
        "summary" => %{
          "matched" => length(findings),
          "active_findings_in_session" => active_total,
          "filter_summary" => filter_summary,
          "security_case_summary" => security_summary
        },
        "entries" =>
          Enum.map(findings, fn finding ->
            %{
              "id" => finding.id,
              "severity" => finding.severity,
              "status" => finding.status,
              "title" => finding.title,
              "rule_id" => finding.rule_id
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          if findings == [] do
            {:ok,
             [
               "Findings: 0 matched#{filter_summary}",
               "Active findings in session: #{active_total}",
               "Security cases: #{security_case_status_line(security_summary)}"
             ] ++ help_lines}
          else
            {:ok,
             [
               "Findings: #{length(findings)} matched#{filter_summary}",
               "Active findings in session: #{active_total}",
               "Security cases: #{security_case_status_line(security_summary)}"
             ] ++
               Enum.map(findings, fn finding ->
                 "##{finding.id} [#{finding.severity}/#{finding.status}] #{finding.title} (#{finding.rule_id})"
               end) ++ help_lines}
          end
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

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
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <-
           ensure_local_project(options[:project_root] || project_root) do
      browser =
        Mission.browse_proof_bundles(%{
          session_id: options[:session_id] || session.id,
          task_id: options[:task_id],
          deploy_ready: options[:deploy_ready]
        })

      help_lines = proofs_help_lines(browser.entries, options)

      payload = %{
        "summary" => %{
          "matched" => length(browser.entries),
          "session_proof_bundles" => browser.total_count,
          "deploy_ready_in_view" => Enum.count(browser.entries, & &1.deploy_ready),
          "filter_summary" => proofs_filter_summary(options)
        },
        "entries" =>
          Enum.map(browser.entries, fn proof ->
            %{
              "id" => proof.id,
              "version" => proof.version,
              "status" => proof.status,
              "task_id" => proof.task_id,
              "task_title" => proof.task.title,
              "risk_score" => proof.risk_score,
              "deploy_ready" => proof.deploy_ready
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          if browser.entries == [] do
            {:ok,
             [
               "Proof bundles: 0 matched#{proofs_filter_summary(options)}",
               "Session proof bundles: #{browser.total_count}",
               "Deploy-ready in view: 0"
             ] ++ help_lines}
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
               end) ++ help_lines}
          end
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

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

  def run_command(%{command: :progress, options: options}, project_root) do
    session_id = options[:session_id]

    session_id =
      if session_id do
        session_id
      else
        case Local.load(project_root) do
          {:ok, _binding, session} -> session.id
          _ -> nil
        end
      end

    if is_nil(session_id) do
      {:error, "No active session. Use --session-id or run from a bound project."}
    else
      case ControlKeel.Mission.Progress.compute(session_id) do
        {:ok, progress} ->
          with {:ok, format} <- effective_cli_format(options) do
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

            help_lines = progress_help_lines(progress, current_task)

            payload = %{
              "session_id" => session_id,
              "overall_percent" => progress.overall_percent,
              "tasks" => progress.tasks,
              "findings" => progress.findings,
              "budget" => progress.budget,
              "estimated_effort" => progress.estimated_effort,
              "current_task" => current_task_payload(current_task),
              "remaining_items" => progress.remaining_items,
              "suggested_next_steps" => help_lines_to_values(help_lines)
            }

            case format do
              "json" ->
                {:ok, [Jason.encode!(payload)]}

              _ ->
                {:ok, lines ++ help_lines}
            end
          else
            {:error, {:invalid_output_format, message}} ->
              {:error, message}
          end

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
        case Local.load(project_root) do
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
end
