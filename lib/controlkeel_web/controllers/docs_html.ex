defmodule ControlKeelWeb.DocsHTML do
  use ControlKeelWeb, :html

  embed_templates "docs_html/*"

  defp format_targets([]), do: "none"
  defp format_targets(nil), do: "none"
  defp format_targets(values), do: Enum.join(values, ", ")

  defp format_install_channels([]), do: "none"
  defp format_install_channels(nil), do: "none"

  defp format_install_channels(ids) do
    ids
    |> ControlKeel.Ops.Distribution.install_channels()
    |> Enum.map(& &1.label)
    |> Enum.join(", ")
  end

  defp format_paths([]), do: "not installed"
  defp format_paths(nil), do: "not installed"
  defp format_paths(paths), do: Enum.join(paths, ", ")

  defp format_package_outputs([]), do: "none"
  defp format_package_outputs(nil), do: "none"

  defp format_package_outputs(outputs) do
    outputs
    |> Enum.map(fn output ->
      case output do
        %{"artifact" => artifact, "kind" => kind} -> "#{kind}: #{artifact}"
        %{artifact: artifact, kind: kind} -> "#{kind}: #{artifact}"
        other -> inspect(other)
      end
    end)
    |> Enum.join(", ")
  end

  defp format_direct_install_methods([]), do: "attach only"
  defp format_direct_install_methods(nil), do: "attach only"

  defp format_direct_install_methods(methods) do
    methods
    |> Enum.map(fn method ->
      case method do
        %{"label" => label, "command" => command} -> "#{label}: #{command}"
        %{label: label, command: command} -> "#{label}: #{command}"
        other -> inspect(other)
      end
    end)
    |> Enum.join(" | ")
  end

  defp format_runtime_session_support(nil), do: "none"
  defp format_runtime_session_support(%{} = support) when map_size(support) == 0, do: "none"

  defp format_runtime_session_support(%{} = support) do
    support
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.join(", ")
  end

  defp human_support_class("attach_client"), do: "Attachable client"
  defp human_support_class("headless_runtime"), do: "Headless runtime"
  defp human_support_class("framework_adapter"), do: "Framework adapter"
  defp human_support_class("provider_only"), do: "Provider-only"
  defp human_support_class("alias"), do: "Alias"
  defp human_support_class("unverified"), do: "Unverified"
  defp human_support_class(_), do: "Portable integration"

  defp human_install_experience("first_class"), do: "first-class"
  defp human_install_experience("guided"), do: "guided"
  defp human_install_experience("fallback"), do: "fallback"
  defp human_install_experience(_value), do: "guided"

  defp human_review_experience("native_review"), do: "native review"
  defp human_review_experience("browser_review"), do: "browser review"
  defp human_review_experience("feedback_only"), do: "feedback only"
  defp human_review_experience("none"), do: "none"
  defp human_review_experience(_value), do: "browser review"

  defp human_phase_model("host_plan_mode"), do: "host plan mode"
  defp human_phase_model("file_plan_mode"), do: "file plan mode"
  defp human_phase_model("review_only"), do: "review only"
  defp human_phase_model(_value), do: "review only"

  defp human_browser_embed("external"), do: "external browser"
  defp human_browser_embed("vscode_webview"), do: "VS Code webview"
  defp human_browser_embed("none"), do: "none"
  defp human_browser_embed(_value), do: "external browser"

  defp human_subagent_visibility("primary_only"), do: "primary only"
  defp human_subagent_visibility("all"), do: "all agents"
  defp human_subagent_visibility("none"), do: "none"
  defp human_subagent_visibility(_value), do: "none"

  defp human_confidence_level("shipped"), do: "shipped"
  defp human_confidence_level("experimental"), do: "experimental"
  defp human_confidence_level("research"), do: "research"
  defp human_confidence_level(_value), do: "shipped"

  defp alias_action(%{alias_of: alias_of}) when is_binary(alias_of), do: "Use #{alias_of}"
  defp alias_action(_integration), do: "reference only"

  defp auth_owner(integration), do: ControlKeel.Agent.Integration.auth_owner(integration)

  defp format_provider_bridge(%{supported: true, provider: provider, mode: mode}),
    do: "#{mode}: #{provider}"

  defp format_provider_bridge(%{"supported" => true, "provider" => provider, "mode" => mode}),
    do: "#{mode}: #{provider}"

  defp format_provider_bridge(%{supported: true, mode: mode}), do: mode
  defp format_provider_bridge(%{"supported" => true, "mode" => mode}), do: mode

  defp format_provider_bridge(%{mode: "ck_owned"}), do: "ck-owned"
  defp format_provider_bridge(%{"mode" => "ck_owned"}), do: "ck-owned"

  defp format_provider_bridge(_bridge), do: "none"

  defp registry_label(%{registry_match: true, registry_version: version, registry_stale: stale}) do
    suffix = if stale, do: " (stale cache)", else: ""
    "matched #{version || "unknown"}#{suffix}"
  end

  defp registry_label(_integration), do: "not matched"

  defp human_intervention_copy(%{execution_support: "direct"}),
    do: "Only when findings or approvals block execution"

  defp human_intervention_copy(%{execution_support: "handoff"}),
    do: "Required to continue from the generated handoff package"

  defp human_intervention_copy(%{execution_support: "runtime"}),
    do: "Only when the remote runtime pauses or policy gates block"

  defp human_intervention_copy(_integration), do: "Use ControlKeel from the agent side only"
end
