defmodule ControlKeel.CLI.Dispatch.ProvidersBudget do
  @moduledoc false

  alias ControlKeel.Budget.CostOptimizer
  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.CLI.Output
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProviderBroker.Config
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :workspace_tool_policy_get, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      policy = Accounts.get_workspace_tool_policy(workspace_id)
      mode = policy.mode
      tools = WorkspaceToolPolicy.decode_tools(policy)

      lines = [
        "Tool policy for workspace ##{workspace_id}:",
        "  Mode: #{mode}"
      ]

      lines =
        if tools == [] do
          lines
        else
          lines ++ ["  Tools: #{Enum.join(tools, ", ")}"]
        end

      {:ok, lines}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :workspace_tool_policy_set, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, mode} <- require_string_option(options[:mode], "mode") do
      tools =
        case options[:tools] do
          nil -> []
          t -> String.split(t, ",") |> Enum.map(&String.trim/1)
        end

      case Accounts.set_workspace_tool_policy(workspace_id, mode, tools) do
        {:ok, policy} ->
          decoded = WorkspaceToolPolicy.decode_tools(policy)

          {:ok,
           [
             "Tool policy updated for workspace ##{workspace_id}.",
             "  Mode: #{policy.mode}",
             "  Tools: #{if decoded == [], do: "(none)", else: Enum.join(decoded, ", ")}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to set tool policy: #{inspect(changeset)}"}
      end
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :provider_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Project root: #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
       "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Bootstrap mode: #{status["bootstrap"]["mode"]}",
       "Profiles:"
     ] ++
       Enum.map(status["profiles"], fn profile ->
         "  #{profile["provider"]}: configured=#{if(profile["configured"], do: "yes", else: "no")} env=#{if(profile["env_override"], do: "yes", else: "no")} default=#{if(profile["default"], do: "yes", else: "no")} model=#{profile["model"] || "n/a"} base_url=#{profile["base_url"] || "default"}"
       end)}
  end

  def run_command(%{command: :provider_show, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Provider status for #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Selected model: #{status["selected_model"] || "n/a"}",
       "Selected base URL: #{selected_base_url(status)}",
       "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
       "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
       "Integrity posture: #{get_in(status, ["selected_trust_profile", "integrity_posture"]) || "unknown"}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Reason: #{status["reason"]}",
       "Fallback chain: #{Enum.join(status["fallback_chain"], " -> ")}"
     ] ++
       Enum.map(status["provider_chain"], fn resolution ->
         "  #{resolution["source"]}: #{resolution["provider"]} (#{resolution["model"] || "default"}) base_url=#{resolution["base_url"] || "default"} [#{resolution["auth_mode"]}/#{resolution["auth_owner"]}] trust=#{get_in(resolution, ["trust_profile", "trust_boundary"]) || "unknown"} risk=#{get_in(resolution, ["trust_profile", "intermediary_risk"]) || "unknown"}"
       end)}
  end

  def run_command(%{command: :provider_doctor, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = options[:project_root] || project_root
      doctor = ProviderBroker.doctor(root)
      status = doctor["status"]

      case format do
        "json" ->
          {:ok, [Jason.encode!(doctor)]}

        _ ->
          {:ok,
           [
             "Provider doctor for #{status["project_root"]}",
             "Selected source: #{status["selected_source"]}",
             "Selected provider: #{status["selected_provider"]}",
             "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
             "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
             "Auth mode: #{status["selected_auth_mode"]}",
             "Auth owner: #{status["selected_auth_owner"]}",
             "Bootstrap mode: #{status["bootstrap"]["mode"]}"
           ] ++ Enum.map(doctor["suggestions"], &"  #{&1}")}
      end
    end
  end

  def run_command(%{command: :provider_default, args: [source], options: options}, project_root) do
    scope = options[:scope] || "user"
    root = options[:project_root] || project_root

    case ProviderBroker.set_default_source(source, scope: scope, project_root: root) do
      {:ok, _config} ->
        {:ok, ["Set default provider source to #{source} for #{scope} scope."]}

      {:error, reason} ->
        {:error, "Failed to set default provider source: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_base_url, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_BASE_URL")

    with {:ok, base_url} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_base_url(provider, base_url) do
      {:ok, ["Stored base URL for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_BASE_URL"}

      {:error, reason} ->
        {:error, "Failed to store provider base URL: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_model, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_MODEL")

    with {:ok, model} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_model(provider, model) do
      {:ok, ["Stored model for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_MODEL"}

      {:error, reason} ->
        {:error, "Failed to store provider model: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_key, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_KEY")

    with {:ok, key} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_key(provider, key) do
      {:ok, ["Stored provider key for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_KEY"}

      {:error, reason} ->
        {:error, "Failed to store provider key: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_fallback_chain, args: providers, options: options},
        _project_root
      )
      when providers != [] do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _config} <- Config.set_fallback_chain(providers) do
      payload = %{"fallback_chain" => providers}

      Output.render_format(format, payload, fn _ ->
        ["Fallback chain set: #{Enum.join(providers, " → ")}"]
      end)
    else
      {:error, {:unknown_providers, bad}} ->
        {:error,
         "Unknown provider(s): #{Enum.join(bad, ", ")}. Allowed: #{Enum.join(Config.allowed_providers(), ", ")}"}

      {:error, reason} ->
        {:error, "Failed to set fallback chain: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :provider_set_fallback_chain} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end

  def run_command(%{command: :provider_set_fallback_chain, args: []}, _project_root) do
    {:error,
     "Provide at least one provider: controlkeel provider set-fallback-chain <p1> [p2 ...]"}
  end

  def run_command(%{command: :cost_optimize, options: options}, _project_root) do
    {:ok, format} = effective_cli_format(options)
    session_id = options[:session_id]
    provider = options[:provider]
    model = options[:model]

    spending =
      if session_id do
        import Ecto.Query

        from(i in ControlKeel.Mission.Invocation,
          where: i.session_id == ^session_id,
          select: %{
            estimated_cost_cents: i.estimated_cost_cents,
            tool: i.tool,
            metadata: i.metadata
          }
        )
        |> ControlKeel.Repo.all()
      else
        []
      end

    case CostOptimizer.suggest(session_id || "cli",
           spending: spending,
           top_provider: provider,
           top_model: model
         ) do
      {:ok, []} ->
        case format do
          "json" -> {:ok, [Jason.encode!(%{"suggestions" => []})]}
          _ -> {:ok, ["No cost optimization suggestions at this time."]}
        end

      {:ok, suggestions} ->
        if format == "json" do
          {:ok, [Jason.encode!(%{"suggestions" => suggestions})]}
        else
          lines =
            Enum.map(suggestions, fn s ->
              "[#{s.priority}] #{s.title}\n  #{s.description}\n  Potential savings: #{s.savings_percent}%"
            end)

          {:ok, ["Cost Optimization Suggestions:", "" | lines]}
        end
    end
  end

  def run_command(%{command: :cost_compare, options: options}, _project_root) do
    tokens = options[:tokens] || 10_000

    case CostOptimizer.compare_agents("CLI comparison", estimated_tokens: tokens) do
      {:ok, result} ->
        lines =
          Enum.map(result.comparisons, fn c ->
            "$#{Float.round(c.estimated_cost_usd, 4)}  #{c.agent} (#{c.provider}/#{c.model})"
          end)

        savings =
          if result.savings_range > 0 do
            ["", "Potential savings: $#{Float.round(result.savings_range / 100, 2)}"]
          else
            []
          end

        {:ok, ["Agent cost comparison (#{tokens} tokens):", "" | lines] ++ savings}
    end
  end
end
