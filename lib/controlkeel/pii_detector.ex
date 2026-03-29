defmodule ControlKeel.PIIDetector do
  @moduledoc """
  Lightweight PII detection for governance checks.

  Supports common PII types via regex patterns. For production use,
  consider integrating with dedicated PII detection services (Microsoft Presidio,
  AWS Comprehend, Google DLP, or PromptShield's detection engine).

  Actions: :block, :mask, :allow
  """

  @type pii_type :: :credit_card | :ssn | :email | :phone | :ip_address | :iban | :custom
  @type action :: :block | :mask | :allow

  @default_rules [
    %{
      type: :credit_card,
      pattern: ~r/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
      action: :block
    },
    %{type: :ssn, pattern: ~r/\b\d{3}[\s-]?\d{2}[\s-]?\d{4}\b/, action: :block},
    %{
      type: :email,
      pattern: ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      action: :mask
    },
    %{type: :phone, pattern: ~r/\b\d{3}[\s.-]?\d{3}[\s.-]?\d{4}\b/, action: :mask},
    %{type: :ip_address, pattern: ~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, action: :mask},
    %{type: :iban, pattern: ~r/\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b/, action: :block}
  ]

  @doc """
  Detect PII in text and return findings with recommended actions.

  ## Options
    - `:rules` - Custom detection rules (default: built-in rules)
    - `:min_confidence` - Minimum confidence threshold (0.0-1.0, default: 0.7)
    - `:action_override` - Override all detections to a specific action

  ## Returns
      {:ok, %{findings: [...], action: :block | :mask | :allow}}
  """
  @spec scan(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def scan(text, opts \\ []) when is_binary(text) do
    rules = Keyword.get(opts, :rules, @default_rules)
    action_override = Keyword.get(opts, :action_override)

    findings =
      Enum.flat_map(rules, fn rule ->
        detect_matches(text, rule, action_override)
      end)

    action = determine_action(findings, action_override)

    {:ok, %{findings: findings, action: action}}
  end

  @doc """
  Scan prompt before execution. Returns findings for governance review.
  """
  @spec scan_prompt(String.t(), keyword()) :: {:ok, map()}
  def scan_prompt(prompt, opts \\ []) do
    scan(prompt, opts)
  end

  @doc """
  Scan response after execution. Useful for detecting PII leakage.
  """
  @spec scan_response(String.t(), keyword()) :: {:ok, map()}
  def scan_response(response, opts \\ []) do
    scan(response, opts)
  end

  @doc """
  Check if text should be blocked based on PII findings.
  """
  @spec blocked?(String.t(), keyword()) :: boolean()
  def blocked?(text, opts \\ []) do
    case scan(text, opts) do
      {:ok, %{action: :block}} -> true
      _ -> false
    end
  end

  @doc """
  Mask PII in text with entity type placeholders.
  """
  @spec mask_pii(String.t(), keyword()) :: String.t()
  def mask_pii(text, opts \\ []) when is_binary(text) do
    rules = Keyword.get(opts, :rules, @default_rules)

    Enum.reduce(rules, text, fn rule, acc ->
      replacement = "[#{String.upcase(to_string(rule.type))}]"
      Regex.replace(rule.pattern, acc, replacement, global: true)
    end)
  end

  @doc """
  Return supported PII types.
  """
  @spec supported_types() :: [pii_type()]
  def supported_types do
    [:credit_card, :ssn, :email, :phone, :ip_address, :iban]
  end

  defp detect_matches(text, rule, action_override) do
    rule.pattern
    |> Regex.scan(text)
    |> Enum.map(fn [full_match | _] ->
      %{
        type: rule.type,
        value: if(rule.action == :allow, do: full_match, else: "[REDACTED]"),
        action: action_override || rule.action
      }
    end)
  end

  defp determine_action(findings, nil) do
    if Enum.any?(findings, &(&1.action == :block)) do
      :block
    else
      :allow
    end
  end

  defp determine_action(_, action_override), do: action_override
end
