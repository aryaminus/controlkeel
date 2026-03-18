defmodule Mix.Tasks.Ck.Watch do
  use Mix.Task

  alias ControlKeel.Budget
  alias ControlKeel.LocalProject
  alias ControlKeel.Mission

  @shortdoc "Stream real-time findings and budget for the current governed session"

  @moduledoc """
  Watches the current governed session and prints findings as they arrive.
  Polls every 2 seconds. Press Ctrl+C to exit.

  Usage:

      mix ck.watch [--interval 2000]

  Options:

    --interval  Poll interval in milliseconds (default: 2000)

  """

  @default_interval 2_000

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [interval: :integer])
    interval = Keyword.get(opts, :interval, @default_interval)

    project_root = File.cwd!()

    case LocalProject.load(project_root) do
      {:ok, _binding, session} ->
        shell = Mix.shell()
        shell.info("")
        shell.info("ControlKeel Watch — session ##{session.id}: #{session.title}")
        shell.info("  Polling every #{interval}ms  ·  Ctrl+C to exit")
        shell.info(String.duplicate("─", 60))

        watch_loop(session.id, MapSet.new(), interval, shell)

      {:error, :not_found} ->
        Mix.raise("No governed session found. Run `mix ck.init` first.")

      {:error, reason} ->
        Mix.raise("Failed to load local project: #{inspect(reason)}")
    end
  end

  defp watch_loop(session_id, seen, interval, shell) do
    findings = Mission.list_session_findings(session_id)
    session = Mission.get_session(session_id)

    new_findings = Enum.reject(findings, fn f -> MapSet.member?(seen, f.id) end)
    updated_seen = Enum.reduce(new_findings, seen, fn f, acc -> MapSet.put(acc, f.id) end)

    Enum.each(new_findings, fn f ->
      print_finding(shell, f)
    end)

    if session do
      print_budget_line(shell, session)
    end

    Process.sleep(interval)
    watch_loop(session_id, updated_seen, interval, shell)
  end

  defp print_finding(shell, finding) do
    severity_badge =
      case finding.severity do
        "critical" -> "[CRITICAL]"
        "high" -> "[HIGH]    "
        "medium" -> "[MEDIUM]  "
        _ -> "[LOW]     "
      end

    status_badge =
      case finding.status do
        "blocked" -> "BLOCKED"
        "approved" -> "approved"
        "rejected" -> "rejected"
        "escalated" -> "ESCALATED"
        _ -> "open"
      end

    shell.info("")
    shell.info("  #{severity_badge} #{finding.rule_id}  (#{status_badge})")
    shell.info("  #{finding.plain_message || finding.title}")
  end

  defp print_budget_line(shell, session) do
    spent = session.spent_cents || 0
    budget = session.budget_cents || 0
    rolling = Budget.rolling_24h_spend_cents(session.id)

    pct =
      if budget > 0 do
        round(spent / budget * 100)
      else
        0
      end

    bar = budget_bar(pct)

    shell.info("")
    shell.info(
      "  Budget  #{bar}  #{format_cents(spent)}/#{format_cents(budget)} (#{pct}%)  " <>
        "· rolling 24h: #{format_cents(rolling)}"
    )

    shell.info(String.duplicate("─", 60))
  end

  defp budget_bar(pct) do
    filled = round(pct / 5)
    empty = 20 - filled
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end

  defp format_cents(nil), do: "$0.00"
  defp format_cents(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
end
