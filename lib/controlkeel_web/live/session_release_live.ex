defmodule ControlKeelWeb.SessionReleaseLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Governance
  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case SessionScope.fetch_session(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(session) ->
        cond do
          not ControlKeel.Accounts.session_accessible?(session, current_user) ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()

            {:ok,
             socket
             |> assign_session(session)
             |> assign_release_readiness(release_form_defaults(), false)}
        end
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(:breadcrumbs, [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      },
      %{label: "Release", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Release readiness")
    |> assign(:session, session)
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, SessionScope.session_not_found(socket)}

      session ->
        case SessionScope.reauthorize(socket, session) do
          {:ok, session} -> {:noreply, assign_session(socket, session)}
          {:error, :not_found} -> {:noreply, SessionScope.session_not_found(socket)}
        end
    end
  end

  @impl true
  def handle_event("check_release_readiness", %{"release" => params}, socket) do
    form_params = Map.merge(release_form_defaults(), params)

    socket =
      socket
      |> assign(:release_form_params, form_params)
      |> assign_release_readiness(form_params, true)

    {:noreply,
     case socket.assigns.release_readiness do
       nil -> socket
       _readiness -> put_flash(socket, :info, "Release readiness checked.")
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section id="mission-release-readiness">
        <.page_title
          title="Release readiness"
          subtitle="Submit smoke and provenance evidence to check whether this session is ready to ship."
        />

        <%= if is_nil(@release_readiness) do %>
          <p class="mt-4 text-sm text-muted-foreground" id="release-readiness-unavailable">
            Release readiness could not be evaluated for this session yet. Submit the evidence below to run the gate.
          </p>
        <% else %>
          <div class="w-full flex flex-col gap-6 mt-6 lg:flex-row">
            <div class="flex-1">
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-3">
                Release evidence
              </p>

              <.form
                for={@release_form}
                id="release-readiness-form"
                phx-submit="check_release_readiness"
                class="flex flex-col gap-3 "
              >
                <div>
                  <label
                    for="release-smoke-status"
                    class="mb-1.5 flex items-center gap-1.5 text-sm font-medium text-foreground/90"
                  >
                    Smoke status
                  </label>
                  <select
                    id="release-smoke-status"
                    name="release[smoke_status]"
                    class="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-base transition-colors outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm"
                  >
                    <option value="" selected={@release_form[:smoke_status].value in [nil, ""]}>
                      Not run yet
                    </option>
                    <option value="success" selected={@release_form[:smoke_status].value == "success"}>
                      Passed
                    </option>
                    <option value="failed" selected={@release_form[:smoke_status].value == "failed"}>
                      Failed
                    </option>
                  </select>
                </div>
                <.input_component
                  field={@release_form[:smoke_run]}
                  label="Smoke run URL or note"
                  placeholder="https://ci.example.com/run/1234"
                />
                <.input_component
                  field={@release_form[:artifact_source]}
                  label="Artifact source"
                  placeholder="github-actions"
                />
                <.input_component
                  field={@release_form[:sha]}
                  label="Commit SHA"
                  placeholder="release commit (optional)"
                />
                <.input
                  field={@release_form[:provenance_verified]}
                  type="checkbox"
                  label="Artifact provenance verified"
                />
                <div>
                  <.button type="submit" variant="default">
                    <.icon name="hero-shield-check" class="size-4" /> Check release readiness
                  </.button>
                </div>
              </.form>
            </div>

            <aside class="space-y-4">
              <div class="rounded-2xl bg-muted p-4">
                <div class="flex flex-wrap items-center justify-between gap-8">
                  <div>
                    <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      Release-candidate proof
                    </p>
                    <%= if @release_readiness["proof"] do %>
                      <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
                        <.link
                          navigate={~p"/proofs/#{@release_readiness["proof"]["id"]}"}
                          class="text-base font-semibold text-primary transition hover:text-primary"
                        >
                          Proof #{@release_readiness["proof"]["id"]} v{@release_readiness["proof"][
                            "version"
                          ]}
                        </.link>
                        <span class="text-xs text-muted-foreground">
                          risk {@release_readiness["proof"]["risk_score"]}
                        </span>
                      </div>
                    <% else %>
                      <p class="mt-2 text-sm text-muted-foreground">
                        No proof bundle is available for release review yet.
                      </p>
                    <% end %>
                  </div>
                  <%= if @release_readiness["proof"] do %>
                    <span class={[
                      "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold ring-1",
                      if(@release_readiness["proof"]["deploy_ready"],
                        do: "bg-success/10 text-success ring-success/20",
                        else: "bg-warning/10 text-warning ring-warning/20"
                      )
                    ]}>
                      {if @release_readiness["proof"]["deploy_ready"],
                        do: "deploy-ready",
                        else: "review required"}
                    </span>
                  <% end %>
                </div>
              </div>
              <div class="rounded-2xl bg-muted p-4">
                <div class="space-y-4">
                  <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                    Unresolved findings
                  </p>

                  <div class="mt-2 flex flex-wrap items-end gap-x-5 gap-y-2">
                    <div>
                      <p class="text-xl font-semibold text-foreground/90 tabular-nums">
                        {@release_readiness["findings"]["open"]}
                      </p>
                      <p class="text-xs text-muted-foreground">open</p>
                    </div>
                    <div>
                      <p class="text-xl font-semibold text-foreground/90 tabular-nums">
                        {@release_readiness["findings"]["blocked"]}
                      </p>
                      <p class="text-xs text-muted-foreground">blocked</p>
                    </div>
                    <div>
                      <p class="text-xl font-semibold text-foreground/90 tabular-nums">
                        {@release_readiness["findings"]["escalated"]}
                      </p>
                      <p class="text-xs text-muted-foreground">escalated</p>
                    </div>
                    <div>
                      <p class="text-xl font-semibold text-foreground/90 tabular-nums">
                        {@release_readiness["findings"]["high_or_critical"]}
                      </p>
                      <p class="text-xs text-muted-foreground">high or critical</p>
                    </div>
                    <span
                      :if={@release_readiness["findings"]["critical_vulnerability_cases"] > 0}
                      class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1 bg-destructive/10 text-destructive ring-destructive/20"
                    >
                      {@release_readiness["findings"]["critical_vulnerability_cases"]} vulnerability case(s)
                    </span>
                  </div>

                  <.link
                    navigate={
                      ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/findings"
                    }
                    class="inline-flex shrink-0 items-center gap-1 text-sm font-medium text-primary transition hover:text-primary"
                  >
                    View open findings <.icon name="hero-arrow-up-right" class="size-3" />
                  </.link>
                </div>
              </div>

              <%= if @release_readiness["status"] == "ready" do %>
                <p class="text-sm text-success" id="release-readiness-summary">
                  {@release_readiness["summary"]}
                </p>
              <% else %>
                <div id="release-readiness-reasons">
                  <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
                    Unmet gate conditions
                  </p>
                  <ul class="space-y-1 text-sm text-muted-foreground list-disc ml-5">
                    <%= for reason <- @release_readiness["reasons"] do %>
                      <li>{reason}</li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </aside>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp release_form_defaults do
    %{
      "smoke_status" => "",
      "smoke_run" => "",
      "artifact_source" => "",
      "sha" => "",
      "provenance_verified" => "false"
    }
  end

  # Release readiness is isolated so a gate failure can never take down the
  # periodic refresh loop. Only explicit operator checks record telemetry;
  # mount and auto-refresh evaluate silently.
  defp assign_release_readiness(socket, form_params, record_telemetry) do
    readiness =
      socket.assigns.session.id
      |> release_readiness_opts(form_params)
      |> Map.put(:record_telemetry, record_telemetry)
      |> Governance.release_readiness()
      |> case do
        {:ok, readiness} -> readiness
        {:error, _reason} -> nil
      end

    socket
    |> assign(:release_readiness, readiness)
    |> assign(:release_form, to_form(form_params, as: :release))
  rescue
    e ->
      require Logger
      Logger.warning("SessionReleaseLive release readiness rescued: #{inspect(e)}")

      socket
      |> assign(:release_readiness, nil)
      |> assign(:release_form, to_form(form_params, as: :release))
  end

  defp release_readiness_opts(session_id, params) do
    %{
      session_id: session_id,
      sha: blank_to_nil(params["sha"]),
      smoke: %{
        "status" => blank_to_nil(params["smoke_status"]),
        "run_id" => blank_to_nil(params["smoke_run"])
      },
      provenance: %{
        "verified" => params["provenance_verified"] in [true, "true"],
        "artifact_source" => blank_to_nil(params["artifact_source"])
      }
    }
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
