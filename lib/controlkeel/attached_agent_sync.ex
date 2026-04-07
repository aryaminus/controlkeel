defmodule ControlKeel.AttachedAgentSync do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills

  def sync(binding, project_root, opts \\ []) when is_map(binding) do
    mode = Keyword.get(opts, :mode, :project)
    current_version = controlkeel_version()

    {updated_binding, changes} =
      binding
      |> Map.get("attached_agents", %{})
      |> Enum.reduce({binding, []}, fn {agent_key, attrs}, {acc, changes} ->
        case sync_agent(agent_key, attrs, project_root, current_version) do
          {:ok, _updated_attrs, false} ->
            {acc, changes}

          {:ok, updated_attrs, true} ->
            {
              put_in(acc, ["attached_agents", agent_key], updated_attrs),
              [%{"agent" => agent_key, "status" => "synced"} | changes]
            }

          {:error, reason} ->
            {acc,
             [
               %{"agent" => agent_key, "status" => "failed", "reason" => inspect(reason)}
               | changes
             ]}
        end
      end)

    if updated_binding != binding do
      case ProjectBinding.write_effective(updated_binding, project_root, mode: mode) do
        {:ok, written} -> {:ok, written, Enum.reverse(changes)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, binding, Enum.reverse(changes)}
    end
  end

  defp sync_agent(agent_key, attrs, project_root, current_version) do
    attrs = stringify_keys(attrs)

    if attrs["controlkeel_version"] == current_version do
      {:ok, attrs, false}
    else
      with %AgentIntegration{} = integration <- inferred_integration(agent_key),
           {:ok, target} <- inferred_target(attrs, integration),
           {:ok, scope} <- inferred_scope(attrs, integration),
           {:ok, result} <- Skills.install(target, project_root, scope: scope) do
        updated_attrs =
          attrs
          |> Map.put("target", target)
          |> Map.put("scope", scope)
          |> Map.put("controlkeel_version", current_version)
          |> Map.put(
            "synced_at",
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          )
          |> merge_install_result(result)

        {:ok, updated_attrs, true}
      else
        nil -> {:ok, attrs, false}
        {:skip, _reason} -> {:ok, attrs, false}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp inferred_integration(agent_key) do
    agent_key
    |> AgentIntegration.canonical()
  end

  defp inferred_target(%{"target" => target}, _integration)
       when is_binary(target) and target != "",
       do: {:ok, target}

  defp inferred_target(_attrs, %AgentIntegration{preferred_target: target})
       when is_binary(target) and target != "" do
    {:ok, target}
  end

  defp inferred_target(_attrs, _integration), do: {:skip, :no_target}

  defp inferred_scope(%{"scope" => scope}, _integration)
       when scope in ["project", "user"] do
    {:ok, scope}
  end

  defp inferred_scope(_attrs, %AgentIntegration{default_scope: scope})
       when scope in ["project", "user"] do
    {:ok, scope}
  end

  defp inferred_scope(_attrs, _integration), do: {:skip, :no_scope}

  defp merge_install_result(attrs, result) when is_map(result) do
    attrs
    |> maybe_put("destination", Map.get(result, :destination))
    |> maybe_put("compat_destination", Map.get(result, :compat_destination))
    |> maybe_put("skills_destination", Map.get(result, :skills_destination))
    |> maybe_put("agents_destination", Map.get(result, :agents_destination))
    |> maybe_put("commands_destination", Map.get(result, :commands_destination))
    |> maybe_put("rules_destination", Map.get(result, :rules_destination))
    |> maybe_put("config_destination", Map.get(result, :config_destination))
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp stringify_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp controlkeel_version do
    to_string(Application.spec(:controlkeel, :vsn) || "0.1.0")
  end
end
