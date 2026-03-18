defmodule ControlKeel.Intent.Providers.Ollama do
  @moduledoc false

  @behaviour ControlKeel.Intent.Provider

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief

  def compile(prompt, _opts) do
    config = provider_config()

    with {:ok, response} <- request(prompt, config),
         {:ok, payload} <- Jason.decode(response.body),
         {:ok, content} <- extract_content(payload),
         {:ok, brief_map} <- Jason.decode(content) do
      {:ok, brief_map, %{"model" => payload["model"] || config[:model]}}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      other -> other
    end
  end

  defp request(prompt, config) do
    Req.post(
      url: config[:base_url] <> "/api/chat",
      headers: [{"content-type", "application/json"}],
      json: %{
        "model" => config[:model],
        "stream" => false,
        "format" => ExecutionBrief.provider_schema(),
        "messages" => [
          %{"role" => "system", "content" => prompt.system},
          %{"role" => "user", "content" => prompt.user}
        ]
      }
    )
    |> normalize_response()
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_binary(content),
    do: {:ok, content}

  defp extract_content(_payload), do: {:error, :invalid_response}

  defp provider_config do
    Application.get_env(:controlkeel, Intent, [])[:providers][:ollama]
  end

  defp normalize_response({:ok, %Req.Response{status: status} = response})
       when status in 200..299,
       do: {:ok, response}

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, "ollama_request_failed_#{status}: #{inspect(body)}"}

  defp normalize_response({:error, _reason}), do: {:skip, :unavailable}
end
