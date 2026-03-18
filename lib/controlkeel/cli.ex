defmodule ControlKeel.CLI do
  @moduledoc false

  alias ControlKeel.Analytics
  alias ControlKeel.Budget
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.LocalProject
  alias ControlKeel.Mission
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Proxy

  @init_switches [
    industry: :string,
    agent: :string,
    idea: :string,
    features: :string,
    budget: :string,
    users: :string,
    data: :string,
    project_name: :string
  ]
  @findings_switches [severity: :string, status: :string]
  @mcp_switches [project_root: :string]
  @watch_switches [interval: :integer]

  def standalone_argv do
    if Code.ensure_loaded?(Burrito.Util.Args) and function_exported?(Burrito.Util.Args, :argv, 0) do
      Burrito.Util.Args.argv()
    else
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

      ["attach", "claude-code"] ->
        {:ok, %{command: :attach, options: %{}, args: ["claude-code"]}}

      ["status"] ->
        {:ok, %{command: :status, options: %{}, args: []}}

      ["findings" | rest] ->
        parse_with_switches(:findings, rest, @findings_switches)

      ["approve", finding_id] ->
        {:ok, %{command: :approve, options: %{}, args: [finding_id]}}

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
      controlkeel attach claude-code  Register ControlKeel as a local Claude Code MCP server
      controlkeel status              Show current session status
      controlkeel findings [options]  List findings for the current session
      controlkeel approve <id>        Approve a finding in the current session
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

    case LocalProject.init(attrs, project_root) do
      {:ok, binding, :created} ->
        {:ok,
         [
           "Initialized ControlKeel for #{binding["project_root"]}",
           "Project binding: #{ProjectBinding.path(project_root)}",
           "MCP wrapper: #{ProjectBinding.mcp_wrapper_path(project_root)}"
         ]}

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

  def run_command(%{command: :attach, args: ["claude-code"]}, project_root) do
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
       ]}
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

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

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

  defp format_money(nil), do: "unlimited"
  defp format_money(cents), do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()
  defp format_duration(nil), do: "not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"
end
