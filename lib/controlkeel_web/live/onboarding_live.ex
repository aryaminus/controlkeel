defmodule ControlKeelWeb.OnboardingLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker

  @impl true
  def mount(_params, _session, socket) do
    occupation = default_occupation()
    attrs = default_attrs(occupation)
    provider_status = ProviderBroker.status()

    {:ok,
     socket
     |> assign(:page_title, "Start a mission")
     |> assign(:occupation_profiles, Intent.occupation_profiles())
     |> assign(:agent_options, Intent.agent_options())
     |> assign(:step, 1)
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(occupation))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:provider_status, provider_status)
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)
     |> assign(:compiled_brief, nil)
     |> assign(:compiled_boundary_summary, Intent.boundary_summary(nil))
     |> assign(:started?, false)
     |> assign_form()}
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
  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, max(socket.assigns.step - 1, 1))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)}
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
  def handle_event("accept", _params, %{assigns: %{compiled_brief: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Compile the brief before creating a mission.")}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    case Mission.create_launch_from_brief(socket.assigns.attrs, socket.assigns.compiled_brief) do
      {:ok, session} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/missions/#{session.id}?launched=1")}

      {:error, _scope, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "ControlKeel could not create the mission from this brief.")
         |> assign(:step, 4)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Mission onboarding</p>
          <h1 class="ck-section-title">Compile a governed execution brief</h1>
          <p class="ck-lead ck-lead-tight">
            ControlKeel is the control tower that turns agent-generated work into secure, scoped, validated, production-ready delivery. ControlKeel turns agent output into production engineering. This flow interviews the operator in plain language, compiles the brief on the server, and seeds a production-minded mission.
          </p>
          <p class="ck-note">
            Agent output is cheap. Reviewability, security, release safety, and cost control are not. This flow exists to turn a rough idea into a governed execution brief, task plan, and proof trail.
          </p>
          <p class="ck-note">
            If a generator leaves you with a brittle repo or unclear launch boundary, ControlKeel acts as the rescue control plane: it compiles the brief, makes the constraints visible, and keeps proof attached to the work.
          </p>
        </div>
        <a href={~p"/"} class="ck-link">Back home</a>
      </div>

      <div class="ck-metric-row">
        <span>Step {@step} of 4</span>
        <span>{@preflight.domain_pack_label} pack</span>
        <span>{@preflight.preliminary_risk_tier} preliminary risk</span>
      </div>

      <div class="ck-grid ck-grid-dashboard">
        <div class="ck-card">
          <.form for={@form} phx-change="validate" phx-submit="next">
            <%= case @step do %>
              <% 1 -> %>
                <div class="ck-form-panel">
                  <p class="ck-mini-label">Step 1</p>
                  <h2 class="ck-section-title">Choose the domain and primary agent</h2>
                  <p class="ck-note">
                    Start with what best describes the work. ControlKeel uses that choice to set the domain pack, interview language, and initial governance posture without forcing framework acronyms first.
                  </p>

                  <div class="ck-session-grid">
                    <%= for profile <- @occupation_profiles do %>
                      <label class="ck-card ck-session-card">
                        <input
                          type="radio"
                          name="launch[occupation]"
                          value={profile.id}
                          checked={@attrs["occupation"] == profile.id}
                        />
                        <div class="ck-session-head">
                          <div>
                            <p class="ck-mini-label">{Intent.pack_label(profile.domain_pack)}</p>
                            <h3>{profile.label}</h3>
                          </div>
                        </div>
                        <p class="ck-note">{profile.description}</p>
                      </label>
                    <% end %>
                  </div>
                  <%= if error = field_error(@errors, "occupation") do %>
                    <p class="ck-note">{error}</p>
                  <% end %>

                  <label>
                    <span class="ck-label">Primary agent</span>
                    <select name="launch[agent]">
                      <%= for {id, label} <- @agent_options do %>
                        <option value={id} selected={@attrs["agent"] == id}>{label}</option>
                      <% end %>
                    </select>
                  </label>
                  <%= if error = field_error(@errors, "agent") do %>
                    <p class="ck-note">{error}</p>
                  <% end %>

                  <label>
                    <span class="ck-label">Daily budget (USD)</span>
                    <span class="ck-note">
                      ControlKeel stops agents when this limit is reached. $10/day is roughly 3 full features.
                    </span>
                    <input
                      type="number"
                      name="launch[budget]"
                      value={@attrs["budget"]}
                      min="0"
                      max="500"
                      step="5"
                      placeholder="30"
                    />
                  </label>
                  <%= if error = field_error(@errors, "budget") do %>
                    <p class="ck-note">{error}</p>
                  <% end %>
                </div>
              <% 2 -> %>
                <div class="ck-form-panel">
                  <p class="ck-mini-label">Step 2</p>
                  <h2 class="ck-section-title">Describe the product</h2>

                  <label>
                    <span class="ck-label">Project name</span>
                    <input
                      type="text"
                      name="launch[project_name]"
                      value={@attrs["project_name"]}
                      placeholder="ControlKeel mission name"
                    />
                  </label>

                  <label>
                    <span class="ck-label">Core product prompt</span>
                    <textarea
                      name="launch[idea]"
                      rows="8"
                      placeholder="Describe what you want built in plain language."
                    ><%= @attrs["idea"] %></textarea>
                  </label>
                  <%= if error = field_error(@errors, "idea") do %>
                    <p class="ck-note">{error}</p>
                  <% end %>
                </div>
              <% 3 -> %>
                <div class="ck-form-panel">
                  <p class="ck-mini-label">Step 3</p>
                  <h2 class="ck-section-title">Answer the guided interview</h2>

                  <%= for question <- @interview_questions do %>
                    <label>
                      <span class="ck-label">{question.label}</span>
                      <span class="ck-note">{question.prompt}</span>
                      <textarea
                        name={"launch[interview_answers][#{question.id}]"}
                        rows="4"
                        placeholder={question.placeholder}
                      ><%= Map.get(@attrs["interview_answers"], question.id, "") %></textarea>
                    </label>
                    <%= if error = field_error(@errors, "interview_answers.#{question.id}") do %>
                      <p class="ck-note">{error}</p>
                    <% end %>
                  <% end %>
                  <%= if @compile_error do %>
                    <p class="ck-note">{@compile_error}</p>
                  <% end %>
                </div>
              <% 4 -> %>
                <div class="ck-form-panel">
                  <p class="ck-mini-label">Step 4</p>
                  <h2 class="ck-section-title">Review the compiled brief</h2>
                  <%= if @compiled_brief do %>
                    <% brief = Intent.to_brief_map(@compiled_brief) %>
                    <% compiler = brief["compiler"] || %{} %>
                    <div class="ck-brief-grid">
                      <div>
                        <h3>Objective</h3>
                        <p class="ck-note">{brief["objective"]}</p>
                      </div>
                      <div>
                        <h3>Recommended stack</h3>
                        <p class="ck-note">{brief["recommended_stack"]}</p>
                      </div>
                      <div>
                        <h3>Next step</h3>
                        <p class="ck-note">{brief["next_step"]}</p>
                      </div>
                      <div>
                        <h3>Compiler</h3>
                        <p class="ck-note">
                          {compiler["provider"]} / {compiler["model"]}
                        </p>
                      </div>
                      <div>
                        <h3>Provider mode</h3>
                        <p class="ck-note">{provider_mode_label(@provider_status)}</p>
                      </div>
                    </div>

                    <div class="ck-grid ck-grid-dashboard">
                      <div class="ck-card">
                        <p class="ck-mini-label">Acceptance criteria</p>
                        <ul class="ck-mini-list">
                          <%= for item <- brief["acceptance_criteria"] || [] do %>
                            <li>{item}</li>
                          <% end %>
                        </ul>
                      </div>
                      <div class="ck-card">
                        <p class="ck-mini-label">Production boundary</p>
                        <div class="ck-brief-grid">
                          <div>
                            <h3>Risk tier</h3>
                            <p class="ck-note">
                              {boundary_value(@compiled_boundary_summary, "risk_tier")}
                            </p>
                          </div>
                          <div>
                            <h3>Budget note</h3>
                            <p class="ck-note">
                              {boundary_value(@compiled_boundary_summary, "budget_note")}
                            </p>
                          </div>
                          <div>
                            <h3>Launch window</h3>
                            <p class="ck-note">
                              {boundary_value(@compiled_boundary_summary, "launch_window")}
                            </p>
                          </div>
                          <div>
                            <h3>Constraints</h3>
                            <ul class="ck-mini-list">
                              <%= for item <- boundary_list(@compiled_boundary_summary, "constraints") do %>
                                <li>{item}</li>
                              <% end %>
                            </ul>
                          </div>
                        </div>
                      </div>
                      <div class="ck-card">
                        <p class="ck-mini-label">Open questions</p>
                        <ul class="ck-mini-list">
                          <%= for item <- brief["open_questions"] || [] do %>
                            <li>{item}</li>
                          <% end %>
                        </ul>
                      </div>
                    </div>
                  <% else %>
                    <p class="ck-note">The brief is not available yet.</p>
                  <% end %>
                </div>
            <% end %>

            <div class="ck-action-row">
              <button
                :if={@step > 1}
                class="ck-link"
                type="button"
                phx-click="back"
              >
                Back
              </button>

              <button :if={@step < 4} class="ck-button-primary" type="submit">
                {if @step == 3, do: "Compile brief", else: "Continue"}
              </button>
            </div>
          </.form>

          <div :if={@step == 4} class="ck-action-row">
            <button class="ck-link" type="button" phx-click="back">Edit answers</button>
            <button class="ck-link" type="button" phx-click="regenerate">Regenerate</button>
            <button class="ck-button-primary" type="button" phx-click="accept">Create mission</button>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Domain pack preview</p>
          <div class="ck-brief-grid">
            <div>
              <h3>Occupation</h3>
              <p class="ck-note">{@preflight.occupation.label}</p>
            </div>
            <div>
              <h3>Validation emphasis</h3>
              <p class="ck-note">{@preflight.validation_language}</p>
            </div>
            <div>
              <h3>Compliance</h3>
              <ul class="ck-tag-list">
                <%= for item <- @preflight.compliance do %>
                  <li><span class="ck-tag">{item}</span></li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3>Stack guidance</h3>
              <p class="ck-note">{@preflight.stack_guidance}</p>
            </div>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Provider and autonomy status</p>
          <p class="ck-note">
            Designed for serious solo builders and tiny teams first. ControlKeel is not another IDE, coding model, or post-hoc review layer; it is the governed control loop around those tools.
          </p>
          <p class="ck-note" style="margin-top: 0.75rem;">
            Unsupported tool or rescue situation? Bootstrap the project, use `controlkeel watch`, findings, proofs, and `ck_validate`, then add governed proxy only when the tool can target compatible endpoints.
          </p>
          <div class="ck-brief-grid">
            <div>
              <h3>Current mode</h3>
              <p class="ck-note">{provider_mode_label(@provider_status)}</p>
            </div>
            <div>
              <h3>Current provider</h3>
              <p class="ck-note">{provider_name(@provider_status)}</p>
            </div>
            <div>
              <h3>Setup scope</h3>
              <p class="ck-note">{setup_scope_copy(@provider_status)}</p>
            </div>
            <div>
              <h3>Attached agents</h3>
              <p class="ck-note">{attached_agents_copy(@provider_status)}</p>
            </div>
          </div>

          <p class="ck-note" style="margin-top: 1rem;">
            {provider_guidance(@provider_status)}
          </p>

          <p class="ck-note" style="margin-top: 0.75rem;">
            Autonomy and findings: see
            <code class="font-mono text-sm">docs/autonomy-and-findings.md</code>
            in the repository for how severity maps to human review (LLM advisory requires a provider; validate responses include an advisory status).
          </p>

          <div class="ck-grid ck-grid-dashboard" style="margin-top: 1rem;">
            <div class="ck-card">
              <p class="ck-mini-label">Always available</p>
              <ul class="ck-mini-list">
                <%= for item <- always_available_capabilities() do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
            <div class="ck-card">
              <p class="ck-mini-label">Model-backed features</p>
              <ul class="ck-mini-list">
                <%= for item <- model_backed_capabilities(@provider_status) do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
          </div>

          <div class="ck-grid ck-grid-dashboard" style="margin-top: 1rem;">
            <div class="ck-card">
              <p class="ck-mini-label">Resolution order</p>
              <ol class="ck-mini-list">
                <%= for item <- provider_resolution_steps() do %>
                  <li>{item}</li>
                <% end %>
              </ol>
            </div>
            <div class="ck-card">
              <p class="ck-mini-label">Autonomy defaults</p>
              <ul class="ck-mini-list">
                <%= for item <- autonomy_defaults() do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </section>
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
           Intent.boundary_summary(brief, project_root: File.cwd!())
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

  defp boundary_value(map, key), do: Map.get(map, key) || "Not specified"

  defp boundary_list(map, key) do
    case Map.get(map, key, []) do
      [] -> ["Not specified"]
      items -> items
    end
  end

  defp validate_step(1, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "occupation",
        blank?(attrs["occupation"]),
        "Choose the occupation that best fits this mission."
      )
      |> maybe_error("agent", blank?(attrs["agent"]), "Choose the primary coding agent.")

    step_result(attrs, errors)
  end

  defp validate_step(2, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "idea",
        short_text?(attrs["idea"], 12),
        "Describe the product in a few concrete sentences."
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
          "Answer this question before compiling the brief."
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

  defp short_text?(value, minimum),
    do: String.length(String.trim(to_string(value || ""))) < minimum

  defp field_error(errors, key), do: Map.get(errors, key)

  defp compile_error_message(reason) do
    "ControlKeel could not compile the execution brief yet (#{format_reason(reason)}). If you do not have a bridge, API key, or local Ollama model, ControlKeel still runs in heuristic mode for governance, proofs, skills, and benchmarks."
  end

  defp provider_mode_label(%{
         "selected_source" => "agent_bridge",
         "selected_provider" => provider
       }) do
    "Bridge via attached agent (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "workspace_profile",
         "selected_provider" => provider
       }) do
    "Workspace-managed provider (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "user_default_profile",
         "selected_provider" => provider
       }) do
    "ControlKeel user profile (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "project_override",
         "selected_provider" => provider
       }) do
    "Project override (#{provider})"
  end

  defp provider_mode_label(%{"selected_source" => "ollama", "selected_model" => model}) do
    "Local Ollama (#{model || "default model"})"
  end

  defp provider_mode_label(_status), do: "Heuristic / no-LLM fallback"

  defp provider_name(%{"selected_provider" => provider}) when provider in [nil, "heuristic"],
    do: "No provider selected"

  defp provider_name(%{"selected_provider" => provider, "selected_model" => model}) do
    if blank?(model), do: provider, else: "#{provider} / #{model}"
  end

  defp setup_scope_copy(%{"binding_mode" => mode}) when mode in ["project", "ephemeral"] do
    "Governance stays project-local. Some agent installs can still be user-scoped."
  end

  defp setup_scope_copy(_status) do
    "Use user scope for reusable agent installs. Use project bootstrap for governed repos."
  end

  defp attached_agents_copy(%{"attached_agents" => []}), do: "None yet"

  defp attached_agents_copy(%{"attached_agents" => agents}) when is_list(agents) do
    agents
    |> Enum.map_join(", ", fn agent ->
      Map.get(agent, "label") || Map.get(agent, "id") || "Unknown"
    end)
  end

  defp attached_agents_copy(_status), do: "None yet"

  defp provider_guidance(%{"selected_source" => "agent_bridge"}) do
    "ControlKeel is borrowing model access from an attached agent bridge, so you usually do not need to enter a separate API key for guided compilation and advisory features."
  end

  defp provider_guidance(%{"selected_source" => source})
       when source in ["workspace_profile", "user_default_profile", "project_override"] do
    "ControlKeel has its own provider profile available. Guided compilation and advisory features can run directly from the configured model source."
  end

  defp provider_guidance(%{"selected_source" => "ollama"}) do
    "ControlKeel is using a local Ollama model. This keeps setup local-first and avoids hosted API keys, but model quality depends on the local model you run."
  end

  defp provider_guidance(_status) do
    "No bridge, API key, or local model is configured right now. ControlKeel still governs agent work, captures proofs, runs MCP tools, and benchmarks outcomes in heuristic mode."
  end

  defp always_available_capabilities do
    [
      "Governance and policy validation on agent actions",
      "Findings, proof bundles, and mission audit trail",
      "MCP tools, skills, and agent attachments",
      "Benchmark runs and policy artifact management"
    ]
  end

  defp model_backed_capabilities(%{"selected_provider" => provider})
       when provider in [nil, "heuristic"] do
    [
      "Execution brief compilation falls back to heuristics or may ask for a provider",
      "Advisory scanner only runs when a provider is available",
      "Model-backed guidance is limited until a bridge, key, or Ollama model is configured"
    ]
  end

  defp model_backed_capabilities(_status) do
    [
      "Execution brief compilation can use the configured model path",
      "Advisory scanner can add model-backed review on top of pattern scanning",
      "Provider-backed guidance can run without asking for another setup step"
    ]
  end

  defp provider_resolution_steps do
    [
      "Attached agent bridge when supported",
      "Workspace or service-account profile",
      "ControlKeel user default profile",
      "Project override",
      "Local Ollama",
      "Heuristic fallback"
    ]
  end

  defp autonomy_defaults do
    [
      "Low-risk guidance continues automatically with warnings when needed",
      "Medium-risk findings stay visible and route the operator toward a fix",
      "Destructive or high-risk actions should be blocked or explicitly reviewed",
      "Governed repos keep the policy trail even when model features degrade"
    ]
  end

  defp format_reason(%Ecto.Changeset{}), do: "schema validation failed"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
