defmodule ControlKeel.Memory.Embeddings do
  @moduledoc false

  alias ControlKeel.Memory.Embedding
  alias ControlKeel.Memory.Record
  alias ControlKeel.Memory.Providers.{Ollama, OpenAI, OpenRouter}
  alias ControlKeel.Repo

  def embed(text, opts \\ []) when is_binary(text) do
    providers = providers(opts)

    Enum.reduce_while(providers, {:error, :unavailable}, fn provider, _acc ->
      case provider_embed(provider, text, opts) do
        {:ok, payload} -> {:halt, {:ok, payload}}
        _error -> {:cont, {:error, :unavailable}}
      end
    end)
  end

  def upsert_record_embedding(%Record{} = record, opts \\ []) do
    with {:ok, payload} <- embed(document(record), opts) do
      attrs = %{
        memory_record_id: record.id,
        provider: payload.provider,
        model: payload.model,
        dimensions: length(payload.embedding),
        embedding: payload.embedding
      }

      %Embedding{}
      |> Embedding.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [
            dimensions: attrs.dimensions,
            embedding: attrs.embedding,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        ],
        conflict_target: [:memory_record_id, :provider, :model]
      )
    else
      {:error, :unavailable} -> {:error, :unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  def document(%Record{} = record) do
    [record.title, record.summary, record.body, Enum.join(record.tags || [], " ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp providers(opts) do
    override = Application.get_env(:controlkeel, :memory_embedding_providers_override)

    cond do
      is_list(override) and override != [] ->
        override

      true ->
        provider_env =
          opts[:provider] ||
            System.get_env("CONTROLKEEL_EMBEDDINGS_PROVIDER") ||
            Application.get_env(:controlkeel, :memory_embeddings_provider)

        base =
          case provider_env do
            nil -> configured_providers()
            "none" -> []
            value when is_binary(value) -> [String.to_existing_atom(value)]
            value when is_atom(value) -> [value]
            _value -> configured_providers()
          end

        Enum.uniq(base)
    end
  rescue
    ArgumentError -> configured_providers()
  end

  defp provider_embed({module, provider_opts}, text, _opts)
       when is_atom(module) and is_list(provider_opts) do
    apply(module, :embed, [text, provider_opts])
  end

  defp provider_embed(:ollama, text, opts), do: Ollama.embed(text, opts)
  defp provider_embed(:openai, text, opts), do: OpenAI.embed(text, opts)
  defp provider_embed(:openrouter, text, opts), do: OpenRouter.embed(text, opts)
  defp provider_embed(_provider, _text, _opts), do: {:error, :unavailable}

  defp configured_providers do
    []
    |> maybe_add_provider(:ollama, ollama_configured?())
    |> maybe_add_provider(:openai, present?(System.get_env("OPENAI_API_KEY")))
    |> maybe_add_provider(:openrouter, present?(System.get_env("OPENROUTER_API_KEY")))
  end

  defp ollama_configured? do
    present?(System.get_env("CONTROLKEEL_OLLAMA_BASE_URL")) or
      present?(System.get_env("OLLAMA_HOST")) or
      Application.get_env(:controlkeel, :memory_embeddings_provider) == :ollama
  end

  defp maybe_add_provider(providers, provider, true), do: providers ++ [provider]
  defp maybe_add_provider(providers, _provider, false), do: providers

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
