defmodule ControlKeel.Intent.Providers.OpenRouter do
  @moduledoc false

  @behaviour ControlKeel.Intent.Provider

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  def compile(prompt, opts) do
    config = provider_config(opts)

    with {:ok, api_key} <- require_api_key(config),
         {:ok, response} <- request(prompt, api_key, config),
         {:ok, payload} <- Jason.decode(response.body),
         {:ok, content} <- extract_content(payload),
         {:ok, brief_map} <- Jason.decode(content) do
      {:ok, brief_map, %{"model" => payload["model"] || config[:model]}}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      other -> other
    end
  end

  defp request(prompt, api_key, config) do
    Req.post(
      url: config[:base_url] <> "/api/v1/chat/completions",
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      json: %{
        "model" => config[:model],
        "messages" => [
          %{"role" => "system", "content" => prompt.system},
          %{"role" => "user", "content" => prompt.user}
        ],
        "response_format" => %{
          "type" => "json_schema",
          "json_schema" => %{
            "name" => "execution_brief",
            "strict" => true,
            "schema" => ExecutionBrief.provider_schema()
          }
        }
      }
    )
    |> normalize_response()
  end

  defp extract_content(payload) do
    content = get_in(payload, ["choices", Access.at(0), "message", "content"])
    if is_binary(content), do: {:ok, content}, else: {:error, :invalid_response}
  end

  defp provider_config(opts) do
    base =
      normalize_opts(Application.get_env(:controlkeel, Intent, [])[:providers][:openrouter] || [])

    override = normalize_opts(opts[:provider_config])
    Keyword.merge(base, override)
  end

  defp normalize_opts(nil), do: []
  defp normalize_opts(value) when is_list(value), do: value
  defp normalize_opts(value) when is_map(value), do: Enum.into(value, [])
  defp normalize_opts(_value), do: []

  defp require_api_key(config) do
    case config[:api_key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:skip, :unconfigured}
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status} = response})
       when status in 200..299,
       do: {:ok, response}

  defp normalize_response({:ok, %Req.Response{status: status}}) when status in [401, 403],
    do: {:skip, :unauthorized}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, "openrouter_request_failed_#{status}: #{inspect(body)}"}

  defp normalize_response({:error, _reason}), do: {:skip, :unavailable}
end
