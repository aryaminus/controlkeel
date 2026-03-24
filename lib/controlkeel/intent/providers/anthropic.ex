defmodule ControlKeel.Intent.Providers.Anthropic do
  @moduledoc false

  @behaviour ControlKeel.Intent.Provider

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  def compile(prompt, opts) do
    config = provider_config(opts)

    with {:ok, api_key} <- require_api_key(config),
         {:ok, response} <- request(prompt, api_key, config),
         {:ok, payload} <- Jason.decode(response.body),
         {:ok, tool_input} <- extract_tool_input(payload) do
      {:ok, tool_input, %{"model" => payload["model"] || config[:model]}}
    else
      other -> other
    end
  end

  defp request(prompt, api_key, config) do
    Req.post(
      url: config[:base_url] <> "/v1/messages",
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ],
      json: %{
        "model" => config[:model],
        "max_tokens" => 1_200,
        "system" => prompt.system,
        "messages" => [%{"role" => "user", "content" => prompt.user}],
        "tools" => [
          %{
            "name" => "submit_execution_brief",
            "description" => "Submit the compiled execution brief.",
            "input_schema" => ExecutionBrief.provider_schema()
          }
        ],
        "tool_choice" => %{"type" => "tool", "name" => "submit_execution_brief"}
      }
    )
    |> normalize_response()
  end

  defp extract_tool_input(%{"content" => content}) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "tool_use")) do
      %{"input" => input} when is_map(input) -> {:ok, input}
      _other -> {:error, :invalid_response}
    end
  end

  defp extract_tool_input(_payload), do: {:error, :invalid_response}

  defp provider_config(opts) do
    base =
      normalize_opts(Application.get_env(:controlkeel, Intent, [])[:providers][:anthropic] || [])

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
    do: {:error, "anthropic_request_failed_#{status}: #{inspect(body)}"}

  defp normalize_response({:error, _reason}), do: {:skip, :unavailable}
end
