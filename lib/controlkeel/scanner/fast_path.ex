defmodule ControlKeel.Scanner.FastPath do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Policy.Rule
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.{Advisory, Entropy, Patterns, Semgrep}

  @type input :: map()

  def scan(input, _opts \\ []) when is_map(input) do
    normalized = normalize_input(input)
    baseline_rules = PackLoader.load!("baseline")
    cost_rules = PackLoader.load!("cost")

    layer1 =
      []
      |> Kernel.++(Patterns.detect(normalized["content"], normalized, baseline_rules))
      |> Kernel.++(Entropy.detect(normalized["content"], normalized, baseline_rules))
      |> Kernel.++(budget_findings(normalized, cost_rules))
      |> uniq_findings()

    layer2 =
      if Semgrep.available?() and Semgrep.code_like?(normalized, force: layer1 != []) do
        case Semgrep.scan(normalized, force: layer1 != [], timeout_ms: 5_000) do
          {:ok, %{findings: sf}} -> sf
          _ -> []
        end
      else
        []
      end

    combined = uniq_findings(layer1 ++ layer2)

    layer3 = Advisory.scan(normalized, combined)

    build_result(uniq_findings(combined ++ layer3))
  end

  defp normalize_input(input) do
    %{
      "content" => Map.get(input, "content", Map.get(input, :content, "")),
      "path" => Map.get(input, "path", Map.get(input, :path)),
      "kind" => Map.get(input, "kind", Map.get(input, :kind, "code")),
      "session_id" => Map.get(input, "session_id", Map.get(input, :session_id)),
      "task_id" => Map.get(input, "task_id", Map.get(input, :task_id))
    }
  end

  defp budget_findings(%{"session_id" => nil}, _rules), do: []

  defp budget_findings(%{"session_id" => session_id, "kind" => kind, "path" => path}, rules) do
    case Mission.get_session(session_id) do
      nil ->
        []

      session ->
        budget_cents = session.budget_cents || 0
        spent_cents = session.spent_cents || 0

        if budget_cents <= 0 do
          []
        else
          ratio = spent_cents / budget_cents

          rules
          |> Enum.filter(fn %Rule{matcher: %{"type" => "budget", "ratio_gte" => threshold}} ->
            ratio >= threshold
          end)
          |> Enum.map(fn rule ->
            %Scanner.Finding{
              id: budget_fingerprint(rule.id, session.id, spent_cents, budget_cents),
              severity: rule.severity,
              category: rule.category,
              rule_id: rule.id,
              decision: action_to_decision(rule.action),
              plain_message: rule.plain_message,
              location: %{"path" => path, "kind" => kind},
              metadata: %{
                "scanner" => "fast_path",
                "matcher" => "budget",
                "spent_cents" => spent_cents,
                "budget_cents" => budget_cents,
                "budget_ratio" => Float.round(ratio, 3)
              }
            }
          end)
        end
    end
  end

  defp build_result([]) do
    %Scanner.Result{
      allowed: true,
      decision: "allow",
      summary: "No issues detected.",
      findings: [],
      scanned_at: scanned_at()
    }
  end

  defp build_result(findings) do
    decision = findings |> Enum.map(& &1.decision) |> final_decision()

    %Scanner.Result{
      allowed: decision != "block",
      decision: decision,
      summary: summary_for(decision, findings),
      findings: findings,
      scanned_at: scanned_at()
    }
  end

  defp summary_for("block", findings),
    do: "Blocked #{length(findings)} finding(s): " <> categories_summary(findings)

  defp summary_for("warn", findings),
    do: "Warnings detected (#{length(findings)}): " <> categories_summary(findings)

  defp summary_for(_decision, _findings), do: "No issues detected."

  defp categories_summary(findings) do
    findings
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp final_decision(decisions) do
    cond do
      "block" in decisions -> "block"
      "warn" in decisions -> "warn"
      true -> "allow"
    end
  end

  defp uniq_findings(findings) do
    findings
    |> Enum.uniq_by(fn finding ->
      {finding.rule_id, finding.metadata["matched_text_redacted"],
       finding.metadata["budget_ratio"]}
    end)
  end

  defp scanned_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp budget_fingerprint(rule_id, session_id, spent_cents, budget_cents) do
    seed = "#{rule_id}:#{session_id}:#{spent_cents}:#{budget_cents}"
    "fp_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp action_to_decision("block"), do: "block"
  defp action_to_decision("warn"), do: "warn"
  defp action_to_decision("escalate_to_human"), do: "warn"
  defp action_to_decision(_action), do: "allow"
end
