defmodule ControlKeel.Proxy.Governor do
  @moduledoc false

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.{FastPath, Semgrep}

  def benchmark_evaluate(extracted, opts \\ []) when is_map(extracted) do
    scan = scan_content(extracted.text || "", opts[:path], opts[:kind] || "text", opts)

    %{
      decision: scan.decision,
      allowed: scan.decision != "block",
      summary: scan.summary,
      findings: scan.findings
    }
  end

  def preflight(%Session{} = session, provider, tool, extracted, opts \\ []) do
    budget =
      Budget.estimate_proxy(%{
        "session_id" => session.id,
        "provider" => Atom.to_string(provider),
        "model" => extracted.model,
        "input_text" => extracted.text,
        "max_output_tokens" => extracted.max_output_tokens
      })

    budget_findings =
      case budget do
        {:ok, result} -> budget_findings(result, provider, tool)
        _other -> []
      end

    scan = scan_content(extracted.text, opts[:path], opts[:kind] || "text", opts)
    findings = uniq_findings(budget_findings ++ scan.findings)
    decision = final_decision(budget, findings)
    summary = summary_for(decision, budget, findings)

    persist_findings(session, findings, opts, "request")
    emit_decision(provider, "request", decision, session.id, length(findings))

    {:ok,
     %{
       decision: decision,
       allowed: decision != "block",
       summary: summary,
       findings: findings,
       budget: budget
     }}
  end

  def postflight(%Session{} = session, provider, extracted, opts \\ []) do
    scan = scan_content(extracted.text, opts[:path], opts[:kind] || "text", opts)
    decision = scan.decision
    summary = scan.summary

    persist_findings(session, scan.findings, opts, opts[:phase] || "response")

    emit_decision(
      provider,
      opts[:phase] || "response",
      decision,
      session.id,
      length(scan.findings)
    )

    {:ok,
     %{
       decision: decision,
       allowed: decision != "block",
       summary: summary,
       findings: scan.findings
     }}
  end

  def commit_usage(%Session{} = session, provider, tool, preflight, usage, opts \\ []) do
    budget_result =
      case usage do
        %{input_tokens: input_tokens, output_tokens: output_tokens} = usage ->
          Budget.commit(%{
            "session_id" => session.id,
            "provider" => Atom.to_string(provider),
            "model" => opts[:model],
            "input_tokens" => input_tokens,
            "cached_input_tokens" => usage[:cached_input_tokens] || 0,
            "output_tokens" => output_tokens,
            "source" => "proxy",
            "tool" => tool,
            "metadata" => %{"route" => opts[:route], "phase" => opts[:phase] || "complete"}
          })

        _other ->
          with {:ok, estimate} <- preflight,
               estimated_cost_cents when is_integer(estimated_cost_cents) <-
                 estimate["estimated_cost_cents"] do
            Budget.commit(%{
              "session_id" => session.id,
              "estimated_cost_cents" => estimated_cost_cents,
              "source" => "proxy",
              "tool" => tool,
              "metadata" => %{"route" => opts[:route], "phase" => opts[:phase] || "complete"}
            })
          end
      end

    committed_cost_cents =
      case budget_result do
        {:ok, result} -> result["estimated_cost_cents"]
        _other -> nil
      end

    :telemetry.execute(
      [:controlkeel, :proxy, :budget],
      %{
        estimated_cost_cents: estimated_cost(preflight),
        committed_cost_cents: committed_cost_cents || 0
      },
      %{provider: provider, tool: tool, session_id: session.id}
    )

    budget_result
  end

  defp scan_content(content, path, kind, opts) do
    normalized = %{"content" => content || "", "path" => path, "kind" => kind}

    fast_path =
      if String.trim(content || "") == "", do: empty_result(), else: FastPath.scan(normalized)

    semgrep_findings =
      if Semgrep.code_like?(normalized, force: fast_path.findings != []) do
        case Semgrep.scan(normalized,
               force: fast_path.findings != [],
               timeout_ms: opts[:timeout_ms]
             ) do
          {:ok, %{findings: findings}} -> findings
          _other -> []
        end
      else
        []
      end

    findings = uniq_findings(fast_path.findings ++ semgrep_findings)
    decision = findings |> Enum.map(& &1.decision) |> final_decision_from_list()

    %{
      decision: decision,
      summary: summary_from_findings(decision, findings),
      findings: findings
    }
  end

  defp budget_findings(%{"decision" => "allow"}, _provider, _tool), do: []

  defp budget_findings(result, provider, tool) do
    [
      %Scanner.Finding{
        id: "budget_" <> Integer.to_string(System.unique_integer([:positive])),
        severity: if(result["decision"] == "block", do: "high", else: "medium"),
        category: "cost",
        rule_id:
          if(result["decision"] == "block",
            do: "cost.proxy_budget_guard",
            else: "cost.proxy_budget_warning"
          ),
        decision: result["decision"],
        plain_message: result["summary"],
        location: %{"path" => "/proxy/#{provider}#{tool}", "kind" => "text"},
        metadata: %{
          "scanner" => "budget",
          "projected_spend_cents" => result["projected_spend_cents"],
          "remaining_session_cents" => result["remaining_session_cents"],
          "remaining_daily_cents" => result["remaining_daily_cents"]
        }
      }
    ]
  end

  defp persist_findings(_session, [], _opts, _phase), do: :ok

  defp persist_findings(%Session{} = session, findings, opts, phase) do
    _ =
      Mission.record_runtime_findings(session.id, findings,
        session_id: session.id,
        task_id: opts[:task_id],
        path: opts[:path],
        kind: opts[:kind] || "text",
        source: "proxy",
        phase: phase
      )

    :ok
  end

  defp emit_decision(provider, phase, decision, session_id, findings_count) do
    :telemetry.execute(
      [:controlkeel, :proxy, :decision],
      %{count: 1},
      %{
        provider: provider,
        phase: phase,
        decision: decision,
        session_id: session_id,
        findings_count: findings_count
      }
    )
  end

  defp summary_for("block", _budget, findings), do: summary_from_findings("block", findings)

  defp summary_for(decision, {:ok, budget}, findings) do
    cond do
      findings != [] -> summary_from_findings(decision, findings)
      true -> budget["summary"]
    end
  end

  defp summary_for(decision, _budget, findings), do: summary_from_findings(decision, findings)

  defp summary_from_findings("block", findings),
    do: "Blocked #{length(findings)} finding(s): " <> categories_summary(findings)

  defp summary_from_findings("warn", findings),
    do: "Warnings detected (#{length(findings)}): " <> categories_summary(findings)

  defp summary_from_findings(_decision, _findings), do: "No issues detected."

  defp categories_summary(findings) do
    findings
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp final_decision({:ok, budget}, findings) do
    final_decision_from_list([budget["decision"] | Enum.map(findings, & &1.decision)])
  end

  defp final_decision(_budget, findings),
    do: final_decision_from_list(Enum.map(findings, & &1.decision))

  defp final_decision_from_list(decisions) do
    cond do
      "block" in decisions -> "block"
      "warn" in decisions -> "warn"
      true -> "allow"
    end
  end

  defp uniq_findings(findings) do
    Enum.uniq_by(findings, fn finding ->
      {finding.rule_id, finding.metadata["matched_text_redacted"], finding.location["path"]}
    end)
  end

  defp empty_result,
    do: %Scanner.Result{
      allowed: true,
      decision: "allow",
      summary: "No issues detected.",
      findings: [],
      scanned_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

  defp estimated_cost({:ok, estimate}), do: estimate["estimated_cost_cents"]
  defp estimated_cost(_preflight), do: 0
end
