defmodule ControlKeel.Intent.Providers.OpenAI do
  @moduledoc false

  @behaviour ControlKeel.Intent.Provider

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  def compile(prompt, opts) do
    config = provider_config(opts)

    with {:ok, api_key} <- resolve_api_key(config),
         {:ok, response} <- request(prompt, api_key, config),
         {:ok, brief_map, payload} <- decode_brief(response.body) do
      {:ok, brief_map, %{"model" => payload["model"] || config[:model]}}
    end
  end

  defp request(prompt, api_key, config) do
    case responses_request(prompt, api_key, config) do
      {:fallback, :chat_completions} -> chat_completions_request(prompt, api_key, config)
      other -> other
    end
  end

  defp responses_request(prompt, api_key, config) do
    Req.post(
      url: endpoint_url(config[:base_url], "/v1/responses"),
      headers: request_headers(api_key),
      json: %{
        "model" => config[:model],
        "input" => prompt.user,
        "instructions" => prompt.system,
        "text" => %{
          "format" => %{
            "type" => "json_schema",
            "name" => "execution_brief",
            "schema" => ExecutionBrief.provider_schema(),
            "strict" => true
          }
        }
      }
    )
    |> normalize_response(config, :responses)
  end

  defp chat_completions_request(prompt, api_key, config) do
    Req.post(
      url: endpoint_url(config[:base_url], "/v1/chat/completions"),
      headers: request_headers(api_key),
      json: %{
        "model" => config[:model],
        "messages" => [
          %{"role" => "system", "content" => chat_completion_system_prompt(prompt.system)},
          %{"role" => "user", "content" => prompt.user}
        ],
        "response_format" => %{"type" => "json_object"}
      }
    )
    |> normalize_response(config, :chat_completions)
  end

  defp extract_content(%{"output_text" => content}) when is_binary(content), do: {:ok, content}

  defp extract_content(payload) do
    content =
      get_in(payload, ["output", Access.at(0), "content", Access.at(0), "text"]) ||
        get_in(payload, ["choices", Access.at(0), "message", "content"])

    if is_binary(content), do: {:ok, content}, else: {:error, :invalid_response}
  end

  defp decode_brief(body) do
    with {:ok, payload} <- Jason.decode(body),
         {:ok, content} <- extract_content(payload),
         {:ok, brief_map} <- Jason.decode(content) do
      {:ok, brief_map, payload}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      other -> other
    end
  end

  defp provider_config(opts) do
    base =
      normalize_opts(Application.get_env(:controlkeel, Intent, [])[:providers][:openai] || [])

    override = normalize_opts(opts[:provider_config])
    Keyword.merge(base, override)
  end

  defp normalize_opts(nil), do: []
  defp normalize_opts(value) when is_list(value), do: value
  defp normalize_opts(value) when is_map(value), do: Enum.into(value, [])
  defp normalize_opts(_value), do: []

  defp resolve_api_key(config) do
    case config[:api_key] do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        if auth_optional?(config) do
          {:ok, nil}
        else
          {:skip, :unconfigured}
        end
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status} = response}, _config, _endpoint)
       when status in 200..299,
       do: {:ok, response}

  defp normalize_response({:ok, %Req.Response{status: status}}, _config, _endpoint)
       when status in [401, 403],
       do: {:skip, :unauthorized}

  defp normalize_response(
         {:ok, %Req.Response{status: status}},
         config,
         :responses
       )
       when status in [400, 404, 405, 422, 501] do
    if openai_compatible_fallback?(config) do
      {:fallback, :chat_completions}
    else
      {:error, :invalid_response}
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}, _config, _endpoint),
    do: {:error, "openai_request_failed_#{status}: #{inspect(body)}"}

  defp normalize_response({:error, _reason}, config, :responses) do
    if openai_compatible_fallback?(config) do
      {:fallback, :chat_completions}
    else
      {:skip, :unavailable}
    end
  end

  defp normalize_response({:error, _reason}, _config, _endpoint), do: {:skip, :unavailable}

  defp request_headers(api_key) do
    auth_headers(api_key) ++ [{"content-type", "application/json"}]
  end

  defp auth_headers(api_key) when is_binary(api_key) and api_key != "" do
    [{"authorization", "Bearer #{api_key}"}]
  end

  defp auth_headers(_api_key), do: []

  defp chat_completion_system_prompt(system_prompt) do
    system_prompt <>
      "\nReturn only a JSON object. Match this schema exactly: " <>
      Jason.encode!(ExecutionBrief.provider_schema())
  end

  defp endpoint_url(base_url, path) do
    base =
      base_url
      |> to_string()
      |> String.trim()
      |> String.trim_trailing("/")

    if String.ends_with?(base, "/v1") and String.starts_with?(path, "/v1/") do
      base <> String.trim_leading(path, "/v1")
    else
      base <> path
    end
  end

  defp auth_optional?(config) do
    openai_compatible_fallback?(config)
  end

  defp openai_compatible_fallback?(config) do
    case config[:base_url] do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.trim_trailing("/")
        |> String.replace_suffix("/v1", "")
        |> case do
          "" -> false
          "https://api.openai.com" -> false
          _ -> true
        end

      _ ->
        false
    end
  end
end
