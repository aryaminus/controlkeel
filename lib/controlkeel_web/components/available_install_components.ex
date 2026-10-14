defmodule ControlKeelWeb.AvailableInstallComponents do
  use Phoenix.Component

  attr :agent_integrations, :list, required: true

  def available_where(assigns) do
    ~H"""
    <div class="border rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-10">
      <p class="text-lg font-semibold text-primary tracking-[0.14em] uppercase">
        Available where
      </p>

      <style>
        .scrollbar-thin::-webkit-scrollbar { width: 6px; }
        .scrollbar-thin::-webkit-scrollbar-track { background: transparent; }
        .scrollbar-thin::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
        .scrollbar-thin::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
      </style>
      <div
        class="max-h-[520px] overflow-y-auto mt-4 space-y-4 scrollbar-thin"
        style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
      >
        <%= for integration <- @agent_integrations do %>
          <details
            id={"agent-#{integration.id}"}
            class="group border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] bg-[rgba(255,255,255,0.03)] open:bg-[rgba(255,255,255,0.05)] transition-colors duration-200"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 select-none [&::-webkit-details-marker]:hidden">
              <p class="text-lg font-semibold">{integration.label}</p>
              <span class="text-xs text-muted-foreground transition-transform duration-200 group-open:rotate-180">
                ▼
              </span>
            </summary>

            <div class="flex justify-end">
              <span class="border rounded-full px-3 py-[0.45rem] text-[0.8rem] w-fit">
                {human_support_class(integration.support_class)}
              </span>
            </div>

            <div class="space-y-8 px-5 pb-5">
              <div class="space-y-1.5">
                <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
                  How agent uses CK
                </p>
                <p class="text-muted-foreground text-sm">
                  Uses CK via: {format_targets(integration.agent_uses_ck_via)}
                </p>

                <p class="text-muted-foreground text-sm">
                  Scope: {format_targets(integration.supported_scopes)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Install: {human_install_experience(integration.install_experience)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Auto-bootstrap: {if integration.auto_bootstrap, do: "yes", else: "no"}
                </p>

                <%= if integration.attach_command do %>
                  <div class="flex items-stretch gap-0 overflow-hidden rounded-xl border bg-[rgba(0,0,0,0.25)] mt-4">
                    <code class="flex-1 px-3 py-2 text-sm leading-relaxed font-mono truncate">
                      {integration.attach_command}
                    </code>
                    <button
                      type="button"
                      class="flex items-center gap-1 px-3 py-2 text-xs font-semibold text-primary bg-[rgba(196,240,66,0.08)] hover:bg-[rgba(196,240,66,0.16)] transition-colors duration-150 border-l whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
                      id={"copy-agent-#{integration.id}"}
                      aria-label="Copy attach command"
                      title="Copy attach command"
                      phx-click="copy_command"
                      phx-value-command={integration.attach_command}
                    >
                      Copy
                    </button>
                  </div>
                <% else %>
                  <code class="text-sm">
                    {integration.runtime_export_command || alias_action(integration)}
                  </code>
                <% end %>
              </div>

              <div class="space-y-1.5">
                <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
                  How CK runs the agent
                </p>
                <p class="text-muted-foreground text-sm">
                  CK runs via: {integration.ck_runs_agent_via || "none"}
                </p>
                <p class="text-muted-foreground text-sm">
                  Execution: {integration.execution_support || "inbound_only"}
                </p>
                <p class="text-muted-foreground text-sm">
                  Review: {human_review_experience(integration.review_experience)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Submit / feedback: {integration.submission_mode} / {integration.feedback_mode}
                </p>
                <p class="text-muted-foreground text-sm">
                  Phase / embed: {human_phase_model(integration.phase_model)} / {human_browser_embed(
                    integration.browser_embed
                  )}
                </p>
                <p class="text-muted-foreground text-sm">
                  Runtime / review transport: {integration.runtime_transport || "artifact_only"} / {integration.runtime_review_transport ||
                    "artifact_only"}
                </p>
                <p class="text-muted-foreground text-sm">
                  Subagent visibility: {human_subagent_visibility(integration.subagent_visibility)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Autonomy: {integration.autonomy_mode || "policy_gated"}
                </p>
                <p class="text-muted-foreground text-sm">{integration.config_location}</p>
                <p class="text-muted-foreground text-sm">
                  Required CK tools: {format_targets(integration.required_mcp_tools)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Auth: {integration.auth_mode} / {auth_owner(integration)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Provider bridge: {format_provider_bridge(integration.provider_bridge)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Runtime auth owner: {integration.runtime_auth_owner || "none"}
                </p>
                <p class="text-muted-foreground text-sm">
                  MCP / skills: {integration.mcp_mode} / {integration.skills_mode}
                </p>
              </div>

              <div class="space-y-1.5">
                <p class="text-xs font-semibold text-primary tracking-[0.14em] uppercase">
                  Companion and policy
                </p>
                <p class="text-muted-foreground text-sm">{integration.companion_delivery}</p>
                <p class="text-muted-foreground text-sm">
                  Export targets: {format_targets(integration.export_targets)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Plan phases: {format_targets(integration.plan_phase_support)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Runtime sessions: {format_runtime_session_support(
                    integration.runtime_session_support
                  )}
                </p>
                <p class="text-muted-foreground text-sm">
                  Files written: {format_paths(integration.artifact_surfaces)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Package outputs: {format_package_outputs(integration.package_outputs)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Direct install: {format_direct_install_methods(integration.direct_install_methods)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Human intervention: {human_intervention_copy(integration)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Confidence: {human_confidence_level(integration.confidence_level)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Upstream: {integration.upstream_slug || "n/a"}
                </p>
                <p class="text-muted-foreground text-sm">
                  ACP registry: {registry_label(integration)}
                </p>
                <p class="text-muted-foreground text-sm">
                  Get CK: {format_install_channels(integration.install_channels)}
                </p>
              </div>
            </div>
          </details>
        <% end %>
      </div>
    </div>
    """
  end

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
