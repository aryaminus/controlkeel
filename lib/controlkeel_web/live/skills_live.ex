defmodule ControlKeelWeb.SkillsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.ProviderBroker
  alias ControlKeel.Skills

  @impl true
  def mount(_params, _session, socket) do
    project_root = File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Skills Studio")
     |> assign(:selected, nil)
     |> assign(:last_result, nil)
     |> assign(:agent_integrations, Skills.agent_integrations())
     |> assign(:install_channels, Skills.install_channels())
     |> assign(:target_options, target_options())
     |> assign(:scope_options, [{"Export", "export"}, {"User", "user"}, {"Project", "project"}])
     |> assign_analysis(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:action_form, action_form())}
  end

  @impl true
  def handle_event("select_skill", %{"name" => name}, socket) do
    selected = Enum.find(socket.assigns.skills, &(&1.name == name))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("validate_project", %{"project" => %{"project_root" => project_root}}, socket) do
    project_root = String.trim(project_root)

    {:noreply,
     socket
     |> assign_analysis(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:selected, nil)}
  end

  def handle_event("update_action_form", %{"skill_action" => params}, socket) do
    {:noreply, assign(socket, :action_form, action_form(params))}
  end

  def handle_event("copy_command", %{"command" => command}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: command})
     |> put_flash(:info, "Copied command to clipboard.")}
  end

  def handle_event("export", params, socket) do
    project_root = socket.assigns.project_root
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.export(target, project_root, scope: scope) do
        {:ok, plan} ->
          {:info, "Exported #{plan.target} bundle to #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to export skills: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:action_form, action_form(params))
     |> assign_analysis(project_root)}
  end

  def handle_event("install", params, socket) do
    project_root = socket.assigns.project_root
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.install(target, project_root, scope: scope) do
        {:ok, %{destination: destination} = install} ->
          agent_line =
            if Map.has_key?(install, :agent_destination) do
              " Agent: #{install.agent_destination}."
            else
              ""
            end

          {:info, "Installed #{install.target} skills to #{destination}.#{agent_line}"}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:info, "Prepared #{plan.target} bundle at #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to install skills: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:action_form, action_form(params))
     |> assign_analysis(project_root)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Skills Studio</p>
            <h1 class="ck-section-title">Native skills and plugin operator console</h1>
            <p class="ck-lead ck-lead-tight">
              ControlKeel keeps `priv/skills/` as the canonical source of truth, validates every skill package, and can export or install the same capability set for Codex, Claude Code, Copilot / VS Code, and MCP-only tools.
            </p>
          </div>
          <a href={~p"/"} class="ck-link">Back home</a>
        </div>

        <div class="ck-card" style="margin-bottom: 1rem;">
          <.form for={@project_form} id="skills-project-form" phx-submit="validate_project">
            <div class="ck-brief-grid">
              <div>
                <.input
                  field={@project_form[:project_root]}
                  type="text"
                  label="Project root"
                  placeholder="/absolute/path/to/project"
                />
              </div>
              <div class="flex items-end">
                <button type="submit" class="ck-button ck-button-primary" id="skills-project-submit">
                  Refresh catalog
                </button>
              </div>
            </div>
          </.form>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Total skills</p>
            <strong>{length(@skills)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Warnings</p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "warn"))}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Errors</p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "error"))}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Project trust</p>
            <strong>{if @trusted_project?, do: "trusted", else: "gated"}</strong>
          </div>
        </div>

        <div class="ck-card" style="margin: 1rem 0;">
          <p class="ck-mini-label">Install ControlKeel</p>
          <div class="ck-finding-list">
            <%= for channel <- @install_channels do %>
              <article class="ck-finding-item" id={"install-channel-#{channel.id}"}>
                <div class="ck-finding-head">
                  <h3>{channel.label}</h3>
                  <span class="ck-pill ck-pill-neutral">{Enum.join(channel.platforms, ", ")}</span>
                </div>
                <p class="ck-note">{channel.description}</p>
                <div class="flex items-start gap-2" style="margin-top: 0.5rem;">
                  <code>{channel.command}</code>
                  <button
                    type="button"
                    class="ck-link"
                    id={"copy-install-#{channel.id}"}
                    phx-click="copy_command"
                    phx-value-command={channel.command}
                  >
                    Copy
                  </button>
                </div>
              </article>
            <% end %>
          </div>
        </div>

        <div class="ck-card" style="margin: 1rem 0;" id="skills-provider-status">
          <p class="ck-mini-label">Provider and bootstrap status</p>
          <div class="ck-finding-list">
            <article class="ck-finding-item">
              <div class="ck-finding-head">
                <h3>Active provider</h3>
                <span class="ck-pill ck-pill-neutral">{@provider_status["selected_source"]}</span>
              </div>
              <p class="ck-note">
                Provider: {@provider_status["selected_provider"]} / {@provider_status[
                  "selected_model"
                ] || "default"}
              </p>
              <p class="ck-note" style="margin-top: 0.35rem;">
                Bootstrap mode: {@provider_status["bootstrap"]["mode"]}
              </p>
              <p class="ck-note" style="margin-top: 0.35rem;">
                Fallback chain: {Enum.join(@provider_status["fallback_chain"], ", ")}
              </p>
            </article>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="space-y-4">
            <div class="ck-card">
              <p class="ck-mini-label">Available skills</p>
              <div class="ck-finding-list">
                <%= for skill <- @skills do %>
                  <article
                    id={"skill-#{skill.name}"}
                    class={[
                      "ck-finding-item",
                      @selected && @selected.name == skill.name && "ck-finding-item-active"
                    ]}
                    style="cursor: pointer;"
                    phx-click="select_skill"
                    phx-value-name={skill.name}
                  >
                    <div class="ck-finding-head">
                      <h3>{skill.name}</h3>
                      <span class={"ck-pill #{scope_pill_class(skill.scope)}"}>{skill.scope}</span>
                    </div>
                    <p class="ck-note">{skill.description}</p>
                    <p class="ck-note" style="margin-top: 0.35rem;">
                      Targets: {format_targets(skill.compatibility_targets)}
                    </p>
                  </article>
                <% end %>
              </div>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Catalog diagnostics</p>
              <div :if={@diagnostics == []} class="ck-note">No skill diagnostics were recorded.</div>
              <div :if={@diagnostics != []} class="ck-finding-list">
                <%= for diagnostic <- @diagnostics do %>
                  <article class="ck-finding-item">
                    <div class="ck-finding-head">
                      <h3>{diagnostic.code}</h3>
                      <span class={"ck-pill #{diagnostic_pill_class(diagnostic.level)}"}>
                        {diagnostic.level}
                      </span>
                    </div>
                    <p class="ck-note">{diagnostic.message}</p>
                    <p class="ck-note" style="margin-top: 0.35rem; font-family: monospace;">
                      {diagnostic.path}
                    </p>
                  </article>
                <% end %>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="ck-card">
              <p class="ck-mini-label">Export and install</p>
              <.form for={@action_form} id="skills-action-form" phx-change="update_action_form">
                <div class="ck-brief-grid">
                  <div>
                    <.input
                      field={@action_form[:target]}
                      type="select"
                      label="Target"
                      options={@target_options}
                    />
                  </div>
                  <div>
                    <.input
                      field={@action_form[:scope]}
                      type="select"
                      label="Scope"
                      options={@scope_options}
                    />
                  </div>
                </div>
                <div class="ck-action-row" style="margin-top: 1rem;">
                  <button
                    type="button"
                    class="ck-button ck-button-primary"
                    id="skills-export-button"
                    phx-click="export"
                    phx-value-target={@action_form.params["target"]}
                    phx-value-scope={@action_form.params["scope"]}
                  >
                    Export bundle
                  </button>
                  <button
                    type="button"
                    class="ck-button"
                    id="skills-install-button"
                    phx-click="install"
                    phx-value-target={@action_form.params["target"]}
                    phx-value-scope={@action_form.params["scope"]}
                  >
                    Install target
                  </button>
                </div>
              </.form>
              <%= if @last_result do %>
                <p class="ck-note" style="margin-top: 0.85rem;">
                  Last action: {elem(@last_result, 1)}
                </p>
              <% end %>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Target availability</p>
              <div class="ck-table-wrap">
                <table class="min-w-full text-sm" id="skills-target-matrix">
                  <thead>
                    <tr>
                      <th class="text-left py-2 pr-4">Target</th>
                      <th class="text-left py-2 pr-4">Default scope</th>
                      <th class="text-left py-2 pr-4">Native</th>
                      <th class="text-left py-2 pr-4">Release asset</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for target <- @targets do %>
                      <tr id={"skill-target-#{target.id}"}>
                        <td class="py-2 pr-4">
                          <strong>{target.label}</strong>
                          <p class="ck-note">{target.description}</p>
                        </td>
                        <td class="py-2 pr-4">{target.default_scope}</td>
                        <td class="py-2 pr-4">{if target.native, do: "yes", else: "fallback"}</td>
                        <td class="py-2 pr-4">
                          {if target.release_bundle, do: "published", else: "local only"}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Available where</p>
              <div class="ck-table-wrap">
                <table class="min-w-full text-sm" id="skills-agent-matrix">
                  <thead>
                    <tr>
                      <th class="text-left py-2 pr-4">Agent</th>
                      <th class="text-left py-2 pr-4">Attach</th>
                      <th class="text-left py-2 pr-4">Connection</th>
                      <th class="text-left py-2 pr-4">Companion</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for integration <- @agent_integrations do %>
                      <tr id={"agent-#{integration.id}"}>
                        <td class="py-2 pr-4 align-top">
                          <strong>{integration.label}</strong>
                          <p class="ck-note">{human_category(integration.category)}</p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <div class="flex items-start gap-2">
                            <code>{integration.attach_command}</code>
                            <button
                              type="button"
                              class="ck-link"
                              id={"copy-agent-#{integration.id}"}
                              phx-click="copy_command"
                              phx-value-command={integration.attach_command}
                            >
                              Copy
                            </button>
                          </div>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Scope: {Enum.join(integration.supported_scopes, ", ")}
                          </p>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Auto-bootstrap: {if integration.auto_bootstrap, do: "yes", else: "no"}
                          </p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <p class="ck-note">{integration.config_location}</p>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Required CK tools: {format_targets(integration.required_mcp_tools)}
                          </p>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Provider bridge: {format_provider_bridge(integration.provider_bridge)}
                          </p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <p class="ck-note">{integration.companion_delivery}</p>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Export targets: {format_targets(integration.export_targets)}
                          </p>
                          <p class="ck-note" style="margin-top: 0.35rem;">
                            Get CK: {format_install_channels(integration.install_channels)}
                          </p>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="ck-card">
              <%= if @selected do %>
                <p class="ck-mini-label">{@selected.name}</p>
                <p class="ck-note" style="margin-bottom: 0.75rem;">{@selected.description}</p>
                <div class="ck-tag-list" style="margin-bottom: 0.75rem;">
                  <%= for target <- @selected.compatibility_targets do %>
                    <span class="ck-tag ck-severity-low">{target}</span>
                  <% end %>
                </div>
                <p class="ck-note" style="margin-bottom: 0.5rem;">
                  Required CK MCP tools: {format_targets(@selected.required_mcp_tools)}
                </p>
                <p class="ck-note" style="margin-bottom: 0.5rem;">
                  Native locations: {format_paths(
                    get_in(@selected.install_state, ["native_locations"])
                  )}
                </p>
                <p class="ck-note" style="margin-bottom: 0.5rem;">
                  Exported targets: {format_targets(
                    get_in(@selected.install_state, ["exported_targets"])
                  )}
                </p>
                <%= if @selected.resources != [] do %>
                  <p class="ck-mini-label" style="margin-top: 1rem;">Resources</p>
                  <ul class="ck-mini-list">
                    <%= for resource <- @selected.resources do %>
                      <li>{resource}</li>
                    <% end %>
                  </ul>
                <% end %>
                <%= if @selected.diagnostics != [] do %>
                  <p class="ck-mini-label" style="margin-top: 1rem;">Skill diagnostics</p>
                  <ul class="ck-mini-list">
                    <%= for diagnostic <- @selected.diagnostics do %>
                      <li>[{diagnostic.level}] {diagnostic.code} — {diagnostic.message}</li>
                    <% end %>
                  </ul>
                <% end %>
                <p class="ck-mini-label" style="margin-top: 1rem;">Instructions preview</p>
                <pre style="font-size: 0.72rem; line-height: 1.5; white-space: pre-wrap; word-break: break-word; max-height: 420px; overflow-y: auto; margin-top: 0.5rem;">{@selected.body}</pre>
              <% else %>
                <p class="ck-mini-label">How this works</p>
                <ul class="ck-mini-list">
                  <li>`priv/skills/` is the canonical built-in source of truth.</li>
                  <li>`ck_skill_list` and `ck_skill_load` remain the universal MCP fallback.</li>
                  <li>
                    Native targets are generated from the same catalog instead of being hand-maintained.
                  </li>
                  <li>
                    Project-local skills are only loaded when the project is trusted by ControlKeel.
                  </li>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp assign_analysis(socket, project_root) do
    analysis = Skills.analyze(project_root)
    provider_status = ProviderBroker.status(project_root)

    socket
    |> assign(:project_root, project_root)
    |> assign(:skills, analysis.skills)
    |> assign(:diagnostics, analysis.diagnostics)
    |> assign(:targets, Skills.targets())
    |> assign(:trusted_project?, analysis.trusted_project?)
    |> assign(:provider_status, provider_status)
  end

  defp project_form(project_root), do: to_form(%{"project_root" => project_root}, as: :project)

  defp action_form(params \\ %{"target" => "open-standard", "scope" => "export"}) do
    to_form(params, as: :skill_action)
  end

  defp target_options do
    Enum.map(Skills.targets(), fn target -> {target.label, target.id} end)
  end

  defp format_targets([]), do: "none"
  defp format_targets(nil), do: "none"
  defp format_targets(values), do: Enum.join(values, ", ")

  defp format_install_channels([]), do: "none"

  defp format_install_channels(ids) do
    ids
    |> ControlKeel.Distribution.install_channels()
    |> Enum.map(& &1.label)
    |> Enum.join(", ")
  end

  defp format_paths([]), do: "not installed"
  defp format_paths(nil), do: "not installed"
  defp format_paths(paths), do: Enum.join(paths, ", ")

  defp scope_pill_class("builtin"), do: "ck-pill-critical"
  defp scope_pill_class("user"), do: "ck-pill-medium"
  defp scope_pill_class("project"), do: "ck-pill-neutral"
  defp scope_pill_class(_), do: "ck-pill-neutral"

  defp diagnostic_pill_class("error"), do: "ck-pill-critical"
  defp diagnostic_pill_class("warn"), do: "ck-pill-medium"
  defp diagnostic_pill_class(_), do: "ck-pill-neutral"

  defp human_category("native-first"), do: "Native skills install on attach"
  defp human_category("repo-native"), do: "Repo-native skills, agents, and plugin bundles"

  defp human_category("mcp-plus-instructions"),
    do: "MCP attach plus generated instruction snippets"

  defp human_category(_), do: "Portable MCP fallback"

  defp format_provider_bridge(%{supported: true, provider: provider}), do: "#{provider} bridge"
  defp format_provider_bridge(_bridge), do: "none"
end
