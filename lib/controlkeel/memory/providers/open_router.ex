defmodule ControlKeel.Memory.Providers.OpenRouter do
  @moduledoc false

  @default_model "openai/text-embedding-3-small"

  def embed(text, opts \\ []) when is_binary(text) do
    api_key = opts[:api_key] || System.get_env("OPENROUTER_API_KEY")
    model = opts[:model] || System.get_env("CONTROLKEEL_EMBEDDINGS_MODEL") || @default_model

    with true <- (is_binary(api_key) and api_key != "") || {:error, :unavailable},
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(
             url: "https://openrouter.ai/api/v1/embeddings",
             headers: [{"authorization", "Bearer #{api_key}"}],
             json: %{"model" => model, "input" => text},
             receive_timeout: 10_000
           ),
         {:ok, embedding} <- normalize_embedding(body) do
      {:ok, %{embedding: embedding, provider: "openrouter", model: model}}
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
end
