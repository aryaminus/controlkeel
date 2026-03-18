defmodule ControlKeel.Scanner.Patterns do
  @moduledoc false

  alias ControlKeel.Policy.Rule
  alias ControlKeel.Scanner.Finding

  def detect(content, input, rules) when is_binary(content) and is_list(rules) do
    Enum.flat_map(rules, fn
      %Rule{matcher: %{"type" => "regex", "patterns" => patterns}} = rule ->
        detect_rule(content, input, rule, List.wrap(patterns))

      _rule ->
        []
    end)
  end

  defp detect_rule(content, input, rule, patterns) do
    patterns
    |> Enum.map(&Regex.compile!/1)
    |> Enum.reduce_while([], fn regex, acc ->
      case Regex.run(regex, content) do
        nil ->
          {:cont, acc}

        [match | _rest] ->
          {:halt, [finding_from_match(rule, input, match)]}
      end
    end)
  end

  defp finding_from_match(rule, input, match) do
    redacted = redact(match)

    %Finding{
      id: fingerprint(rule.id, redacted, input),
      severity: rule.severity,
      category: rule.category,
      rule_id: rule.id,
      decision: action_to_decision(rule.action),
      plain_message: rule.plain_message,
      location: %{
        "path" => Map.get(input, "path"),
        "kind" => Map.get(input, "kind", "code")
      },
      metadata: %{
        "scanner" => "fast_path",
        "matcher" => "regex",
        "matched_text_redacted" => redacted
      }
    }
  end

  defp fingerprint(rule_id, redacted, input) do
    seed =
      [rule_id, redacted, Map.get(input, "path"), Map.get(input, "kind")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    "fp_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp action_to_decision("block"), do: "block"
  defp action_to_decision("warn"), do: "warn"
  defp action_to_decision("escalate_to_human"), do: "warn"
  defp action_to_decision(_action), do: "allow"

  defp redact(value) when byte_size(value) <= 12, do: "[redacted]"

  defp redact(value) do
    prefix = binary_part(value, 0, 4)
    suffix = binary_part(value, byte_size(value) - 4, 4)
    prefix <> "..." <> suffix
  end
end
