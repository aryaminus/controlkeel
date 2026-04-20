defmodule ControlKeel.ProviderBroker do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.AgentRuntimes.Registry, as: RuntimeRegistry
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
      "selected_auth_mode" => selected.auth_mode,
      "selected_auth_owner" => selected.auth_owner,
      "selected_trust_profile" => trust_profile_summary(selected),
      "reason" => selected.reason,
      "fallback_chain" => Enum.map(broker_chain, & &1.source),
      "provider_chain" => Enum.map(broker_chain, &resolution_summary/1),
      "profiles" => Enum.map(provider_ids(), &profile_summary(config, &1)),
      "bootstrap" => ProjectBinding.bootstrap_summary(root),
      "binding_mode" => bootstrap_mode(root),
      "attached_agents" => attached_agent_summaries(binding, root, opts),
      "runtime_hints" => runtime_hint_summaries(binding, root, opts)
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

  def set_base_url(provider, value) when is_binary(value) do
    ProviderConfig.put_profile(provider, %{"base_url" => normalize_optional_string(value)})
  end

  def set_model(provider, value) when is_binary(value) do
    ProviderConfig.put_profile(provider, %{"model" => normalize_optional_string(value)})
  end

  def doctor(project_root \\ File.cwd!(), opts \\ []) do
    status = status(project_root, opts)
    runtime_hints = status["runtime_hints"] || []

    suggestions =
      case {status["selected_source"], status["selected_provider"], runtime_hints} do
        {"heuristic", "heuristic", [_ | _] = hints} ->
          transports =
            hints
            |> Enum.map(&"#{&1["agent_id"]}:#{&1["transport"] || "runtime"}")
            |> Enum.join(", ")

          [
            "No CK-owned provider is currently configured for advisory requests.",
            "Attached runtime-backed agents can still execute with host-owned auth: #{transports}.",
            "Configure a provider only if you want CK itself to call hosted model APIs for advisory, validation, or embeddings."
          ]

        {"heuristic", "heuristic", _} ->
          [
            "No model provider is currently available.",
            "Configure a provider with `controlkeel provider set-key <provider> --value ...`, `controlkeel provider set-base-url openai --value ...`, run a supported agent bridge, or start Ollama.",
            "CK still works in heuristic mode for governance, proof, benchmark, and MCP surfaces."
          ]

        {source, provider, _} ->
          trust_profile = trust_profile_summary(selected_resolution(status))

          [
            "Current provider source: #{source}.",
            "Current provider: #{provider}.",
            "Auth mode: #{status["selected_auth_mode"]}.",
            "Auth owner: #{status["selected_auth_owner"]}.",
            "Trust boundary: #{trust_profile["trust_boundary"]}.",
            "Intermediary risk: #{trust_profile["intermediary_risk"]}.",
            "Integrity posture: #{trust_profile["integrity_posture"]}."
          ] ++ trust_profile_suggestions(trust_profile)
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
      integration = AgentIntegration.get(agent_id)
      resolution = bridge_resolution_for_integration(integration, opts)

      case resolution do
        %{provider: ^provider} -> resolution
        _ -> nil
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
        AgentIntegration.get(agent_id)
        |> bridge_resolution_for_integration(opts)
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
      "No configured provider source was available for #{Path.expand(project_root)}.",
      "heuristic",
      "none"
    )
  end

  defp bridge_resolution_for_integration(
         %AgentIntegration{
           provider_bridge: %{supported: true, mode: "env_bridge", provider: provider}
         } = integration,
         opts
       ) do
    env_bridge_resolution(provider, integration, opts)
  end

  defp bridge_resolution_for_integration(
         %AgentIntegration{id: "hermes-agent", provider_bridge: %{supported: true}} = integration,
         opts
       ) do
    opts
    |> hermes_provider_hint()
    |> resolution_from_hint(
      integration,
      "Attached Hermes provider config selected a compatible provider."
    )
  end

  defp bridge_resolution_for_integration(
         %AgentIntegration{id: "openclaw", provider_bridge: %{supported: true}} = integration,
         opts
       ) do
    opts
    |> openclaw_provider_hint()
    |> resolution_from_hint(
      integration,
      "Attached OpenClaw config selected a compatible provider."
    )
  end

  defp bridge_resolution_for_integration(
         %AgentIntegration{id: "droid", provider_bridge: %{supported: true}} = integration,
         opts
       ) do
    opts
    |> droid_provider_hint()
    |> resolution_from_hint(
      integration,
      "Attached Factory Droid settings selected a compatible provider."
    )
  end

  defp bridge_resolution_for_integration(
         %AgentIntegration{id: "forge", provider_bridge: %{supported: true, mode: "acp_session"}},
         opts
       ) do
    case Keyword.get(opts, :acp_session) do
      %{provider: provider} = session ->
        provider = normalize_provider(provider)
        allowed_providers = Map.keys(@hosted_provider_envs)

        api_key =
          session[:api_key] ||
            session["api_key"] ||
            present_env(Map.get(@hosted_provider_envs, provider))

        if provider in allowed_providers and present?(api_key) do
          config =
            provider_config(provider, api_key, opts, :agent_bridge)
            |> maybe_put_config("base_url", session[:base_url] || session["base_url"])
            |> maybe_put_config("model", session[:model] || session["model"])

          resolution(
            "agent_bridge",
            provider,
            config,
            "Attached Forge ACP session exposed a compatible provider.",
            "acp_session",
            "agent"
          )
        end

      _ ->
        nil
    end
  end

  defp bridge_resolution_for_integration(_integration, _opts), do: nil

  defp env_bridge_resolution(provider, integration, opts) do
    env_key = Map.get(@hosted_provider_envs, provider)

    case present_env(env_key) do
      nil ->
        nil

      api_key ->
        resolution(
          "agent_bridge",
          provider,
          provider_config(provider, api_key, opts, :agent_bridge),
          "Attached #{integration.label} exposed a compatible provider environment.",
          integration.auth_mode,
          AgentIntegration.auth_owner(integration)
        )
    end
  end

  defp resolution_from_hint(nil, _integration, _reason), do: nil

  defp resolution_from_hint(hint, integration, reason) do
    provider = normalize_provider(hint["provider"] || hint[:provider])

    cond do
      provider not in Map.keys(@hosted_provider_envs) ->
        nil

      api_key =
          hint["api_key"] || hint[:api_key] ||
            present_env(Map.get(@hosted_provider_envs, provider)) ->
        config =
          provider_config(provider, api_key, [], :agent_bridge)
          |> maybe_put_config("base_url", hint["base_url"] || hint[:base_url])
          |> maybe_put_config("model", hint["model"] || hint[:model])

        resolution(
          "agent_bridge",
          provider,
          config,
          reason,
          integration.auth_mode,
          AgentIntegration.auth_owner(integration)
        )

      true ->
        nil
    end
  end

  defp resolution(source, provider, config, reason, auth_mode \\ nil, auth_owner \\ nil) do
    %{
      source: source,
      provider: provider,
      model: config["model"] || config[:model],
      config: config,
      reason: reason,
      auth_mode: auth_mode || source_auth_mode(source),
      auth_owner: auth_owner || source_auth_owner(source)
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

    profile_resolution =
      resolution(
        "stored_profile",
        provider,
        effective_profile(provider, profile, []),
        "Stored profile summary."
      )

    %{
      "provider" => provider,
      "configured" => configured_profile?(effective_profile(provider, profile, [])),
      "persisted" => configured_profile?(profile),
      "env_override" => present?(present_env(env_key)),
      "default" => config["default_source"] == provider,
      "model" => profile["model"] || default_model(provider, []),
      "base_url" => profile["base_url"],
      "source_hint" => profile_source_hint(provider, profile),
      "trust_hint" => trust_profile_summary(profile_resolution)
    }
  end

  defp profile_source_hint("ollama", _profile), do: "Local runtime"

  defp profile_source_hint("openai", %{"base_url" => base_url}) when is_binary(base_url) do
    if custom_openai_base_url?(base_url), do: "OpenAI-compatible backend", else: "Stored profile"
  end

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

  defp attached_agent_summaries(binding, project_root, opts) do
    binding
    |> attached_agents(binding)
    |> Enum.map(fn {id, attrs} ->
      normalized_id = normalize_agent_id(id)
      integration = AgentIntegration.get(normalized_id)
      runtime_hint = RuntimeRegistry.provider_hint(normalized_id, project_root, opts)

      %{
        "id" => normalized_id,
        "label" => if(integration, do: integration.label, else: id),
        "provider_bridge_supported" => bridge_supported?(normalized_id),
        "support_class" => integration && integration.support_class,
        "auth_mode" => integration && integration.auth_mode,
        "auth_owner" => integration && AgentIntegration.auth_owner(integration),
        "mcp_mode" => integration && integration.mcp_mode,
        "skills_mode" => integration && integration.skills_mode,
        "runtime_transport" => integration && integration.runtime_transport,
        "runtime_review_transport" => integration && integration.runtime_review_transport,
        "runtime_auth_owner" => integration && integration.runtime_auth_owner,
        "runtime_session_support" => integration && integration.runtime_session_support,
        "runtime_capabilities" => integration && integration.runtime_capabilities,
        "runtime_provider_hint" => sanitize_runtime_hint(runtime_hint),
        "attached_at" => attrs["attached_at"] || attrs[:attached_at]
      }
    end)
  end

  defp runtime_hint_summaries(binding, project_root, opts) do
    binding
    |> attached_agents(binding)
    |> Enum.flat_map(fn {id, _attrs} ->
      normalized_id = normalize_agent_id(id)

      case RuntimeRegistry.provider_hint(normalized_id, project_root, opts) do
        nil ->
          []

        hint ->
          [
            %{
              "agent_id" => normalized_id,
              "transport" =>
                case AgentIntegration.get(normalized_id) do
                  nil -> nil
                  integration -> integration.runtime_transport
                end,
              "hint" => sanitize_runtime_hint(hint)
            }
          ]
      end
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

  defp hermes_provider_hint(opts) do
    config_path =
      Keyword.get(opts, :hermes_config_path) ||
        Path.join(user_home(), ".hermes/config.yaml")

    env_path =
      Keyword.get(opts, :hermes_env_path) ||
        Path.join(user_home(), ".hermes/.env")

    yaml = read_yaml_hints(config_path)
    env_map = read_env_file(env_path)

    provider = normalize_provider(yaml["provider"] || yaml["model_provider"])
    model = yaml["model"]
    env_key = env_map["OPENROUTER_API_KEY"] && "OPENROUTER_API_KEY"
    env_key = env_key || provider_env_key(provider)

    if provider && env_key do
      %{"provider" => provider, "model" => model, "api_key" => present_env(env_key)}
    end
  end

  defp openclaw_provider_hint(opts) do
    config_path =
      Keyword.get(opts, :openclaw_config_path) ||
        Path.join(user_home(), ".openclaw/openclaw.json")

    with {:ok, contents} <- File.read(config_path),
         {:ok, decoded} <- Jason.decode(contents) do
      providers =
        get_in(decoded, ["models", "providers"]) ||
          decoded["providers"] ||
          %{}

      find_provider_hint(providers, decoded["model"])
    else
      _ -> nil
    end
  end

  defp droid_provider_hint(opts) do
    settings_path =
      Keyword.get(opts, :droid_settings_path) ||
        Path.join(user_home(), ".factory/settings.json")

    with {:ok, contents} <- File.read(settings_path),
         {:ok, decoded} <- Jason.decode(contents) do
      provider =
        normalize_provider(
          decoded["provider"] ||
            get_in(decoded, ["model", "provider"]) ||
            get_in(decoded, ["llm", "provider"])
        ) || if(present?(decoded["base_url"] || decoded["baseUrl"]), do: "openai", else: nil)

      if provider do
        %{
          "provider" => provider,
          "model" => decoded["model"] || get_in(decoded, ["llm", "model"]),
          "base_url" => decoded["base_url"] || decoded["baseUrl"],
          "api_key" => present_env(provider_env_key(provider))
        }
      end
    else
      _ -> nil
    end
  end

  defp find_provider_hint(providers, default_model) when is_map(providers) do
    providers
    |> Enum.find_value(fn {name, config} ->
      provider =
        normalize_provider(name) ||
          normalize_provider(config["provider"]) ||
          if(present?(config["baseUrl"] || config["base_url"]), do: "openai", else: nil)

      env_key =
        config["apiKeyEnv"] ||
          config["api_key_env"] ||
          get_in(config, ["apiKey", "env"]) ||
          provider_env_key(provider)

      if provider && present?(env_key) && present?(present_env(env_key)) do
        %{
          "provider" => provider,
          "model" => config["model"] || config["defaultModel"] || default_model,
          "base_url" => config["baseUrl"] || config["base_url"],
          "api_key" => present_env(env_key)
        }
      end
    end)
  end

  defp find_provider_hint(_providers, _default_model), do: nil

  defp read_yaml_hints(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ":", parts: 2) do
            [key, value] ->
              value = value |> String.trim() |> String.trim("\"'")

              if value == "" or String.starts_with?(key, "#") do
                acc
              else
                Map.put(acc, String.trim(key), value)
              end

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp read_env_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              Map.put(acc, String.trim(key), String.trim(value) |> String.trim("\"'"))

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp provider_env_key(nil), do: nil
  defp provider_env_key(provider), do: Map.get(@hosted_provider_envs, provider)

  defp maybe_put_config(config, _key, nil), do: config
  defp maybe_put_config(config, key, value), do: Map.put(config, key, value)

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
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

  defp configured_profile?(%{"base_url" => base_url, "provider" => "openai"}),
    do: custom_openai_base_url?(base_url)

  defp configured_profile?(_profile), do: false

  defp resolution_summary(resolution) do
    %{
      "source" => resolution.source,
      "provider" => resolution.provider,
      "model" => resolution.model,
      "base_url" => resolution.config["base_url"] || resolution.config[:base_url],
      "reason" => resolution.reason,
      "auth_mode" => resolution.auth_mode,
      "auth_owner" => resolution.auth_owner,
      "trust_profile" => trust_profile_summary(resolution)
    }
  end

  defp selected_resolution(%{"provider_chain" => [resolution | _]}), do: resolution

  defp selected_resolution(_status),
    do: %{source: "heuristic", provider: "heuristic", config: %{}}

  defp trust_profile_summary(%{} = resolution) do
    source = resolution[:source] || resolution["source"]
    provider = resolution[:provider] || resolution["provider"]
    config = resolution[:config] || resolution["config"] || %{}

    base_url =
      config["base_url"] || config[:base_url] || resolution[:base_url] || resolution["base_url"]

    cond do
      provider == "heuristic" ->
        %{
          "trust_boundary" => "no_provider_selected",
          "intermediary_risk" => "unknown",
          "integrity_posture" => "none",
          "transparency_recommended" => false,
          "recommended_controls" => []
        }

      provider == "ollama" ->
        %{
          "trust_boundary" => "local_runtime",
          "intermediary_risk" => "low",
          "integrity_posture" => "local_only",
          "transparency_recommended" => false,
          "recommended_controls" => []
        }

      provider == "openrouter" ->
        %{
          "trust_boundary" => "api_router_intermediary",
          "intermediary_risk" => "high",
          "integrity_posture" => "router_visible_plaintext",
          "transparency_recommended" => true,
          "recommended_controls" => [
            "prefer_fail_closed_high_risk_tool_gates",
            "enable_append_only_request_response_logging",
            "prefer_direct_provider_paths_for_sensitive_sessions"
          ]
        }

      provider == "openai" and custom_openai_base_url?(base_url) ->
        %{
          "trust_boundary" => "openai_compatible_gateway",
          "intermediary_risk" => "high",
          "integrity_posture" => "custom_gateway_no_upstream_attestation",
          "transparency_recommended" => true,
          "recommended_controls" => [
            "prefer_fail_closed_high_risk_tool_gates",
            "enable_append_only_request_response_logging",
            "treat_gateway_as_full_trust_boundary"
          ]
        }

      source == "agent_bridge" ->
        %{
          "trust_boundary" => "host_managed_agent_bridge",
          "intermediary_risk" => "medium",
          "integrity_posture" => "host_bridge_not_provider_signed",
          "transparency_recommended" => true,
          "recommended_controls" => [
            "log_provider_and_bridge_resolution_per_session",
            "prefer_fail_closed_high_risk_tool_gates"
          ]
        }

      provider in ["anthropic", "openai"] ->
        %{
          "trust_boundary" => "direct_provider",
          "intermediary_risk" => "low",
          "integrity_posture" => "direct_tls_without_response_attestation",
          "transparency_recommended" => false,
          "recommended_controls" => []
        }

      true ->
        %{
          "trust_boundary" => "unknown_provider_path",
          "intermediary_risk" => "medium",
          "integrity_posture" => "unknown",
          "transparency_recommended" => true,
          "recommended_controls" => [
            "review_provider_path_before_sensitive_work",
            "enable_append_only_request_response_logging"
          ]
        }
    end
  end

  defp trust_profile_suggestions(%{"recommended_controls" => controls})
       when is_list(controls) and controls != [] do
    controls
    |> Enum.map(fn control ->
      case control do
        "prefer_fail_closed_high_risk_tool_gates" ->
          "Prefer fail-closed validation for high-risk shell, installer, and package commands on this provider path."

        "enable_append_only_request_response_logging" ->
          "Keep append-only request/response logging enabled so CK can scope exposure if a router or gateway becomes suspect."

        "prefer_direct_provider_paths_for_sensitive_sessions" ->
          "Prefer direct provider paths over routed intermediaries for sensitive coding, deploy, or security work."

        "treat_gateway_as_full_trust_boundary" ->
          "Treat the configured gateway as a full trust boundary because it can observe and rewrite tool-call payloads."

        "log_provider_and_bridge_resolution_per_session" ->
          "Record the selected bridge and provider resolution in session evidence before approving sensitive work."

        "review_provider_path_before_sensitive_work" ->
          "Review the provider path before running sensitive or autonomous sessions."

        other ->
          other
      end
    end)
  end

  defp trust_profile_suggestions(_trust_profile), do: []

  defp sanitize_runtime_hint(nil), do: nil

  defp sanitize_runtime_hint(hint) when is_map(hint) do
    hint
    |> Enum.reject(fn {key, _value} -> to_string(key) in ["api_key", "token", "secret"] end)
    |> Enum.into(%{})
  end

  defp source_auth_mode("agent_bridge"), do: "env_bridge"
  defp source_auth_mode("workspace_profile"), do: "ck_owned"
  defp source_auth_mode("user_default_profile"), do: "ck_owned"
  defp source_auth_mode("project_override"), do: "ck_owned"
  defp source_auth_mode("ollama"), do: "local"
  defp source_auth_mode("heuristic"), do: "heuristic"
  defp source_auth_mode(_source), do: "ck_owned"

  defp source_auth_owner("agent_bridge"), do: "agent"
  defp source_auth_owner("workspace_profile"), do: "controlkeel"
  defp source_auth_owner("user_default_profile"), do: "controlkeel"
  defp source_auth_owner("project_override"), do: "controlkeel"
  defp source_auth_owner("ollama"), do: "local"
  defp source_auth_owner("heuristic"), do: "none"
  defp source_auth_owner(_source), do: "controlkeel"

  defp present_env(nil), do: nil
  defp present_env(key), do: present_value(System.get_env(key))

  defp normalize_optional_string(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_value(nil), do: nil

  defp present_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp present_value(value), do: value

  defp present?(value), do: not is_nil(present_value(value))

  defp custom_openai_base_url?(base_url) when is_binary(base_url) do
    base_url
    |> normalized_openai_base_url()
    |> case do
      "" -> false
      "https://api.openai.com" -> false
      _ -> true
    end
  end

  defp custom_openai_base_url?(_base_url), do: false

  defp normalized_openai_base_url(base_url) do
    base_url
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.replace_suffix("/v1", "")
  end

  defp maybe_append(list, nil), do: list
  defp maybe_append(list, value), do: list ++ [value]

  defp global_config do
    case ProviderConfig.read() do
      {:ok, config} -> config
      {:error, _reason} -> ProviderConfig.default_config()
    end
  end
end
