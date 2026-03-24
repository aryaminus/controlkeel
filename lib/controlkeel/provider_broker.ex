defmodule ControlKeel.ProviderBroker do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProviderConfig

  @hosted_provider_envs %{
    "anthropic" => "ANTHROPIC_API_KEY",
    "openai" => "OPENAI_API_KEY",
    "openrouter" => "OPENROUTER_API_KEY"
  }
  @ollama_model_env "CONTROLKEEL_INTENT_OLLAMA_MODEL"

  def provider_ids do
    ProviderConfig.allowed_providers()
  end

  def status(project_root \\ File.cwd!(), opts \\ []) do
    root = Path.expand(project_root)
    binding = effective_binding(root)
    broker_chain = resolution_chain(root, opts)
    selected = List.first(broker_chain) || heuristic_resolution(root, opts)
    config = global_config()

    %{
      "project_root" => root,
      "selected_source" => selected.source,
      "selected_provider" => selected.provider,
      "selected_model" => selected.model,
      "reason" => selected.reason,
      "fallback_chain" => Enum.map(broker_chain, & &1.source),
      "provider_chain" => Enum.map(broker_chain, &resolution_summary/1),
      "profiles" => Enum.map(provider_ids(), &profile_summary(config, &1)),
      "bootstrap" => ProjectBinding.bootstrap_summary(root),
      "binding_mode" => bootstrap_mode(root),
      "attached_agents" => attached_agent_summaries(binding)
    }
  end

  def intent_chain(project_root \\ File.cwd!(), opts \\ []) do
    resolution_chain(project_root, Keyword.put(opts, :feature, :intent))
    |> Enum.filter(&provider_supported_for_feature?(&1.provider, :intent))
  end

  def advisory_chain(project_root \\ File.cwd!(), opts \\ []) do
    resolution_chain(project_root, Keyword.put(opts, :feature, :advisory))
    |> Enum.filter(&provider_supported_for_feature?(&1.provider, :advisory))
  end

  def embeddings_chain(project_root \\ File.cwd!(), opts \\ []) do
    resolution_chain(project_root, Keyword.put(opts, :feature, :embeddings))
    |> Enum.filter(&provider_supported_for_feature?(&1.provider, :embeddings))
  end

  def resolve_provider(provider, project_root \\ File.cwd!(), opts \\ []) do
    provider = normalize_provider(provider)
    root = Path.expand(project_root)
    binding = effective_binding(root)

    cond do
      provider in ["anthropic", "openai", "openrouter"] ->
        workspace_resolution =
          case workspace_profile_resolution(opts) do
            %{provider: ^provider} = resolution -> resolution
            _ -> nil
          end

        agent_bridge_resolution_for(provider, binding, opts) ||
          workspace_resolution ||
          user_profile_resolution_for(provider, opts) ||
          project_override_resolution_for(provider, binding, opts)

      provider == "ollama" ->
        ollama_resolution(opts)

      true ->
        nil
    end
  end

  def default_source(project_root \\ File.cwd!()) do
    project_root
    |> Path.expand()
    |> project_override_source()
    |> Kernel.||(global_config()["default_source"])
  end

  def set_default_source(source, opts \\ []) do
    scope = Keyword.get(opts, :scope, "user")

    case scope do
      "project" ->
        project_root = Keyword.get(opts, :project_root, File.cwd!())
        ProjectBinding.put_provider_override(project_root, %{"default_source" => source})

      _ ->
        ProviderConfig.set_default_source(source)
    end
  end

  def set_key(provider, value) when is_binary(value) do
    ProviderConfig.put_profile(provider, %{"api_key" => value})
  end

  def doctor(project_root \\ File.cwd!(), opts \\ []) do
    status = status(project_root, opts)

    suggestions =
      case {status["selected_source"], status["selected_provider"]} do
        {"heuristic", "heuristic"} ->
          [
            "No model provider is currently available.",
            "Configure a provider with `controlkeel provider set-key <provider> --value ...`, run a supported agent bridge, or start Ollama."
          ]

        {source, provider} ->
          [
            "Current provider source: #{source}.",
            "Current provider: #{provider}."
          ]
      end

    %{
      "status" => status,
      "suggestions" => suggestions
    }
  end

  def bridge_supported?(agent_id) when is_binary(agent_id) do
    case AgentIntegration.get(agent_id) do
      %{provider_bridge: %{supported: true}} -> true
      _ -> false
    end
  end

  defp resolution_chain(project_root, opts) do
    root = Path.expand(project_root)
    binding = effective_binding(root)

    []
    |> maybe_append(agent_bridge_resolution(binding, opts))
    |> maybe_append(workspace_profile_resolution(opts))
    |> maybe_append(user_profile_resolution(opts))
    |> maybe_append(project_override_resolution(binding, opts))
    |> maybe_append(ollama_resolution(opts))
    |> Kernel.++([heuristic_resolution(root, opts)])
  end

  defp agent_bridge_resolution_for(provider, binding, opts) do
    binding
    |> attached_agents(binding)
    |> Enum.find_value(fn {agent_id, _attrs} ->
      case AgentIntegration.get(agent_id) do
        %{provider_bridge: %{supported: true, provider: ^provider}} = integration ->
          env_key = Map.get(@hosted_provider_envs, provider)

          case present_env(env_key) do
            nil ->
              nil

            api_key ->
              resolution(
                "agent_bridge",
                provider,
                provider_config(provider, api_key, opts, :agent_bridge),
                "Attached #{integration.label} exposed a compatible provider environment."
              )
          end

        _ ->
          nil
      end
    end)
  end

  defp agent_bridge_resolution(binding, opts) do
    requested = normalize_provider(Keyword.get(opts, :provider))

    if requested do
      agent_bridge_resolution_for(requested, binding, opts)
    else
      binding
      |> attached_agents(binding)
      |> Enum.find_value(fn {agent_id, _attrs} ->
        case AgentIntegration.get(agent_id) do
          %{provider_bridge: %{supported: true, provider: provider}} ->
            agent_bridge_resolution_for(provider, binding, opts)

          _ ->
            nil
        end
      end)
    end
  end

  defp workspace_profile_resolution(opts) do
    metadata =
      case Keyword.get(opts, :service_account) do
        %{metadata: metadata} when is_map(metadata) -> metadata
        _ -> %{}
      end

    provider = metadata["provider"] || metadata[:provider]
    source = metadata["provider_source"] || metadata[:provider_source] || "workspace_profile"

    cond do
      normalize_source(source) == "agent_bridge" ->
        nil

      provider = normalize_provider(provider) ->
        workspace_profile_resolution_for(provider, opts)

      true ->
        nil
    end
  end

  defp workspace_profile_resolution_for(provider, opts) do
    config = global_config()
    profile = ProviderConfig.profile(config, provider)

    if configured_profile?(profile) do
      resolution(
        "workspace_profile",
        provider,
        effective_profile(provider, profile, opts),
        "Workspace or service account metadata selected this provider."
      )
    end
  end

  defp user_profile_resolution(opts) do
    source = global_config()["default_source"]

    case source do
      source
      when source in ["agent_bridge", "project_override", "workspace_profile", "heuristic"] ->
        nil

      "ollama" ->
        nil

      provider ->
        provider
        |> normalize_provider()
        |> user_profile_resolution_for(opts)
    end
  end

  defp user_profile_resolution_for(provider, opts) do
    profile = ProviderConfig.profile(global_config(), provider)

    if configured_profile?(effective_profile(provider, profile, opts)) do
      resolution(
        "user_default_profile",
        provider,
        effective_profile(provider, profile, opts),
        "User provider profile is configured or available in the current environment."
      )
    end
  end

  defp project_override_resolution(binding, opts) do
    case binding do
      %{"provider_override" => override} when is_map(override) ->
        source =
          normalize_source(
            override["default_source"] || override[:default_source] || "project_override"
          )

        provider = normalize_provider(override["provider"] || override[:provider] || source)

        cond do
          source == "heuristic" ->
            nil

          provider in ProviderConfig.allowed_providers() ->
            project_override_resolution_for(provider, binding, opts)

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  defp project_override_resolution_for(provider, binding, opts) do
    case binding do
      %{"provider_override" => _override} ->
        profile = ProviderConfig.profile(global_config(), provider)

        if configured_profile?(effective_profile(provider, profile, opts)) do
          resolution(
            "project_override",
            provider,
            effective_profile(provider, profile, opts),
            "Project binding override selected this provider."
          )
        end

      _ ->
        nil
    end
  end

  defp ollama_resolution(opts) do
    base_url =
      Keyword.get(opts, :ollama_base_url) ||
        System.get_env("CONTROLKEEL_OLLAMA_BASE_URL") ||
        System.get_env("OLLAMA_HOST")

    if present?(base_url) do
      model =
        Keyword.get(opts, :model) ||
          System.get_env(@ollama_model_env) ||
          "qwen2.5:7b"

      resolution(
        "ollama",
        "ollama",
        %{"base_url" => base_url, "model" => model},
        "Local Ollama endpoint is configured."
      )
    end
  end

  defp heuristic_resolution(project_root, _opts) do
    resolution(
      "heuristic",
      "heuristic",
      %{},
      "No configured provider source was available for #{Path.expand(project_root)}."
    )
  end

  defp resolution(source, provider, config, reason) do
    %{
      source: source,
      provider: provider,
      model: config["model"] || config[:model],
      config: config,
      reason: reason
    }
  end

  defp effective_profile(provider, profile, opts) do
    env_key = Map.get(@hosted_provider_envs, provider)

    base_profile =
      profile
      |> Map.put("provider", provider)
      |> Map.put("model", profile["model"] || default_model(provider, opts))

    if env_key do
      case present_env(env_key) do
        nil -> base_profile
        api_key -> Map.put(base_profile, "api_key", api_key)
      end
    else
      base_profile
    end
  end

  defp provider_config(provider, api_key, opts, _source) do
    %{
      "provider" => provider,
      "api_key" => api_key,
      "model" => Keyword.get(opts, :model) || default_model(provider, opts)
    }
  end

  defp default_model("anthropic", _opts), do: "claude-sonnet-4.6"
  defp default_model("openai", _opts), do: "gpt-5.4"
  defp default_model("openrouter", _opts), do: "openai/gpt-5.4-mini"
  defp default_model("ollama", _opts), do: System.get_env(@ollama_model_env) || "qwen2.5:7b"
  defp default_model(_provider, _opts), do: nil

  defp profile_summary(config, provider) do
    profile = ProviderConfig.profile(config, provider)
    env_key = Map.get(@hosted_provider_envs, provider)

    %{
      "provider" => provider,
      "configured" => configured_profile?(effective_profile(provider, profile, [])),
      "persisted" => configured_profile?(profile),
      "env_override" => present?(present_env(env_key)),
      "default" => config["default_source"] == provider,
      "model" => profile["model"] || default_model(provider, []),
      "source_hint" => profile_source_hint(provider, profile)
    }
  end

  defp profile_source_hint("ollama", _profile), do: "Local runtime"

  defp profile_source_hint(_provider, profile) do
    if configured_profile?(profile), do: "Stored profile", else: "Not configured"
  end

  defp effective_binding(project_root) do
    case ProjectBinding.read_effective(project_root) do
      {:ok, binding, _mode} -> binding
      _ -> %{}
    end
  end

  defp bootstrap_mode(project_root) do
    case ProjectBinding.read_effective(project_root) do
      {:ok, _binding, mode} -> Atom.to_string(mode)
      _ -> "none"
    end
  end

  defp attached_agents(%{"attached_agents" => attached_agents}, _binding)
       when is_map(attached_agents),
       do: Enum.to_list(attached_agents)

  defp attached_agents(_binding, _raw), do: []

  defp attached_agent_summaries(binding) do
    binding
    |> attached_agents(binding)
    |> Enum.map(fn {id, attrs} ->
      integration = AgentIntegration.get(normalize_agent_id(id))

      %{
        "id" => normalize_agent_id(id),
        "label" => if(integration, do: integration.label, else: id),
        "provider_bridge_supported" => bridge_supported?(normalize_agent_id(id)),
        "attached_at" => attrs["attached_at"] || attrs[:attached_at]
      }
    end)
  end

  defp project_override_source(project_root) do
    with {:ok, binding, _mode} <- ProjectBinding.read_effective(project_root),
         %{} = override <- binding["provider_override"] do
      override["default_source"] || override[:default_source]
    else
      _ -> nil
    end
  end

  defp normalize_provider(nil), do: nil

  defp normalize_provider(provider) do
    provider
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_source(source) when is_binary(source) do
    source
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_source(source), do: normalize_source(to_string(source))

  defp normalize_agent_id(id) do
    id
    |> to_string()
    |> String.replace("_", "-")
  end

  defp provider_supported_for_feature?(provider, feature)
       when provider in ["anthropic", "openai", "openrouter", "ollama"] do
    case feature do
      :embeddings -> provider in ["openai", "openrouter", "ollama"]
      _ -> true
    end
  end

  defp provider_supported_for_feature?(_provider, _feature), do: false

  defp configured_profile?(%{"api_key" => api_key}) when is_binary(api_key),
    do: String.trim(api_key) != ""

  defp configured_profile?(%{"base_url" => base_url, "provider" => "ollama"}),
    do: present?(base_url)

  defp configured_profile?(_profile), do: false

  defp resolution_summary(resolution) do
    %{
      "source" => resolution.source,
      "provider" => resolution.provider,
      "model" => resolution.model,
      "reason" => resolution.reason
    }
  end

  defp present_env(nil), do: nil
  defp present_env(key), do: present_value(System.get_env(key))

  defp present_value(nil), do: nil

  defp present_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp present_value(value), do: value

  defp present?(value), do: not is_nil(present_value(value))

  defp maybe_append(list, nil), do: list
  defp maybe_append(list, value), do: list ++ [value]

  defp global_config do
    case ProviderConfig.read() do
      {:ok, config} -> config
      {:error, _reason} -> ProviderConfig.default_config()
    end
  end
end
