defmodule ControlKeelWeb.OnboardingLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    occupation = default_occupation()
    attrs = default_attrs(occupation)

    {:ok,
     socket
     |> assign(:page_title, "Start a mission")
     |> assign(:occupation_profiles, Intent.occupation_profiles())
     |> assign(:agent_options, Intent.agent_options())
     |> assign(:step, 1)
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(occupation))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)
     |> assign(:compiled_brief, nil)
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
            ControlKeel interviews the operator, compiles the brief on the server, and seeds a production-minded mission.
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
                    This selects the domain pack, interview language, and initial compliance posture.
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
    "ControlKeel could not compile the execution brief yet (#{format_reason(reason)}). Configure an intent provider or retry."
  end

  defp format_reason(%Ecto.Changeset{}), do: "schema validation failed"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
