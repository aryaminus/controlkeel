defmodule ControlKeelWeb.SkillsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Skills.Registry

  @impl true
  def mount(_params, _session, socket) do
    skills = Registry.catalog()

    {:ok,
     socket
     |> assign(:page_title, "Skills Studio")
     |> assign(:skills, skills)
     |> assign(:selected, nil)}
  end

  @impl true
  def handle_event("select_skill", %{"name" => name}, socket) do
    skill = Enum.find(socket.assigns.skills, &(&1.name == name))
    {:noreply, assign(socket, :selected, skill)}
  end

  @impl true
  def handle_event("deselect", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Skills Studio</p>
          <h1 class="ck-section-title">AgentSkills catalog</h1>
          <p class="ck-lead ck-lead-tight">
            Skills are folder-based capability packages that agents discover and activate on demand.
            Each skill is a <code>SKILL.md</code>
            file with instructions, scripts, and resources —
            following the open <a
              href="https://agentskills.io/specification"
              class="ck-link"
              target="_blank"
              rel="noopener"
            >AgentSkills format</a>.
          </p>
        </div>
        <a href={~p"/"} class="ck-link">Back home</a>
      </div>

      <div class="ck-stat-grid">
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Total skills</p>
          <strong>{length(@skills)}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Built-in</p>
          <strong>{Enum.count(@skills, &(&1.scope == "builtin"))}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">User-level</p>
          <strong>{Enum.count(@skills, &(&1.scope == "user"))}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Project-level</p>
          <strong>{Enum.count(@skills, &(&1.scope == "project"))}</strong>
        </div>
      </div>

      <div class="ck-grid ck-grid-dashboard">
        <div>
          <div class="ck-card">
            <p class="ck-mini-label">Available skills</p>
            <div class="ck-finding-list">
              <%= for skill <- @skills do %>
                <article
                  class={"ck-finding-item #{if @selected && @selected.name == skill.name, do: "ck-finding-item-active", else: ""}"}
                  style="cursor: pointer;"
                  phx-click="select_skill"
                  phx-value-name={skill.name}
                >
                  <div class="ck-finding-head">
                    <h3>{skill.name}</h3>
                    <span class={"ck-pill #{scope_pill_class(skill.scope)}"}>{skill.scope}</span>
                  </div>
                  <p class="ck-note">{skill.description}</p>
                  <%= if skill.allowed_tools != [] do %>
                    <div class="ck-tag-list" style="margin-top: 0.4rem;">
                      <%= for tool <- skill.allowed_tools do %>
                        <span class="ck-tag ck-severity-low">{tool}</span>
                      <% end %>
                    </div>
                  <% end %>
                </article>
              <% end %>
            </div>
          </div>
        </div>

        <div>
          <%= if @selected do %>
            <div class="ck-card" style="margin-bottom: 1rem;">
              <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.75rem;">
                <p class="ck-mini-label">{@selected.name}</p>
                <button phx-click="deselect" class="ck-link" style="font-size: 0.8rem;">Close</button>
              </div>
              <p class="ck-note" style="margin-bottom: 0.75rem;">{@selected.description}</p>
              <%= if @selected.compatibility do %>
                <p class="ck-note" style="color: var(--ck-color-muted); margin-bottom: 0.5rem;">
                  Compatibility: {@selected.compatibility}
                </p>
              <% end %>
              <%= if @selected.license do %>
                <p class="ck-note" style="color: var(--ck-color-muted); margin-bottom: 0.5rem;">
                  License: {@selected.license}
                </p>
              <% end %>
              <p
                class="ck-note"
                style="color: var(--ck-color-muted); font-family: monospace; font-size: 0.75rem; word-break: break-all;"
              >
                {@selected.path}
              </p>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Instructions preview</p>
              <pre style="font-size: 0.72rem; line-height: 1.5; white-space: pre-wrap; word-break: break-word; max-height: 500px; overflow-y: auto; margin-top: 0.5rem;"><%= @selected.body %></pre>
            </div>
          <% else %>
            <div class="ck-card" style="margin-bottom: 1rem;">
              <p class="ck-mini-label">How skills work</p>
              <ul class="ck-mini-list">
                <li>Each skill is a directory containing a <code>SKILL.md</code> file</li>
                <li>
                  Agents discover skills via <code>ck_skill_list</code>
                  and activate them with <code>ck_skill_load</code>
                </li>
                <li>Built-in skills ship with ControlKeel and apply to all agents</li>
                <li>
                  Add project skills in <code>.agents/skills/</code> or <code>.claude/skills/</code>
                </li>
                <li>Add user-level skills in <code>~/.agents/skills/</code></li>
              </ul>
            </div>

            <div class="ck-card" style="margin-bottom: 1rem;">
              <p class="ck-mini-label">MCP tools for agents</p>
              <ul class="ck-mini-list">
                <li><code>ck_skill_list</code> — discover available skills and get the catalog</li>
                <li><code>ck_skill_load</code> — load a skill's full instructions by name</li>
              </ul>
              <p class="ck-note" style="margin-top: 0.75rem;">
                Any agent connected via MCP can call these tools. Skills are compatible with
                Claude Code, Cursor, Kiro, LangGraph, AutoGen, Semantic Kernel, n8n, Zapier,
                and all 67 supported agents.
              </p>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Adding your own skills</p>
              <p class="ck-note" style="margin-bottom: 0.5rem;">
                Create a directory with a <code>SKILL.md</code> file using this structure:
              </p>
              <pre
                phx-no-curly-interpolation
                style="font-size: 0.72rem; line-height: 1.5; background: var(--ck-color-surface, #1a1a2e); padding: 0.75rem; border-radius: 4px; margin-top: 0.25rem;"
              >
                ---
                name: my-skill
                description: What this skill does and when to use it.
                license: Apache-2.0
                metadata:
                  author: your-org
                  version: "1.0"
                ---

                # My Skill

                Instructions for the agent go here...</pre>
              <p class="ck-note" style="margin-top: 0.75rem;">
                Place the directory in <code>.agents/skills/my-skill/</code> inside your project
                and ControlKeel will discover it automatically.
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp scope_pill_class("builtin"), do: "ck-pill-critical"
  defp scope_pill_class("user"), do: "ck-pill-medium"
  defp scope_pill_class("project"), do: "ck-pill-neutral"
  defp scope_pill_class(_), do: "ck-pill-neutral"
end
