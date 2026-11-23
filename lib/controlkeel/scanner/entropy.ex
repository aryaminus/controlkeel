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
        |> Enum.reject(&benign_code_or_path_token?(content, &1))
        |> Enum.reject(&inline_data_uri_payload?(content, &1))
        |> Enum.map(&finding_from_candidate(rule, input, &1))

      _rule ->
        []
    end)
  end

  defp entropy(value) when is_binary(value) and value != "" do
    value
    |> String.to_charlist()
    |> Enum.frequencies()
    |> Enum.reduce(0.0, fn {_char, count}, acc ->
      probability = count / byte_size(value)
      acc - probability * :math.log2(probability)
    end)
  end

  defp entropy(_value), do: 0.0

  defp high_entropy?(value, threshold) do
    entropy(value) >= threshold and
      String.match?(value, ~r/[A-Za-z]/) and
      String.match?(value, ~r/[0-9]/)
  end

  defp inline_data_uri_payload?(content, candidate) do
    pattern = ~r/data:image\/[a-z0-9.+-]+;base64,#{Regex.escape(candidate)}/i
    Regex.match?(pattern, content)
  end

  defp benign_code_or_path_token?(content, candidate) do
    identifier_with_optional_arity?(candidate) or
      migration_path?(content, candidate) or
      url_path_fragment?(content, candidate) or
      plain_path_value?(content, candidate)
  end

  # The candidate may carry a `NAME=` prefix, since `=` is in the candidate
  # alphabet. Judge the name and the path value separately.
  defp plain_path_value?(content, candidate) do
    {name, value} =
      case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_]*)=(.+)$/, candidate) do
        [_, name, value] -> {name, value}
        _ -> {nil, candidate}
      end

    word_path?(value) and not (is_binary(name) and credential_name?(name)) and
      not credential_context?(content, candidate)
  end

  # The candidate is an auth scheme value (`Bearer <x>`) or is assigned to a
  # credential-named key (`GITHUB_TOKEN=<x>`, `"secret": "<x>"`). A keyword
  # inside some other argument, such as a `secret_scan.py` script, does not
  # count.
  defp credential_context?(content, candidate) do
    escaped = Regex.escape(candidate)

    Regex.match?(~r/\b(?:bearer|basic)\s+["']?#{escaped}/i, content) or
      credential_flag_value?(content, escaped) or
      credential_assignment?(content, escaped)
  end

  # `GITHUB_TOKEN=<x>` or `"secret": "<x>"`, but not `PASSWORD_FILE=<path>`.
  defp credential_assignment?(content, escaped) do
    ~r/([A-Za-z0-9_-]+)["']?\s*[:=]\s*["']?#{escaped}/
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.any?(&credential_name?/1)
  end

  defp credential_name?(name) do
    Regex.match?(~r/token|secret|password|passwd|pass|api[_-]?key|auth/i, name) and
      not Regex.match?(~r/(?:file|path|dir)$/i, name)
  end

  # `--password <x>`, `--api-key=<x>` and similar. Flags that take a file or
  # directory (`--password-file`, `--token-path`) carry a path, not a secret.
  defp credential_flag_value?(content, escaped) do
    ~r/(?:^|\s)(--?[A-Za-z0-9_-]+)(?:\s+|=)["']?#{escaped}/
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.any?(&credential_name?/1)
  end

  # API or file paths made of plain words, plain numbers and UUIDs, such as a
  # GitHub `pulls/<n>/comments` path or a session directory. Words must be
  # lowercase, Capitalized or UPPERCASE; base64 secrets mix case and digits
  # inside a run, so they don't take this shape. A candidate right after a
  # credential keyword is never treated as a path.
  defp word_path?(candidate) do
    segments = String.split(candidate, "/", trim: true)
    length(segments) >= 3 and Enum.all?(segments, &path_segment?/1)
  end

  defp path_segment?(segment) do
    Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, segment) or
      segment
      |> String.split(["-", "_", "."], trim: true)
      |> Enum.all?(&Regex.match?(~r/^(?:[A-Z]?[a-z]+|[A-Z]{1,8}|\d+)$/, &1))
  end

  defp migration_path?(content, candidate) do
    Regex.match?(
      ~r/^(?:[A-Za-z0-9_-]+\/)*priv\/repo\/migrations\/[0-9]{14}_[a-z0-9_]+$/,
      candidate
    ) and
      String.contains?(content, candidate <> ".exs")
  end

  defp identifier_with_optional_arity?(candidate) do
    Regex.match?(~r/^[a-z][a-z0-9_]*(?:\/\d+)?$/, candidate)
  end

  defp url_path_fragment?(content, candidate) do
    String.contains?(candidate, "/") and
      Regex.match?(~r/^[A-Za-z0-9_.\/-]+$/, candidate) and
      Regex.match?(~r/https?:\/\/[A-Za-z0-9_.\/-]*#{Regex.escape(candidate)}/, content)
  end

  defp finding_from_candidate(rule, input, candidate) do
    redacted = Finding.redact(candidate)

    %Finding{
      id: fingerprint(rule.id, redacted, input),
      severity: rule.severity,
      category: rule.category,
      rule_id: rule.id,
      decision: Finding.action_to_decision(rule.action),
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
end
