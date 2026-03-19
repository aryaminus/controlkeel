defmodule ControlKeel.Scanner.Advisory do
  @moduledoc """
  Layer 3 scanner: calls a configured LLM provider to review content
  and existing findings for issues that pattern matching misses.

  Only runs when a provider API key is present. Fails silently on
  timeout or LLM errors — it never blocks a scan result.
  """

  alias ControlKeel.Intent
  alias ControlKeel.Scanner.Finding

  @timeout_ms 8_000
  @max_content_chars 5_000
  @json_extract ~r/\[\s*\{[\s\S]*?\}\s*\]/

  @doc """
  Returns a list of additional `Scanner.Finding` structs beyond what
  FastPath and Semgrep already found. Returns `[]` when no provider
  is configured or when the call times out.
  """
  def scan(input, existing_findings, opts \\ []) do
    content = input["content"] || ""

    if enabled?() and String.length(content) > 30 do
      timeout = Keyword.get(opts, :timeout_ms, @timeout_ms)

      case call_provider(input, existing_findings, timeout) do
        {:ok, findings} ->
          emit_telemetry(:ok, length(findings))
          findings

        {:error, reason} ->
          emit_telemetry(reason, 0)
          []
      end
    else
      []
    end
  end

  # ─── Provider dispatch ───────────────────────────────────────────────────────

  defp call_provider(input, existing_findings, timeout) do
    providers = configured_providers()

    Enum.reduce_while(providers, {:error, :no_provider}, fn {name, config}, _acc ->
      case call(name, config, input, existing_findings, timeout) do
        {:ok, _} = ok -> {:halt, ok}
        {:error, _} -> {:cont, {:error, :all_providers_failed}}
      end
    end)
  end

  defp call(:anthropic, config, input, existing_findings, timeout) do
    prompt = build_prompt(input, existing_findings)

    with {:ok, api_key} <- require_key(config),
         {:ok, body} <-
           Req.post(
             url: (config[:base_url] || "https://api.anthropic.com") <> "/v1/messages",
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"},
               {"content-type", "application/json"}
             ],
             json: %{
               "model" => config[:model] || "claude-haiku-4-5-20251001",
               "max_tokens" => 600,
               "system" => prompt.system,
               "messages" => [%{"role" => "user", "content" => prompt.user}]
             },
             receive_timeout: timeout
           )
           |> normalize_resp(),
         {:ok, text} <- extract_text(body) do
      parse_findings(text, input)
    end
  end

  defp call(:openai, config, input, existing_findings, timeout) do
    prompt = build_prompt(input, existing_findings)

    with {:ok, api_key} <- require_key(config),
         {:ok, body} <-
           Req.post(
             url: (config[:base_url] || "https://api.openai.com") <> "/v1/chat/completions",
             headers: [
               {"authorization", "Bearer #{api_key}"},
               {"content-type", "application/json"}
             ],
             json: %{
               "model" => config[:model] || "gpt-4o-mini",
               "max_tokens" => 600,
               "messages" => [
                 %{"role" => "system", "content" => prompt.system},
                 %{"role" => "user", "content" => prompt.user}
               ],
               "response_format" => %{"type" => "json_object"}
             },
             receive_timeout: timeout
           )
           |> normalize_resp(),
         {:ok, text} <- extract_openai_text(body) do
      parse_findings(text, input)
    end
  end

  # ─── Prompt ──────────────────────────────────────────────────────────────────

  defp build_prompt(input, existing_findings) do
    content = String.slice(input["content"] || "", 0, @max_content_chars)
    path = input["path"] || "(unknown)"
    kind = input["kind"] || "code"

    already_found =
      case existing_findings do
        [] ->
          "None yet."

        findings ->
          findings
          |> Enum.map(&"- [#{&1.severity}] #{&1.rule_id}: #{&1.plain_message}")
          |> Enum.join("\n")
      end

    system = """
    You are a security code reviewer for an AI governance platform.
    Your job is to find security issues that regex and AST scanners miss.
    Respond with ONLY a valid JSON array. No prose. No markdown.
    If there are no additional issues, respond with [].

    Each finding object must have exactly these keys:
      rule_id     (string, use advisory.XXX prefix)
      severity    (one of: critical, high, medium, low)
      category    (one of: security, hygiene, logic, privacy)
      message     (plain language, max 120 chars, actionable)
      decision    (one of: block, warn, allow)
    """

    user = """
    File: #{path} (#{kind})

    Already detected by pattern scanner:
    #{already_found}

    Review the following content for additional security issues not already listed.
    Focus on: logic flaws, broken access control, unsafe data flows, \
    insecure defaults, privacy leaks, missing validation, \
    or architecture decisions that create security risk.

    Content:
    ```
    #{content}
    ```

    Respond with a JSON array of findings, or [] if nothing new.
    """

    %{system: String.trim(system), user: String.trim(user)}
  end

  # ─── Response parsing ────────────────────────────────────────────────────────

  defp parse_findings(text, input) do
    with {:ok, json} <- extract_json(text),
         {:ok, items} <- Jason.decode(json),
         items when is_list(items) <- items do
      findings =
        items
        |> Enum.filter(&valid_finding?/1)
        |> Enum.map(&to_finding(&1, input))

      {:ok, findings}
    else
      _ -> {:error, :parse_failed}
    end
  end

  defp extract_json(text) do
    cond do
      # Already looks like a JSON array
      String.starts_with?(String.trim(text), "[") ->
        {:ok, String.trim(text)}

      # JSON object wrapper like {"findings": [...]}
      String.starts_with?(String.trim(text), "{") ->
        case Jason.decode(String.trim(text)) do
          {:ok, map} when is_map(map) ->
            findings = map["findings"] || map["issues"] || map["results"] || []
            {:ok, Jason.encode!(findings)}

          _ ->
            {:error, :no_json}
        end

      # JSON array embedded in prose
      true ->
        case Regex.run(@json_extract, text) do
          [match | _] -> {:ok, match}
          nil -> {:error, :no_json}
        end
    end
  end

  defp valid_finding?(%{"rule_id" => r, "severity" => s, "message" => m})
       when is_binary(r) and is_binary(s) and is_binary(m),
       do: s in ~w(critical high medium low)

  defp valid_finding?(_), do: false

  defp to_finding(item, input) do
    rule_id = item["rule_id"] || "advisory.unknown"
    message = item["message"] || "Advisory finding."
    severity = item["severity"] || "medium"
    category = item["category"] || "security"
    decision = item["decision"] || "warn"

    fingerprint =
      "adv_" <>
        (:crypto.hash(:sha256, "#{rule_id}:#{message}:#{input["path"]}")
         |> Base.encode16(case: :lower)
         |> binary_part(0, 12))

    %Finding{
      id: fingerprint,
      severity: severity,
      category: category,
      rule_id: rule_id,
      decision: decision,
      plain_message: message,
      location: %{"path" => input["path"], "kind" => input["kind"]},
      metadata: %{"scanner" => "advisory", "source" => "llm"}
    }
  end

  # ─── Provider config ─────────────────────────────────────────────────────────

  defp configured_providers do
    providers = Application.get_env(:controlkeel, Intent, [])[:providers] || %{}

    [:anthropic, :openai]
    |> Enum.map(fn name -> {name, Map.get(providers, name)} end)
    |> Enum.reject(fn {_name, config} ->
      is_nil(config) or config[:api_key] in [nil, ""]
    end)
  end

  defp enabled? do
    advisory_cfg = Application.get_env(:controlkeel, :advisory, [])
    explicit = Keyword.get(advisory_cfg, :enabled)

    cond do
      explicit == false -> false
      explicit == true -> true
      # Default: enable when a provider key is present
      true -> configured_providers() != []
    end
  end

  defp require_key(%{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}
  defp require_key(_), do: {:error, :skip}

  defp normalize_resp({:ok, %{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp normalize_resp({:ok, %{status: status}}), do: {:error, {:http, status}}
  defp normalize_resp({:error, reason}), do: {:error, reason}

  defp extract_text(%{"content" => [%{"text" => text} | _]}), do: {:ok, text}

  defp extract_text(%{"content" => content}) when is_list(content) do
    case Enum.find_value(content, fn
           %{"type" => "text", "text" => t} -> t
           _ -> nil
         end) do
      nil -> {:error, :no_text}
      text -> {:ok, text}
    end
  end

  defp extract_text(_), do: {:error, :no_text}

  defp extract_openai_text(%{"choices" => [%{"message" => %{"content" => text}} | _]}),
    do: {:ok, text}

  defp extract_openai_text(_), do: {:error, :no_text}

  defp emit_telemetry(status, count) do
    :telemetry.execute(
      [:controlkeel, :scanner, :advisory],
      %{count: count},
      %{status: to_string(status)}
    )
  end
end
