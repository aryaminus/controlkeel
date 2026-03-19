defmodule ControlKeel.Memory.Providers.Ollama do
  @moduledoc false

  @default_model "nomic-embed-text"

  def embed(text, opts \\ []) when is_binary(text) do
    base_url =
      opts[:base_url] ||
        System.get_env("CONTROLKEEL_OLLAMA_BASE_URL") ||
        System.get_env("OLLAMA_HOST") ||
        "http://127.0.0.1:11434"

    model = opts[:model] || System.get_env("CONTROLKEEL_EMBEDDINGS_MODEL") || @default_model

    with {:ok, embedding} <- request_embedding(base_url, model, text) do
      {:ok, %{embedding: embedding, provider: "ollama", model: model}}
    end
  end

  defp request_embedding(base_url, model, text) do
    endpoints = [
      {"/api/embed", %{"model" => model, "input" => text}},
      {"/api/embeddings", %{"model" => model, "prompt" => text}}
    ]

    Enum.reduce_while(endpoints, {:error, :unavailable}, fn {path, payload}, _acc ->
      case Req.post(base_url: base_url, url: path, json: payload, receive_timeout: 5_000) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          case normalize_embedding(body) do
            {:ok, embedding} -> {:halt, {:ok, embedding}}
            _error -> {:cont, {:error, :unavailable}}
          end

        _other ->
          {:cont, {:error, :unavailable}}
      end
    end)
  end

  defp normalize_embedding(%{"embedding" => embedding}) when is_list(embedding) do
    {:ok, Enum.map(embedding, &normalize_float/1)}
  end

  defp normalize_embedding(%{"embeddings" => [embedding | _]}) when is_list(embedding) do
    {:ok, Enum.map(embedding, &normalize_float/1)}
  end

  defp normalize_embedding(_body), do: {:error, :invalid_response}

  defp normalize_float(value) when is_integer(value), do: value / 1
  defp normalize_float(value) when is_float(value), do: value
  defp normalize_float(_value), do: 0.0
end
