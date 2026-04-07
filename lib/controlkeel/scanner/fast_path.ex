defmodule ControlKeel.Scanner.FastPath do
  @moduledoc false

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Policy.Rule
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.{Advisory, Entropy, Patterns, Semgrep}
  alias ControlKeel.TrustBoundary

  @type input :: map()
  @destructive_shell_patterns [
    %{
      id: "destructive.shell.git_checkout_repo_wide",
      regex: ~r/\bgit\s+checkout\s+--\s+\./,
      message:
        "Repo-wide `git checkout -- .` can discard tracked work across the entire project.",
      recovery:
        "Scope the checkout to an explicit path, create a checkpoint first, and capture a diff before mutating files."
    },
    %{
      id: "destructive.shell.git_restore_repo_wide",
      regex: ~r/\bgit\s+restore(?:\s+--(?:source|staged)\b[^\n;|&]*)?\s+\./,
      message: "Repo-wide `git restore .` can discard tracked work across the entire project.",
      recovery:
        "Restore only the file or directory you intend to reset, and checkpoint uncommitted work first."
    },
    %{
      id: "destructive.shell.git_reset_hard",
      regex: ~r/\bgit\s+reset\s+--hard(?:\s+\S+)?/,
      message: "`git reset --hard` can irreversibly discard both index and working tree changes.",
      recovery:
        "Prefer a checkpoint or `git diff` capture first, and limit reset operations to a reviewed recovery path."
    },
    %{
      id: "destructive.shell.git_clean_force",
      regex: ~r/\bgit\s+clean\b(?=[^\n;|&]*-f)(?=[^\n;|&]*d)[^\n;|&]*/,
      message:
        "`git clean -fd` style cleanup can delete untracked files and generated artifacts with no rollback.",
      recovery:
        "Use `git clean -nd` first, checkpoint untracked files, and scope cleanup paths explicitly."
    },
    %{
      id: "destructive.shell.rm_rf_repo_scope",
      regex:
        Regex.compile!(
          "\\brm\\s+-rf\\b[^\\n;|&]*(?:\\s+\\*|\\s+\\./|\\s+\\.\\b|\\s+\\.[/][^;\\n|&]*|\\s+/)"
        ),
      message:
        "Broad `rm -rf` scope can remove large parts of the repo or filesystem in a single step.",
      recovery:
        "Delete only the reviewed path, prefer dry-run listing first, and checkpoint before destructive cleanup."
    }
  ]

  def scan(input, _opts \\ []) when is_map(input) do
    normalized = normalize_input(input)
    baseline_rules = PackLoader.load!("baseline")
    domain_rules = domain_rules_for(normalized)
    workspace_rules = workspace_rules_for(normalized)
    cost_rules = PackLoader.load!("cost")
    runtime_rules = uniq_rules(baseline_rules ++ domain_rules ++ workspace_rules)

    layer1 =
      []
      |> Kernel.++(Patterns.detect(normalized["content"], normalized, runtime_rules))
      |> Kernel.++(Entropy.detect(normalized["content"], normalized, runtime_rules))
      |> Kernel.++(budget_findings(normalized, cost_rules))
      |> Kernel.++(destructive_shell_findings(normalized))
      |> Kernel.++(trust_boundary_findings(normalized))
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
    merged = uniq_findings(combined ++ layer3)
    advisory = Advisory.advisory_status(normalized, layer3)

    build_result(merged, advisory)
  end

  defp normalize_input(input) do
    %{
      "content" => Map.get(input, "content", Map.get(input, :content, "")),
      "path" => Map.get(input, "path", Map.get(input, :path)),
      "kind" => Map.get(input, "kind", Map.get(input, :kind, "code")),
      "session_id" =>
        normalize_optional_integer(Map.get(input, "session_id", Map.get(input, :session_id))),
      "task_id" =>
        normalize_optional_integer(Map.get(input, "task_id", Map.get(input, :task_id))),
      "domain_pack" => normalize_domain_pack(input)
    }
    |> Map.merge(TrustBoundary.normalize_validation_context(input))
  end

  defp domain_rules_for(%{"domain_pack" => nil}), do: []

  defp domain_rules_for(%{"domain_pack" => domain_pack}) do
    if Domains.supported_pack?(domain_pack) do
      PackLoader.load!(domain_pack)
    else
      []
    end
  end

  defp normalize_domain_pack(input) do
    direct =
      Map.get(input, "domain_pack") ||
        Map.get(input, :domain_pack)

    case normalize_supported_pack(direct) do
      nil ->
        input
        |> Map.get("session_id", Map.get(input, :session_id))
        |> session_domain_pack()

      pack ->
        pack
    end
  end

  defp normalize_supported_pack(nil), do: nil

  defp normalize_supported_pack(value) do
    pack = Domains.normalize_pack(value, "__unsupported__")
    if Domains.supported_pack?(pack), do: pack, else: nil
  end

  defp session_domain_pack(nil), do: nil

  defp session_domain_pack(session_id) do
    case Mission.get_session(session_id) do
      nil ->
        nil

      session ->
        (session.execution_brief || %{})
        |> Map.get("domain_pack")
        |> normalize_supported_pack()
    end
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

  defp workspace_rules_for(%{"session_id" => nil}), do: []

  defp workspace_rules_for(%{"session_id" => session_id}) do
    Platform.session_policy_rules(session_id)
  end

  defp trust_boundary_findings(normalized) do
    {_context, findings} = TrustBoundary.findings_for_validation(normalized)
    findings
  end

  defp destructive_shell_findings(%{"kind" => "shell", "content" => content} = normalized)
       when is_binary(content) do
    @destructive_shell_patterns
    |> Enum.flat_map(fn pattern ->
      case Regex.run(pattern.regex, content) do
        nil ->
          []

        [match | _rest] ->
          [
            destructive_shell_finding(
              pattern.id,
              pattern.message,
              match,
              normalized,
              pattern.recovery
            )
          ]
      end
    end)
  end

  defp destructive_shell_findings(_normalized), do: []

  defp destructive_shell_finding(rule_id, message, matched_command, normalized, recovery) do
    %Scanner.Finding{
      id: shell_fingerprint(rule_id, normalized["path"], matched_command),
      severity: "critical",
      category: "destructive_operation",
      rule_id: rule_id,
      decision: "block",
      plain_message: message,
      location: %{"path" => normalized["path"], "kind" => normalized["kind"]},
      metadata: %{
        "scanner" => "fast_path",
        "matcher" => "destructive_shell",
        "matched_text_redacted" => "[redacted]",
        "checkpoint_recommended" => true,
        "requires_human_review" => true,
        "recovery_guidance" => recovery,
        "rollback_hint" =>
          "Pause, create a checkpoint or proof-backed snapshot, and prefer an explicit path-scoped revert over repo-wide cleanup.",
        "safe_alternative" =>
          "Use a dry-run and an explicit path instead of a repo-wide destructive command."
      }
    }
  end

  defp build_result(findings, advisory)

  defp build_result([], advisory) do
    %Scanner.Result{
      allowed: true,
      decision: "allow",
      summary: "No issues detected.",
      findings: [],
      scanned_at: scanned_at(),
      advisory: advisory
    }
  end

  defp build_result(findings, advisory) do
    decision = findings |> Enum.map(& &1.decision) |> final_decision()

    %Scanner.Result{
      allowed: decision != "block",
      decision: decision,
      summary: summary_for(decision, findings),
      findings: findings,
      scanned_at: scanned_at(),
      advisory: advisory
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

  defp uniq_rules(rules) do
    Enum.uniq_by(rules, & &1.id)
  end

  defp normalize_optional_integer(nil), do: nil
  defp normalize_optional_integer(value) when is_integer(value), do: value

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_optional_integer(_value), do: nil

  defp scanned_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp budget_fingerprint(rule_id, session_id, spent_cents, budget_cents) do
    seed = "#{rule_id}:#{session_id}:#{spent_cents}:#{budget_cents}"
    "fp_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp shell_fingerprint(rule_id, path, matched_command) do
    seed = "#{rule_id}:#{path}:#{matched_command}"
    "fp_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp action_to_decision("block"), do: "block"
  defp action_to_decision("warn"), do: "warn"
  defp action_to_decision("escalate_to_human"), do: "warn"
  defp action_to_decision(_action), do: "allow"
end
