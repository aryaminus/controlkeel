defmodule ControlKeel.Scanner.Entropy do
  @moduledoc false

  alias ControlKeel.Policy.Rule
  alias ControlKeel.Scanner.Finding

  def detect(content, input, rules) when is_binary(content) and is_list(rules) do
    Enum.flat_map(rules, fn
      %Rule{matcher: %{"type" => "entropy"} = matcher} = rule ->
        candidate_pattern = Map.get(matcher, "candidate_pattern", "[A-Za-z0-9_\\-=/+]{20,}")
        min_length = Map.get(matcher, "min_length", 20)
        threshold = Map.get(matcher, "threshold", 3.5)

        content
        |> then(&Regex.scan(Regex.compile!(candidate_pattern), &1))
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.filter(&(byte_size(&1) >= min_length))
        |> Enum.filter(&high_entropy?(&1, threshold))
        |> Enum.map(&finding_from_candidate(rule, input, &1))

      _rule ->
        []
    end)
  end

  def entropy(value) when is_binary(value) and value != "" do
    value
    |> String.to_charlist()
    |> Enum.frequencies()
    |> Enum.reduce(0.0, fn {_char, count}, acc ->
      probability = count / byte_size(value)
      acc - probability * :math.log2(probability)
    end)
  end

  def entropy(_value), do: 0.0

  defp high_entropy?(value, threshold) do
    entropy(value) >= threshold and
      String.match?(value, ~r/[A-Za-z]/) and
      String.match?(value, ~r/[0-9]/)
  end

  defp finding_from_candidate(rule, input, candidate) do
    redacted = redact(candidate)

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
        "matcher" => "entropy",
        "matched_text_redacted" => redacted,
        "entropy" => Float.round(entropy(candidate), 3)
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
