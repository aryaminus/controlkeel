defmodule ControlKeel.Intent.Providers.OpenAI do
  @moduledoc false

  @behaviour ControlKeel.Intent.Provider

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  def compile(prompt, _opts) do
    config = provider_config()

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
      url: config[:base_url] <> "/v1/responses",
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
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
    |> normalize_response()
  end

  defp extract_content(%{"output_text" => content}) when is_binary(content), do: {:ok, content}

  defp extract_content(payload) do
    content =
      get_in(payload, ["output", Access.at(0), "content", Access.at(0), "text"]) ||
        get_in(payload, ["choices", Access.at(0), "message", "content"])

    if is_binary(content), do: {:ok, content}, else: {:error, :invalid_response}
  end

  defp provider_config do
    Application.get_env(:controlkeel, Intent, [])[:providers][:openai]
  end

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
    do: {:error, "openai_request_failed_#{status}: #{inspect(body)}"}

  defp normalize_response({:error, _reason}), do: {:skip, :unavailable}
end
