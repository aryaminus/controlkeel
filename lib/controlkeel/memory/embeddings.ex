defmodule ControlKeel.Memory.Embeddings do
  @moduledoc false

  alias ControlKeel.Memory.Embedding
  alias ControlKeel.Memory.Record
  alias ControlKeel.Memory.Providers.{Ollama, OpenAI, OpenRouter}
  alias ControlKeel.ProviderBroker
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
        project_root = opts[:project_root] || File.cwd!()
        provider_env = opts[:provider] || System.get_env("CONTROLKEEL_EMBEDDINGS_PROVIDER")

        base =
          case provider_env do
            nil ->
              configured_providers(project_root)

            "none" ->
              []

            value when is_binary(value) ->
              [resolved_provider(value, project_root, opts)]

            value when is_atom(value) ->
              [resolved_provider(Atom.to_string(value), project_root, opts)]

            _value ->
              configured_providers(project_root)
          end

        base
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn
          %{provider: provider} -> provider
          other -> other
        end)
    end
  rescue
    ArgumentError -> configured_providers(File.cwd!())
  end

  defp provider_embed({module, provider_opts}, text, _opts)
       when is_atom(module) and is_list(provider_opts) do
    apply(module, :embed, [text, provider_opts])
  end

  defp provider_embed(%{provider: "ollama", config: config}, text, _opts),
    do: Ollama.embed(text, normalize_config(config))

  defp provider_embed(%{provider: "openai", config: config}, text, _opts),
    do: OpenAI.embed(text, normalize_config(config))

  defp provider_embed(%{provider: "openrouter", config: config}, text, _opts),
    do: OpenRouter.embed(text, normalize_config(config))

  defp provider_embed(:ollama, text, opts), do: Ollama.embed(text, opts)
  defp provider_embed(:openai, text, opts), do: OpenAI.embed(text, opts)
  defp provider_embed(:openrouter, text, opts), do: OpenRouter.embed(text, opts)
  defp provider_embed(_provider, _text, _opts), do: {:error, :unavailable}

  defp configured_providers(project_root) do
    ProviderBroker.embeddings_chain(project_root)
  end

  defp resolved_provider(provider, project_root, opts) do
    ProviderBroker.resolve_provider(provider, project_root, opts)
  end

  defp normalize_config(config) when is_list(config), do: config
  defp normalize_config(config) when is_map(config), do: Enum.into(config, [])
  defp normalize_config(_config), do: []
end
