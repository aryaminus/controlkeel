defmodule ControlKeel.Memory.Providers.OpenAI do
  @moduledoc false

  @default_model "text-embedding-3-small"

  def embed(text, opts \\ []) when is_binary(text) do
    api_key = opts[:api_key] || System.get_env("OPENAI_API_KEY")
    model = opts[:model] || System.get_env("CONTROLKEEL_EMBEDDINGS_MODEL") || @default_model
    base_url = opts[:base_url] || "https://api.openai.com"

    with true <- auth_ready?(api_key, base_url) || {:error, :unavailable},
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(
             url: endpoint_url(base_url, "/v1/embeddings"),
             headers: request_headers(api_key),
             json: %{"model" => model, "input" => text},
             receive_timeout: 10_000
           ),
         {:ok, embedding} <- normalize_embedding(body) do
      {:ok, %{embedding: embedding, provider: "openai", model: model}}
    else
      _error -> {:error, :unavailable}
    end
  end

  defp normalize_embedding(%{"data" => [%{"embedding" => embedding} | _]})
       when is_list(embedding) do
    {:ok, Enum.map(embedding, &normalize_float/1)}
  end

  defp normalize_embedding(_body), do: {:error, :invalid_response}

  defp normalize_float(value) when is_integer(value), do: value / 1
  defp normalize_float(value) when is_float(value), do: value
  defp normalize_float(_value), do: 0.0

  defp request_headers(api_key) when is_binary(api_key) and api_key != "" do
    [{"authorization", "Bearer #{api_key}"}]
  end

  defp request_headers(_api_key), do: []

  defp auth_ready?(api_key, _base_url) when is_binary(api_key) and api_key != "", do: true
  defp auth_ready?(_api_key, base_url), do: custom_openai_base_url?(base_url)

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
end
