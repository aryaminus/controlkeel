defmodule ControlKeel.Scanner.Advisory do
  @moduledoc """
  Layer 3 scanner: calls a configured LLM provider to review content
  and existing findings for issues that pattern matching misses.

  Only runs when a provider API key is present. Fails silently on
  timeout or LLM errors — it never blocks a scan result.
  """

  alias ControlKeel.ProviderBroker
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
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    if enabled?() and String.length(content) > 30 do
      timeout = Keyword.get(opts, :timeout_ms, @timeout_ms)

      case call_provider(input, existing_findings, timeout, project_root) do
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

  @doc """
  Summarizes advisory participation for API responses (FastPath / validate).

  `layer3_findings` is the list returned by `scan/3` for this input.
  """
  def advisory_status(input, layer3_findings, project_root \\ File.cwd!()) do
    content = input["content"] || ""
    config = Application.get_env(:controlkeel, :advisory, [])
    explicit = Keyword.get(config, :enabled)

    cond do
      explicit == false ->
        %{status: "disabled", detail: "Advisory disabled via application config."}

      String.length(content) <= 30 ->
        %{status: "skipped_short_content", detail: "Content shorter than advisory minimum."}

      ProviderBroker.advisory_chain(project_root) == [] ->
        %{
          status: "skipped_no_provider",
          detail: "No LLM provider configured; pattern scanners completed."
        }

      layer3_findings != [] ->
        %{status: "ran", extra_findings: length(layer3_findings)}

      true ->
        %{status: "ran_empty", detail: "Advisory ran; no additional issues reported."}
    end
  end

  # ─── Provider dispatch ───────────────────────────────────────────────────────

  defp call_provider(input, existing_findings, timeout, project_root) do
    providers = configured_providers(project_root)

    Enum.reduce_while(providers, {:error, :no_provider}, fn resolution, _acc ->
      case call(resolution, input, existing_findings, timeout) do
        {:ok, _} = ok -> {:halt, ok}
        {:error, _} -> {:cont, {:error, :all_providers_failed}}
      end
    end)
  end

  defp call(%{provider: "anthropic", config: config}, input, existing_findings, timeout) do
    config = normalize_config(config)
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

  defp call(%{provider: "openai", config: config}, input, existing_findings, timeout) do
    config = normalize_config(config)
    prompt = build_prompt(input, existing_findings)

    with {:ok, api_key} <- require_openai_key(config),
         {:ok, body} <-
           Req.post(
             url:
               endpoint_url(config[:base_url] || "https://api.openai.com", "/v1/chat/completions"),
             headers: openai_headers(api_key),
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

  defp call(_resolution, _input, _existing_findings, _timeout), do: {:error, :unavailable}

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

  defp configured_providers(project_root) do
    ProviderBroker.advisory_chain(project_root)
  end

  defp enabled? do
    advisory_cfg = Application.get_env(:controlkeel, :advisory, [])
    explicit = Keyword.get(advisory_cfg, :enabled)

    cond do
      explicit == false -> false
      explicit == true -> true
      # Default: enable when a provider key is present
      true -> configured_providers(File.cwd!()) != []
    end
  end

  defp normalize_config(config) when is_list(config), do: config
  defp normalize_config(config) when is_map(config), do: Enum.into(config, [])
  defp normalize_config(_config), do: []

  defp require_key(config) do
    case config[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :skip}
    end
  end

  defp require_openai_key(config) do
    case config[:api_key] do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        if custom_openai_base_url?(config[:base_url]), do: {:ok, nil}, else: {:error, :skip}
    end
  end

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

  defp openai_headers(api_key) when is_binary(api_key) and api_key != "" do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  defp openai_headers(_api_key), do: [{"content-type", "application/json"}]

  defp endpoint_url(base_url, path) do
    base =
      base_url
      |> String.trim()
      |> String.trim_trailing("/")

    if String.ends_with?(base, "/v1") and String.starts_with?(path, "/v1/") do
      base <> String.trim_leading(path, "/v1")
    else
      base <> path
    end
  end

  defp custom_openai_base_url?(base_url) when is_binary(base_url) do
    base_url
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.replace_suffix("/v1", "")
    |> case do
      "" -> false
      "https://api.openai.com" -> false
      _ -> true
    end
  end

  defp custom_openai_base_url?(_base_url), do: false

  defp emit_telemetry(status, count) do
    :telemetry.execute(
      [:controlkeel, :scanner, :advisory],
      %{count: count},
      %{status: to_string(status)}
    )
  end
end
