defmodule ControlKeelWeb.OnboardingLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    occupation = default_occupation()
    attrs = default_attrs(occupation)
    project_root = socket.endpoint.config(:project_root) || File.cwd!()
    mode = Mode.current()
    cloud_mode = mode in [:cloud, :self_hosted]

    {:ok,
     socket
     |> assign(:page_title, "Start a session")
     |> assign(:project_root, project_root)
     |> assign(:mode, mode)
     |> assign(:cloud_mode, cloud_mode)
     |> assign(:occupation_profiles, Intent.occupation_profiles())
     |> assign(:agent_options, Intent.agent_options())
     |> assign(:step, 1)
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(occupation))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)
     |> assign(:compiled_brief, nil)
     |> assign(:compiled_boundary_summary, Intent.boundary_summary(nil))
     |> assign(:started?, false)
     |> assign(
       :recent_sessions,
       Mission.list_recent_sessions_for_user(socket.assigns[:current_user])
     )
     |> assign_org_context(cloud_mode)
     |> assign_form()}
  end

  # URL-driven scope selection (issue #183): `?org_slug`/`?ws_slug` are the
  # source of truth for the picker. Mount seeds defaults (first admin/owner
  # org + first workspace); handle_params then applies the URL on top, so
  # re-renders and back/forward never lose the selection.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_scope_params(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"launch" => params}, socket) do
    attrs = merge_launch_attrs(socket.assigns.attrs, params)

    {:noreply,
     socket
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(attrs["occupation"]))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:compile_error, nil)
     |> assign_form()}
  end

  @impl true
  def handle_event("select_org", %{"org_id" => org_id}, socket) do
    case parse_org_id(org_id, socket.assigns.org_options) do
      nil ->
        # Unknown/mangled option id: keep the previous valid selection and
        # surface why, instead of blanking the picker (issue #183).
        {:noreply, put_scope_notice(socket, "That organization is not available.")}

      org_id ->
        # Keep the current workspace when it is still valid for the target
        # org; otherwise fall back to the org's first workspace. The URL is
        # the selection state — patch it and let handle_params re-apply.
        workspaces = load_workspaces(org_id)
        org_slug = org_slug_for_id(socket.assigns.org_options, org_id)
        ws_slug = workspace_slug_for_id(workspaces, socket.assigns.selected_workspace_id)

        {:noreply,
         socket
         |> push_patch(to: scope_path(org_slug, ws_slug))}
    end
  end

  @impl true
  def handle_event("select_workspace", %{"workspace_id" => workspace_id}, socket) do
    case parse_workspace_id(workspace_id, socket.assigns.workspace_options) do
      nil ->
        {:noreply, put_scope_notice(socket, "That workspace is not available.")}

      workspace_id ->
        org_slug = org_slug_for_id(socket.assigns.org_options, socket.assigns.selected_org_id)
        ws_slug = option_workspace_slug(socket.assigns.workspace_options, workspace_id)

        {:noreply,
         socket
         |> push_patch(to: scope_path(org_slug, ws_slug))}
    end
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, max(socket.assigns.step - 1, 1))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)}
  end

  @impl true
  def handle_event(
        "next",
        %{"launch" => _params},
        %{assigns: %{cloud_mode: true, can_onboard: false}} = socket
      ) do
    {:noreply, put_flash(socket, :error, onboarding_block_message(socket))}
  end

  @impl true
  def handle_event("next", %{"launch" => params}, socket) do
    attrs = merge_launch_attrs(socket.assigns.attrs, params)
    questions = Intent.interview_questions(attrs["occupation"])

    case validate_step(socket.assigns.step, attrs, questions) do
      {:ok, attrs} when socket.assigns.step < 3 ->
        socket =
          socket
          |> maybe_emit_interview_started(attrs)
          |> emit_interview_step_completed(attrs)
          |> assign(:attrs, attrs)
          |> assign(:interview_questions, questions)
          |> assign(:preflight, Intent.preflight_context(attrs))
          |> assign(:errors, %{})
          |> assign(:step, socket.assigns.step + 1)
          |> assign_form()

        {:noreply, socket}

      {:ok, attrs} ->
        socket =
          socket
          |> maybe_emit_interview_started(attrs)
          |> emit_interview_step_completed(attrs)
          |> assign(:attrs, attrs)
          |> assign(:interview_questions, questions)
          |> assign(:preflight, Intent.preflight_context(attrs))

        compile_brief(socket, attrs)

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:interview_questions, questions)
         |> assign(:preflight, Intent.preflight_context(attrs))
         |> assign(:errors, errors)
         |> assign_form()}
    end
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    compile_brief(socket, socket.assigns.attrs)
  end

  @impl true
  def handle_event(
        "accept",
        _params,
        %{assigns: %{cloud_mode: true, can_onboard: false}} = socket
      ) do
    {:noreply, put_flash(socket, :error, onboarding_block_message(socket))}
  end

  @impl true
  def handle_event("accept", _params, %{assigns: %{compiled_brief: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Compile the brief before creating a mission.")}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    attrs = maybe_put_workspace_id(socket.assigns.attrs, socket)

    case Mission.create_launch_from_brief(attrs, socket.assigns.compiled_brief) do
      {:ok, session} ->
        # Flash = creation confirmation; `?launched=1` keeps the
        # attach-instructions banner on the session page (issue #183).
        case Repo.preload(session, workspace: :org) do
          %{workspace: %{org: %{slug: org_slug}, slug: ws_slug}} = session ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Session \"#{session.title}\" created in #{session.workspace.name}."
             )
             |> push_navigate(
               to: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}?launched=1"
             )}

          _ ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Session created but its workspace is not bound to an organization."
             )
             |> assign(:step, 4)}
        end

      {:error, :workspace_not_found} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "No workspace is available for this mission. Choose an organization and workspace before continuing."
         )
         |> assign(:step, 4)}

      {:error, _scope, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "ControlKeel could not create the session from this brief.")
         |> assign(:step, 4)}
    end
  end

  @impl true
  def handle_event("select_mission", params, socket) do
    id = params["id"] || params["recent_mission_id"]

    case id do
      "" ->
        {:noreply, socket}

      nil ->
        {:noreply, socket}

      id ->
        # Client-supplied ids are untrusted: parse safely and enforce the
        # same access gate as the session pages before reading the brief
        # (issue #183 — the picker must never leak another user's session).
        with {id, ""} <- Integer.parse(to_string(id)),
             session when not is_nil(session) <- Mission.get_session(id),
             true <- Accounts.session_accessible?(session, socket.assigns[:current_user]) do
          brief = session.execution_brief || %{}
          interview_answers = get_in(brief, ["compiler", "interview_answers"]) || %{}
          idea = Map.get(brief, "idea", session.objective)

          attrs =
            socket.assigns.attrs
            |> Map.merge(%{
              "project_name" => session.title,
              "idea" => idea,
              "interview_answers" => interview_answers
            })

          {:noreply,
           socket
           |> assign(:attrs, attrs)
           |> assign(:interview_questions, Intent.interview_questions(attrs["occupation"]))
           |> assign_form()}
        else
          _ ->
            {:noreply, put_flash(socket, :error, "Selected session not found.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full space-y-6">
      <div class="space-y-4 text-center sm:text-left">
        <.page_title
          title="Start a session"
          subtitle="Scope it, describe the product, answer the interview, then review the compiled brief."
        />
        <ControlKeelWeb.SessionStartLayouts.steps step={@step} cloud_mode={@cloud_mode} />
      </div>

      <%= if @cloud_mode do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card" aria-label="Scope">
          <div class="flex items-center justify-between gap-3">
            <.section_title>Organization and workspace</.section_title>
            <span class="rounded-full border px-3 py-1 text-xs text-muted-foreground">
              Step 0 · Scope
            </span>
          </div>
          <p class="mt-1 text-sm text-muted-foreground">
            Choose where this session will be created.
          </p>

          <%!-- LV 1.x only fires phx-change on inputs inside a form; input-level
             bindings are preserved and the client serializes only the bound
             input name/value. --%>
          <form id="onboarding-scope-form">
            <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div class="space-y-1.5">
                <label
                  for="onboarding-org-select"
                  class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono"
                >
                  Organization
                </label>
                <select
                  id="onboarding-org-select"
                  name="org_id"
                  phx-change="select_org"
                  class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                >
                  <%= for {id, name, _slug} <- @org_options do %>
                    <option value={id} selected={@selected_org_id == id}>{name}</option>
                  <% end %>
                </select>
              </div>

              <div class="space-y-1.5">
                <label
                  for="onboarding-workspace-select"
                  class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono"
                >
                  Workspace
                </label>
                <select
                  id="onboarding-workspace-select"
                  name="workspace_id"
                  phx-change="select_workspace"
                  class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                >
                  <%= for {id, name, _slug} <- @workspace_options do %>
                    <option value={id} selected={@selected_workspace_id == id}>{name}</option>
                  <% end %>
                </select>
              </div>
            </div>
          </form>

          <%= if @scope_notice do %>
            <div class="mt-4 flex flex-col gap-2 rounded-xl border border-warning/20 bg-warning/10 p-4">
              <p class="text-sm text-warning font-medium">
                {@scope_notice}
              </p>
            </div>
          <% end %>

          <%= if @onboarding_notice do %>
            <div class="mt-4 flex flex-col gap-2 rounded-xl border border-warning/20 bg-warning/10 p-4">
              <p class="text-sm text-warning font-medium">
                {@onboarding_notice.text}
              </p>
              <%= if @onboarding_notice.link do %>
                <.link
                  navigate={@onboarding_notice.link}
                  class="text-xs font-semibold text-primary hover:text-primary/80 underline underline-offset-4"
                >
                  {@onboarding_notice.link_text}
                </.link>
              <% end %>
            </div>
          <% end %>
        </section>
      <% end %>

      <div class="grid grid-cols-1 items-start gap-6">
        <section
          class="rounded-2xl border bg-card p-5 shadow-card"
          aria-label="Setup wizard"
        >
          <.form for={@form} phx-change="validate" phx-submit="next" id="onboarding-wizard-form">
            <%= case @step do %>
              <% 1 -> %>
                <div class="space-y-6">
                  <div>
                    <p class="text-xs font-semibold tracking-wider text-primary uppercase font-mono">
                      Step 1 of 4
                    </p>
                    <h2 class="text-2xl font-serif text-foreground mt-1">
                      Choose the domain and primary agent
                    </h2>
                  </div>

                  <div class="space-y-1.5">
                    <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                      Domain profile
                    </label>
                    <select
                      name="launch[occupation]"
                      class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                    >
                      <%= for profile <- @occupation_profiles do %>
                        <option value={profile.id} selected={@attrs["occupation"] == profile.id}>
                          {profile.label}
                        </option>
                      <% end %>
                    </select>
                    <%= if error = field_error(@errors, "occupation") do %>
                      <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                    <% end %>
                    <p class="text-xs text-muted-foreground leading-relaxed">
                      {@preflight.occupation.description}
                    </p>
                    <p class="text-xs text-muted-foreground">
                      Domain pack: {@preflight.occupation.domain_pack} · preliminary risk: {@preflight.preliminary_risk_tier}
                    </p>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 pt-4 border-t">
                    <div class="space-y-1.5">
                      <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                        Primary agent
                      </label>
                      <select
                        name="launch[agent]"
                        class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                      >
                        <%= for {id, label} <- @agent_options do %>
                          <option value={id} selected={@attrs["agent"] == id}>{label}</option>
                        <% end %>
                      </select>
                      <%= if error = field_error(@errors, "agent") do %>
                        <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                      <% end %>
                    </div>

                    <div class="space-y-1.5">
                      <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                        Daily budget (USD)
                      </label>
                      <input
                        type="number"
                        name="launch[budget]"
                        value={@attrs["budget"]}
                        min="0"
                        max="500"
                        step="5"
                        placeholder="30"
                        class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                      />
                      <%= if error = field_error(@errors, "budget") do %>
                        <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% 2 -> %>
                <div class="space-y-6">
                  <div>
                    <p class="text-xs font-semibold tracking-wider text-primary uppercase font-mono">
                      Step 2 of 4
                    </p>
                    <h2 class="text-2xl font-serif text-foreground mt-1">
                      Describe the product
                    </h2>
                  </div>

                  <div class="space-y-4">
                    <div class="space-y-1.5">
                      <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                        Project name
                      </label>
                      <input
                        type="text"
                        name="launch[project_name]"
                        value={@attrs["project_name"]}
                        placeholder="e.g., Clinic Intake Portal"
                        class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                      />
                      <%= if error = field_error(@errors, "project_name") do %>
                        <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                      <% end %>
                    </div>

                    <div class="space-y-1.5">
                      <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                        Core product prompt
                      </label>
                      <textarea
                        name="launch[idea]"
                        rows="8"
                        placeholder="Describe what you want built in plain language."
                        class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                      ><%= @attrs["idea"] %></textarea>
                      <%= if error = field_error(@errors, "idea") do %>
                        <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                      <% end %>
                    </div>
                  </div>

                  <%= if @recent_sessions != [] do %>
                    <div class="border-t pt-6">
                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Or continue from an existing session
                        </label>
                        <select
                          id="onboarding-recent-session-select"
                          name="recent_mission_id"
                          class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                          phx-change="select_mission"
                        >
                          <option value="">Select a recent mission...</option>
                          <%= for session <- @recent_sessions do %>
                            <option value={session.id}>{session.title}</option>
                          <% end %>
                        </select>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% 3 -> %>
                <div class="space-y-6">
                  <div>
                    <p class="text-xs font-semibold tracking-wider text-primary uppercase font-mono">
                      Step 3 of 4
                    </p>
                    <h2 class="text-2xl font-serif text-foreground mt-1">
                      Answer the guided interview
                    </h2>
                  </div>

                  <div class="space-y-6">
                    <%= for question <- @interview_questions do %>
                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          {question.label}
                        </label>
                        <p class="text-xs text-muted-foreground leading-relaxed">{question.prompt}</p>
                        <textarea
                          name={"launch[interview_answers][#{question.id}]"}
                          rows="4"
                          placeholder={question.placeholder}
                          class="w-full border border-input bg-background hover:border-primary rounded-xl px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition"
                        ><%= Map.get(@attrs["interview_answers"], question.id, "") %></textarea>
                        <%= if error = field_error(@errors, "interview_answers.#{question.id}") do %>
                          <p class="text-xs text-destructive font-medium mt-1">{error}</p>
                        <% end %>
                      </div>
                    <% end %>
                    <%= if @compile_error do %>
                      <p class="text-sm text-[var(--ck-warning)] font-medium bg-[var(--ck-warning)]/5 border border-[var(--ck-warning)]/20 rounded-xl p-4 mt-2">
                        {@compile_error}
                      </p>
                    <% end %>
                  </div>
                </div>
              <% 4 -> %>
                <div class="space-y-6">
                  <div>
                    <p class="text-xs font-semibold tracking-wider text-primary uppercase font-mono">
                      Step 4 of 4
                    </p>
                    <h2 class="text-2xl font-serif text-foreground mt-1">
                      Review the compiled brief
                    </h2>
                  </div>

                  <%= if @compiled_brief do %>
                    <% brief = Intent.to_brief_map(@compiled_brief) %>
                    <% compiler = brief["compiler"] || %{} %>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4 border-b pb-6">
                      <div>
                        <h4 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Objective
                        </h4>
                        <p class="text-muted-foreground text-sm mt-1 leading-relaxed">
                          {brief["objective"]}
                        </p>
                      </div>
                      <div>
                        <h4 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Project Name
                        </h4>
                        <p class="text-muted-foreground text-sm mt-1 leading-relaxed">
                          {@attrs["project_name"]}
                        </p>
                      </div>
                      <div class="md:col-span-2">
                        <h4 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Core Product Prompt
                        </h4>
                        <p class="text-muted-foreground text-sm mt-1 leading-relaxed">
                          {@attrs["idea"]}
                        </p>
                      </div>
                      <div>
                        <h4 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Next Step
                        </h4>
                        <p class="text-muted-foreground text-sm mt-1 leading-relaxed">
                          {brief["next_step"]}
                        </p>
                      </div>
                      <div>
                        <h4 class="text-xs font-semibold text-muted-foreground uppercase tracking-wider font-mono">
                          Compiler Info
                        </h4>
                        <p class="text-muted-foreground text-sm mt-1 leading-relaxed">
                          {compiler["provider"]} / {compiler["model"]}
                        </p>
                      </div>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6 pt-2">
                      <div class="rounded-xl border bg-card/20 p-4">
                        <h4 class="text-xs font-semibold text-primary uppercase tracking-wider font-mono mb-2">
                          Acceptance criteria
                        </h4>
                        <p class="text-xs text-muted-foreground leading-relaxed whitespace-pre-line">
                          {brief["acceptance_criteria"]}
                        </p>
                      </div>

                      <div class="rounded-xl border bg-card/20 p-4">
                        <h4 class="text-xs font-semibold text-primary uppercase tracking-wider font-mono mb-2">
                          Production boundary
                        </h4>
                        <div class="space-y-3">
                          <div class="grid grid-cols-2 gap-2 text-xs">
                            <div>
                              <span class="text-muted-foreground block font-mono text-[10px] uppercase">
                                Risk Tier
                              </span>
                              <span class="text-muted-foreground font-medium">
                                {boundary_value(@compiled_boundary_summary, "risk_tier")}
                              </span>
                            </div>
                            <div>
                              <span class="text-muted-foreground block font-mono text-[10px] uppercase">
                                Launch Window
                              </span>
                              <span class="text-muted-foreground font-medium">
                                {boundary_value(@compiled_boundary_summary, "launch_window")}
                              </span>
                            </div>
                          </div>
                          <div>
                            <span class="text-muted-foreground text-xs block font-mono text-[10px] uppercase">
                              Budget Note
                            </span>
                            <span class="text-muted-foreground text-xs font-medium leading-relaxed">
                              {boundary_value(@compiled_boundary_summary, "budget_note")}
                            </span>
                          </div>
                          <div>
                            <span class="text-muted-foreground text-xs block mb-1 font-mono text-[10px] uppercase">
                              Constraints
                            </span>
                            <p class="text-xs text-muted-foreground leading-relaxed">
                              {boundary_text(@compiled_boundary_summary, "constraints")}
                            </p>
                          </div>
                        </div>
                      </div>

                      <div class="rounded-xl border bg-card/20 p-4 md:col-span-2">
                        <h4 class="text-xs font-semibold text-primary uppercase tracking-wider font-mono mb-2">
                          Governance that will apply
                        </h4>
                        <p class="text-xs text-muted-foreground leading-relaxed">
                          This session will be governed under the {@preflight.occupation.domain_pack} domain pack
                          at preliminary risk {@preflight.preliminary_risk_tier}. {@preflight.validation_language} High-risk and destructive actions route to human review.
                        </p>
                        <div class="flex flex-wrap gap-1 mt-2">
                          <%= for item <- @preflight.compliance do %>
                            <span class="px-2 py-0.5 rounded-md text-[10px] font-medium bg-muted text-muted-foreground border border-border">
                              {item}
                            </span>
                          <% end %>
                        </div>
                      </div>

                      <div class="rounded-xl border bg-card/20 p-4 md:col-span-2">
                        <h4 class="text-xs font-semibold text-primary uppercase tracking-wider font-mono mb-2">
                          Open Questions
                        </h4>
                        <ul class="text-xs text-muted-foreground space-y-1.5 list-disc list-inside">
                          <%= for item <- brief["open_questions"] || [] do %>
                            <li>{item}</li>
                          <% end %>
                        </ul>
                      </div>
                    </div>
                  <% else %>
                    <p class="text-muted-foreground text-sm">The brief is not available yet.</p>
                  <% end %>
                </div>
            <% end %>

            <div class="flex items-center justify-between gap-4 mt-8 pt-4 border-t">
              <%= if @step > 1 do %>
                <button
                  class="px-4 py-2 text-xs font-semibold uppercase tracking-wider text-primary hover:text-primary transition font-mono"
                  type="button"
                  phx-click="back"
                >
                  Back
                </button>
              <% else %>
                <div></div>
              <% end %>

              <button
                :if={@step < 4}
                disabled={not @can_onboard}
                class={[
                  "px-6 py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm transition-all duration-200",
                  "hover:bg-primary hover:shadow-[0_0_20px_rgba(196,240,66,0.3)]",
                  not @can_onboard && "opacity-50 cursor-not-allowed"
                ]}
                type="submit"
              >
                {if @step == 3, do: "Compile brief", else: "Continue"}
              </button>

              <div :if={@step == 4} class="flex flex-wrap items-center justify-between gap-4">
                <button
                  class="px-6 py-2.5 rounded-full bg-card text-muted-foreground font-semibold text-sm hover:bg-muted hover:text-foreground transition-all duration-200"
                  phx-click="regenerate"
                >
                  Regenerate
                </button>
                <button
                  disabled={not @can_onboard}
                  class={[
                    "px-6 py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm transition-all duration-200",
                    "hover:bg-primary hover:shadow-[0_0_20px_rgba(196,240,66,0.3)]",
                    not @can_onboard && "opacity-50 cursor-not-allowed"
                  ]}
                  type="button"
                  phx-click="accept"
                >
                  Create session
                </button>
              </div>
            </div>
          </.form>
        </section>
      </div>
    </div>
    """
  end

  defp compile_brief(socket, attrs) do
    case Intent.compile(attrs) do
      {:ok, brief} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:errors, %{})
         |> assign(:compile_error, nil)
         |> assign(:compiled_brief, brief)
         |> assign(
           :compiled_boundary_summary,
           Intent.boundary_summary(brief)
         )
         |> assign(:step, 4)
         |> assign_form()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:compile_error, compile_error_message(reason))
         |> assign(:errors, %{})
         |> assign_form()}
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(socket.assigns.attrs, as: :launch))
  end

  defp assign_org_context(socket, false) do
    socket
    |> assign(:org_options, [])
    |> assign(:workspace_options, [])
    |> assign(:selected_org_id, nil)
    |> assign(:selected_workspace_id, nil)
    |> assign(:can_onboard, true)
    |> assign(:onboarding_notice, nil)
    |> assign(:scope_notice, nil)
  end

  # Defaults: first admin/owner org + its first workspace (issue #183 — the
  # URL params applied later by handle_params take precedence over these).
  defp assign_org_context(socket, true) do
    case socket.assigns[:current_user] do
      nil ->
        socket
        |> assign(:org_options, [])
        |> assign(:workspace_options, [])
        |> assign(:selected_org_id, nil)
        |> assign(:selected_workspace_id, nil)
        |> assign(:scope_notice, nil)
        |> recompute_onboarding_state()

      user ->
        org_rows = Accounts.list_orgs_for_user(user.id, "admin")
        org_options = Enum.map(org_rows, &{&1.org.id, &1.org.name, &1.org.slug})
        selected_org_id = default_org_id(org_rows)
        workspaces = load_workspaces(selected_org_id)

        socket
        |> assign(:org_options, org_options)
        |> assign(:workspace_options, Enum.map(workspaces, &{&1.id, &1.name, &1.slug}))
        |> assign(:selected_org_id, selected_org_id)
        |> assign(:selected_workspace_id, default_workspace_id(workspaces))
        |> assign(:scope_notice, nil)
        |> recompute_onboarding_state()
    end
  end

  # Applies `?org_slug`/`?ws_slug` on top of the mount defaults. Only
  # admin/owner orgs are in org_options, so a slug match against them IS the
  # authorization — params for anything else are ignored server-side with an
  # inline notice (issue #183).
  defp apply_scope_params(socket, params) do
    if socket.assigns.cloud_mode and socket.assigns[:current_user] != nil do
      apply_org_slug(socket, params["org_slug"], params["ws_slug"])
    else
      socket
    end
  end

  defp apply_org_slug(socket, org_slug, _ws_slug) when not is_binary(org_slug),
    do: socket

  defp apply_org_slug(socket, org_slug, _ws_slug) when byte_size(org_slug) == 0,
    do: socket

  defp apply_org_slug(socket, org_slug, ws_slug) do
    case Enum.find(socket.assigns.org_options, fn {_id, _name, slug} -> slug == org_slug end) do
      nil ->
        put_scope_notice(
          socket,
          "Organization \"#{org_slug}\" is not available to you — keeping your default selection."
        )

      {org_id, _name, _slug} ->
        apply_ws_slug(socket, org_id, ws_slug)
    end
  end

  defp apply_ws_slug(socket, org_id, ws_slug) when is_binary(ws_slug) and ws_slug != "" do
    workspaces = load_workspaces(org_id)

    case Enum.find(workspaces, &(&1.slug == ws_slug)) do
      nil ->
        put_scope_notice(
          socket,
          "Workspace \"#{ws_slug}\" does not belong to that organization — keeping your default selection."
        )

      workspace ->
        assign_scope_selection(socket, org_id, workspaces, workspace.id)
    end
  end

  # Org-only params (org-scope header buttons): pre-select the org and its
  # first workspace.
  defp apply_ws_slug(socket, org_id, _ws_slug) do
    workspaces = load_workspaces(org_id)
    assign_scope_selection(socket, org_id, workspaces, default_workspace_id(workspaces))
  end

  defp assign_scope_selection(socket, org_id, workspaces, workspace_id) do
    socket
    |> assign(:selected_org_id, org_id)
    |> assign(:workspace_options, Enum.map(workspaces, &{&1.id, &1.name, &1.slug}))
    |> assign(:selected_workspace_id, workspace_id)
    |> assign(:scope_notice, nil)
    |> recompute_onboarding_state()
  end

  # The URL is the selection state: picker events patch these params and
  # handle_params re-applies them.
  defp scope_path(org_slug, nil) when is_binary(org_slug),
    do: ~p"/sessions/start?#{%{org_slug: org_slug}}"

  defp scope_path(org_slug, ws_slug) when is_binary(org_slug) and is_binary(ws_slug),
    do: ~p"/sessions/start?#{%{org_slug: org_slug, ws_slug: ws_slug}}"

  defp org_slug_for_id(org_options, org_id) do
    Enum.find_value(org_options, fn {id, _name, slug} -> if id == org_id, do: slug end)
  end

  defp workspace_slug_for_id(workspaces, workspace_id) do
    Enum.find_value(workspaces, fn ws -> if ws.id == workspace_id, do: ws.slug end)
  end

  defp option_workspace_slug(workspace_options, workspace_id) do
    Enum.find_value(workspace_options, fn {id, _name, slug} ->
      if id == workspace_id, do: slug
    end)
  end

  defp put_scope_notice(socket, text) do
    assign(socket, :scope_notice, text)
  end

  defp recompute_onboarding_state(socket) do
    socket
    |> assign(
      :can_onboard,
      is_integer(socket.assigns.selected_org_id) and
        is_integer(socket.assigns.selected_workspace_id)
    )
    |> assign(:onboarding_notice, workspace_notice(socket.assigns))
  end

  defp load_workspaces(org_id) when is_integer(org_id),
    do: Accounts.list_workspaces_for_org(org_id)

  defp load_workspaces(_org_id), do: []

  defp default_org_id([]), do: nil
  defp default_org_id([%{org: org} | _]), do: org.id

  defp default_workspace_id([]), do: nil
  defp default_workspace_id([workspace | _]), do: workspace.id

  defp parse_org_id(org_id, options) do
    parse_option_id(org_id, options, fn {id, _name, _slug} -> id end)
  end

  defp parse_workspace_id(workspace_id, options) do
    parse_option_id(workspace_id, options, fn {id, _name, _slug} -> id end)
  end

  defp parse_option_id(value, options, id_of) do
    case Integer.parse(to_string(value || "")) do
      {id, ""} ->
        if Enum.any?(options, &(id_of.(&1) == id)), do: id, else: nil

      _ ->
        nil
    end
  end

  defp maybe_put_workspace_id(attrs, socket) do
    if socket.assigns.cloud_mode and is_integer(socket.assigns.selected_workspace_id) do
      Map.put(attrs, "workspace_id", socket.assigns.selected_workspace_id)
    else
      attrs
    end
  end

  defp onboarding_block_message(%{assigns: assigns}) do
    case workspace_notice(assigns) do
      %{text: text} -> text
      nil -> "Choose an organization and workspace before starting this session."
    end
  end

  defp workspace_notice(assigns) do
    cond do
      assigns.org_options == [] ->
        %{
          text:
            "You need to be an admin or owner of at least one organization to start a session here. Organizations where you are only a member or viewer are not shown for onboarding.",
          link: ~p"/organizations",
          link_text: "View organizations"
        }

      assigns.workspace_options == [] ->
        %{
          text:
            "This organization has no workspaces yet. Create a workspace before starting a session.",
          link: ~p"/#{selected_org_slug(assigns)}",
          link_text: "Manage workspaces"
        }

      not is_integer(assigns.selected_workspace_id) ->
        %{text: "Choose a workspace before starting this session.", link: nil, link_text: nil}

      true ->
        nil
    end
  end

  defp selected_org_slug(assigns) do
    Enum.find_value(assigns.org_options, fn {id, _name, slug} ->
      if id == assigns.selected_org_id, do: slug
    end)
  end

  defp boundary_value(map, key), do: Map.get(map, key) || "Not specified"

  defp boundary_text(map, key) do
    case Map.get(map, key, []) do
      items when is_list(items) and items != [] -> Enum.join(items, " ")
      "" <> rest -> rest
      _ -> "Not specified"
    end
  end

  defp validate_step(1, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "occupation",
        blank?(attrs["occupation"]),
        "Choose the occupation that best fits this session."
      )
      |> maybe_error("agent", blank?(attrs["agent"]), "Choose the primary coding agent.")

    step_result(attrs, errors)
  end

  defp validate_step(2, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "project_name",
        blank?(attrs["project_name"]),
        "Give the project a name."
      )
      |> maybe_error(
        "project_name",
        duplicate_project_name?(attrs["project_name"]),
        "This project name is already used by an existing session."
      )
      |> maybe_error(
        "idea",
        short_text?(attrs["idea"], 12),
        "Describe the product in a few concrete sentences (at least 12 characters)."
      )

    step_result(attrs, errors)
  end

  defp validate_step(3, attrs, questions) do
    errors =
      Enum.reduce(questions, %{}, fn question, acc ->
        answer = get_in(attrs, ["interview_answers", question.id])

        maybe_error(
          acc,
          "interview_answers.#{question.id}",
          short_text?(answer, 8),
          "Answer this question before compiling the brief (at least 8 characters)."
        )
      end)

    step_result(attrs, errors)
  end

  defp step_result(attrs, errors) when map_size(errors) == 0, do: {:ok, attrs}
  defp step_result(_attrs, errors), do: {:error, errors}

  defp maybe_error(errors, _field, false, _message), do: errors
  defp maybe_error(errors, field, true, message), do: Map.put(errors, field, message)

  defp maybe_emit_interview_started(%{assigns: %{started?: true}} = socket, _attrs), do: socket

  defp maybe_emit_interview_started(socket, attrs) do
    preflight = Intent.preflight_context(attrs)

    :telemetry.execute(
      [:controlkeel, :intent, :interview, :started],
      %{count: 1},
      %{
        occupation: attrs["occupation"],
        domain_pack: preflight.domain_pack,
        agent: attrs["agent"]
      }
    )

    assign(socket, :started?, true)
  end

  defp emit_interview_step_completed(socket, attrs) do
    preflight = Intent.preflight_context(attrs)

    :telemetry.execute(
      [:controlkeel, :intent, :interview, :step_completed],
      %{count: 1},
      %{
        step: socket.assigns.step,
        occupation: attrs["occupation"],
        domain_pack: preflight.domain_pack
      }
    )

    socket
  end

  defp merge_launch_attrs(current, incoming) do
    current_answers = Map.get(current, "interview_answers", %{})
    incoming_answers = Map.get(incoming, "interview_answers", %{})

    current
    |> Map.merge(stringify_map(incoming))
    |> Map.put("interview_answers", Map.merge(current_answers, stringify_map(incoming_answers)))
  end

  defp stringify_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp default_attrs(occupation) do
    %{
      "occupation" => occupation,
      "agent" => "claude",
      "budget" => "30",
      "project_name" => "",
      "idea" => "",
      "interview_answers" => %{}
    }
  end

  defp default_occupation do
    Intent.occupation_profiles()
    |> List.first()
    |> Map.fetch!(:id)
  end

  defp blank?(value), do: String.trim(to_string(value || "")) == ""

  defp duplicate_project_name?(name) do
    not blank?(name) and Mission.project_name_taken?(name)
  end

  defp short_text?(value, minimum),
    do: String.length(String.trim(to_string(value || ""))) < minimum

  defp field_error(errors, key), do: Map.get(errors, key)

  defp compile_error_message(reason) do
    "ControlKeel could not compile the execution brief yet (#{format_reason(reason)}). If you do not have a bridge, API key, or local Ollama model, ControlKeel still runs in heuristic mode for governance, proofs, skills, and benchmarks."
  end

  defp format_reason(%Ecto.Changeset{}), do: "schema validation failed"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
