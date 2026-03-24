defmodule ControlKeel.ProviderConfig do
  @moduledoc false

  alias ControlKeel.RuntimePaths

  @version 1
  @providers ~w(anthropic openai openrouter ollama)
  @default_source "agent_bridge"

  def allowed_providers, do: @providers

  def read do
    path = RuntimePaths.config_path()

    case File.read(path) do
      {:ok, payload} ->
        with {:ok, decoded} <- Jason.decode(payload),
             :ok <- validate(decoded) do
          {:ok, normalized(decoded)}
        else
          {:error, _reason} -> {:ok, default_config()}
        end

      {:error, :enoent} ->
        {:ok, default_config()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write(attrs) when is_map(attrs) do
    config = attrs |> normalized() |> merge_defaults()
    path = RuntimePaths.config_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(config, pretty: true) <> "\n") do
      {:ok, config}
    end
  end

  def set_default_source(source) when is_binary(source) do
    with {:ok, config} <- read() do
      write(Map.put(config, "default_source", normalize_source(source)))
    end
  end

  def put_profile(provider, attrs) when is_binary(provider) and is_map(attrs) do
    provider = normalize_provider(provider)

    with true <- provider in @providers || {:error, :unknown_provider},
         {:ok, config} <- read() do
      profile =
        config
        |> get_in(["profiles", provider])
        |> Kernel.||(%{})
        |> Map.merge(stringify_keys(attrs))
        |> then(&normalize_profile(provider, &1))

      updated =
        put_in(config, ["profiles", provider], profile)

      write(updated)
    end
  end

  def default_config do
    %{
      "version" => @version,
      "default_source" => @default_source,
      "profiles" =>
        Enum.into(@providers, %{}, fn provider ->
          {provider, default_profile(provider)}
        end)
    }
  end

  def profile(config, provider) when is_map(config) and is_binary(provider) do
    provider = normalize_provider(provider)
    get_in(config, ["profiles", provider]) || default_profile(provider)
  end

  defp validate(%{"version" => @version, "profiles" => profiles}) when is_map(profiles), do: :ok
  defp validate(_payload), do: {:error, :invalid_config}

  defp normalized(config) do
    config
    |> stringify_keys()
    |> merge_defaults()
    |> update_in(["profiles"], fn profiles ->
      profiles
      |> Kernel.||(%{})
      |> Enum.into(%{}, fn {provider, attrs} ->
        provider = normalize_provider(provider)
        {provider, normalize_profile(provider, attrs)}
      end)
      |> then(fn profiles ->
        Enum.into(@providers, profiles, fn provider ->
          {provider, Map.get(profiles, provider, default_profile(provider))}
        end)
      end)
    end)
    |> Map.update("default_source", @default_source, &normalize_source/1)
  end

  defp merge_defaults(config) do
    Map.merge(default_config(), config)
  end

  defp normalize_profile(provider, attrs) do
    provider
    |> default_profile()
    |> Map.merge(stringify_keys(attrs))
    |> Map.update("provider", provider, &normalize_provider/1)
    |> Map.update("enabled", true, &truthy?/1)
  end

  defp default_profile(provider) do
    %{
      "provider" => provider,
      "api_key" => nil,
      "base_url" => nil,
      "model" => nil,
      "enabled" => true
    }
  end

  defp normalize_provider(provider) do
    provider
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_source(source) do
    source
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "anthropic" -> "anthropic"
      "openai" -> "openai"
      "openrouter" -> "openrouter"
      "ollama" -> "ollama"
      "heuristic" -> "heuristic"
      "agent_bridge" -> "agent_bridge"
      "user_profile" -> "user_profile"
      "project_override" -> "project_override"
      "workspace_profile" -> "workspace_profile"
      _ -> @default_source
    end
  end

  defp stringify_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "yes"], do: true
  defp truthy?(value) when value in [false, "false", "0", 0, "no"], do: false
  defp truthy?(value) when is_nil(value), do: false
  defp truthy?(_value), do: true
end
