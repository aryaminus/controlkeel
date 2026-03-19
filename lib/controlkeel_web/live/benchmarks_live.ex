defmodule ControlKeelWeb.BenchmarksLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Benchmark
  alias ControlKeel.PolicyTraining

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benchmarks")
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:form, to_form(default_form_params(), as: :benchmark))
     |> assign(:policy_form, to_form(default_policy_params(), as: :policy))
     |> refresh_dashboard_assigns()}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Benchmark.get_run(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Benchmark run not found.")
         |> push_navigate(to: ~p"/benchmarks")}

      run ->
        {:noreply,
         socket
         |> assign(:run, run)
         |> assign(:matrix, Benchmark.run_matrix(run))
         |> assign(:detail_metrics, Benchmark.run_detail_metrics(run))
         |> assign(:page_title, "Benchmark Run #{run.id}")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:page_title, "Benchmarks")
     |> refresh_dashboard_assigns()}
  end

  @impl true
  def handle_event("run", %{"benchmark" => params}, socket) do
    case Benchmark.run_suite(params) do
      {:ok, run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Benchmark run ##{run.id} completed.")
         |> push_navigate(to: ~p"/benchmarks/runs/#{run.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Benchmark run failed: #{inspect(reason)}")}
    end
  end

  def handle_event("train_policy", %{"policy" => params}, socket) do
    case PolicyTraining.start_training(params) do
      {:ok, artifact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Policy training completed for #{artifact.artifact_type}.")
         |> push_navigate(to: ~p"/benchmarks/policies/#{artifact.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Policy training failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Benchmark run</p>
            <h1 class="ck-section-title">Run ##{@run.id} — {@run.suite.name}</h1>
            <p class="ck-lead ck-lead-tight">
              Compare governed and external subjects across the same failure scenarios without polluting mission data.
            </p>
          </div>
          <div class="ck-action-row">
            <.link navigate={~p"/benchmarks"} class="ck-link">Back to benchmarks</.link>
            <a href={~p"/api/v1/benchmarks/runs/#{@run.id}/export?format=csv"} class="ck-link">
              Export CSV
            </a>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Catch rate</p>
            <strong>{@run.catch_rate}%</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Block rate</p>
            <strong>{@detail_metrics.block_rate}%</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Expected rule hit rate</p>
            <strong>{@detail_metrics.expected_rule_hit_rate}%</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Average overhead</p>
            <strong>{format_percent(@run.average_overhead_percent)}</strong>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Run metadata</p>
          <div class="ck-brief-grid">
            <div>
              <h3>Status</h3>
              <p class="ck-note">{@run.status}</p>
            </div>
            <div>
              <h3>Baseline subject</h3>
              <p class="ck-note">{@run.baseline_subject}</p>
            </div>
            <div>
              <h3>Subjects</h3>
              <p class="ck-note">{Enum.join(@run.subjects, ", ")}</p>
            </div>
            <div>
              <h3>Median latency</h3>
              <p class="ck-note">{format_latency(@run.median_latency_ms)}</p>
            </div>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Scenario matrix</p>
          <div class="ck-table-wrap">
            <table class="min-w-full text-sm" id="benchmark-matrix">
              <thead>
                <tr>
                  <th class="text-left py-2 pr-4">Scenario</th>
                  <%= for subject <- @matrix.subjects do %>
                    <th class="text-left py-2 pr-4">{subject}</th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @matrix.scenarios do %>
                  <tr id={"scenario-#{row.scenario.slug}"}>
                    <td class="align-top py-3 pr-4">
                      <strong>{row.scenario.name}</strong>
                      <p class="ck-note">{row.scenario.incident_label}</p>
                    </td>
                    <%= for result <- row.results do %>
                      <td class="align-top py-3 pr-4">
                        <%= if result do %>
                          <div class="ck-badge-stack">
                            <span class="ck-pill ck-pill-neutral">{result.status}</span>
                            <span :if={result.decision} class="ck-pill ck-pill-neutral">
                              {result.decision}
                            </span>
                          </div>
                          <p class="ck-note">{result.findings_count} findings</p>
                          <p class="ck-note">latency {format_latency(result.latency_ms)}</p>
                          <p class="ck-note">overhead {format_percent(result.overhead_percent)}</p>
                        <% else %>
                          <p class="ck-note">No result</p>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Benchmark engine</p>
            <h1 class="ck-section-title">Run persisted benchmark matrices</h1>
            <p class="ck-lead ck-lead-tight">
              Compare governed subjects and external agents on the same scenario suites, then keep the results as product evidence.
            </p>
          </div>
          <.link navigate={~p"/"} class="ck-link">Back home</.link>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Suites</p>
            <strong>{@summary.total_suites}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Runs</p>
            <strong>{@summary.total_runs}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Average catch rate</p>
            <strong>{format_percent(@summary.average_catch_rate)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Average overhead</p>
            <strong>{format_percent(@summary.average_overhead_percent)}</strong>
          </div>
        </div>

        <div class="ck-card ck-browser-filters">
          <.form for={@form} id="benchmark-runner" phx-submit="run">
            <div class="ck-filter-grid">
              <.input
                field={@form[:suite]}
                type="select"
                label="Suite"
                options={Enum.map(@suites, &{"#{&1.name} (#{&1.slug})", &1.slug})}
              />
              <.input
                field={@form[:subjects]}
                type="text"
                label="Subjects"
                placeholder="controlkeel_validate,controlkeel_proxy"
              />
              <.input
                field={@form[:baseline_subject]}
                type="text"
                label="Baseline subject"
                placeholder="controlkeel_validate"
              />
            </div>
            <div class="ck-action-row" style="margin-top: 1rem;">
              <button type="submit" class="ck-button-primary">Run benchmark</button>
            </div>
          </.form>
          <p class="ck-note" style="margin-top: 1rem;">
            Subjects currently visible to this server process: {Enum.map_join(
              @available_subjects,
              ", ",
              & &1["id"]
            )}
          </p>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Built-in suites</p>
            <div class="ck-finding-list">
              <%= for suite <- @suites do %>
                <article class="ck-finding-item">
                  <div class="ck-finding-head">
                    <h3>{suite.name}</h3>
                    <span class="ck-pill ck-pill-neutral">v{suite.version}</span>
                  </div>
                  <p class="ck-note">{suite.description}</p>
                  <div class="ck-metric-row">
                    <span>{length(suite.scenarios)} scenarios</span>
                    <span>{suite.status}</span>
                  </div>
                </article>
              <% end %>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Recent runs</p>
            <div class="ck-table-wrap">
              <.table id="benchmark-runs" rows={@recent_runs}>
                <:col :let={run} label="Run">
                  <.link navigate={~p"/benchmarks/runs/#{run.id}"} class="ck-link">
                    ##{run.id}
                  </.link>
                </:col>
                <:col :let={run} label="Suite">
                  {run.suite.slug}
                </:col>
                <:col :let={run} label="Status">
                  {run.status}
                </:col>
                <:col :let={run} label="Catch rate">
                  {run.catch_rate}%
                </:col>
                <:col :let={run} label="Baseline">
                  {run.baseline_subject}
                </:col>
              </.table>
            </div>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard" style="margin-top: 1.5rem;">
          <div class="ck-card">
            <p class="ck-mini-label">Active policy artifacts</p>
            <div class="ck-finding-list">
              <article class="ck-finding-item" id="active-router-artifact">
                <div class="ck-finding-head">
                  <h3>Router policy</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {if @active_router_artifact,
                      do: "v#{@active_router_artifact.version}",
                      else: "heuristic"}
                  </span>
                </div>
                <p class="ck-note">
                  <%= if @active_router_artifact do %>
                    {Map.get(@active_router_artifact.metrics["gates"] || %{}, "eligible", false)
                    |> then(fn _ -> @active_router_artifact.model_family end)}. Held-out reward: {Float.round(
                      get_in(@active_router_artifact.metrics, ["held_out", "reward"]) || 0.0,
                      3
                    )}.
                  <% else %>
                    No learned router artifact is active. Runtime routing is using heuristics.
                  <% end %>
                </p>
                <%= if @active_router_artifact do %>
                  <.link
                    navigate={~p"/benchmarks/policies/#{@active_router_artifact.id}"}
                    class="ck-link"
                  >
                    Open policy detail
                  </.link>
                <% end %>
              </article>
              <article class="ck-finding-item" id="active-budget-artifact">
                <div class="ck-finding-head">
                  <h3>Budget hint policy</h3>
                  <span class="ck-pill ck-pill-neutral">
                    {if @active_budget_artifact,
                      do: "v#{@active_budget_artifact.version}",
                      else: "heuristic"}
                  </span>
                </div>
                <p class="ck-note">
                  <%= if @active_budget_artifact do %>
                    {Map.get(
                      @active_budget_artifact.artifact,
                      "model_family",
                      @active_budget_artifact.model_family
                    )}.
                    Held-out precision: {Float.round(
                      get_in(@active_budget_artifact.metrics, ["held_out", "precision"]) || 0.0,
                      3
                    )}.
                  <% else %>
                    No learned budget-hint artifact is active. Budget caps are still deterministic.
                  <% end %>
                </p>
                <%= if @active_budget_artifact do %>
                  <.link
                    navigate={~p"/benchmarks/policies/#{@active_budget_artifact.id}"}
                    class="ck-link"
                  >
                    Open policy detail
                  </.link>
                <% end %>
              </article>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Train a new artifact</p>
            <.form for={@policy_form} id="policy-train-form" phx-submit="train_policy">
              <div class="ck-filter-grid">
                <.input
                  field={@policy_form[:type]}
                  type="select"
                  label="Artifact type"
                  options={[{"Router", "router"}, {"Budget hint", "budget_hint"}]}
                />
              </div>
              <div class="ck-action-row" style="margin-top: 1rem;">
                <button type="submit" class="ck-button-primary">Train policy artifact</button>
              </div>
            </.form>
            <p class="ck-note" style="margin-top: 1rem;">
              Training runs stay offline. Held-out gates prevent promotion if a candidate regresses protection quality or budget-hint precision.
            </p>
          </div>
        </div>

        <div class="ck-card" style="margin-top: 1.5rem;">
          <p class="ck-mini-label">Recent training runs</p>
          <div class="ck-table-wrap">
            <.table id="policy-training-runs" rows={@recent_training_runs}>
              <:col :let={run} label="Run">
                ##{run.id}
              </:col>
              <:col :let={run} label="Type">
                {run.artifact_type}
              </:col>
              <:col :let={run} label="Status">
                {run.status}
              </:col>
              <:col :let={run} label="Artifact">
                <%= case List.first(Enum.sort_by(run.artifacts, & &1.version, :desc)) do %>
                  <% nil -> %>
                    <span class="ck-note">n/a</span>
                  <% artifact -> %>
                    <.link navigate={~p"/benchmarks/policies/#{artifact.id}"} class="ck-link">
                      v{artifact.version}
                    </.link>
                <% end %>
              </:col>
              <:col :let={run} label="Held-out">
                <%= if run.held_out_metrics == %{} do %>
                  <span class="ck-note">n/a</span>
                <% else %>
                  <span class="ck-note">
                    {held_out_summary(run)}
                  </span>
                <% end %>
              </:col>
            </.table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp default_form_params do
    %{
      "suite" => "vibe_failures_v1",
      "subjects" => "controlkeel_validate,controlkeel_proxy",
      "baseline_subject" => "controlkeel_validate"
    }
  end

  defp default_policy_params do
    %{"type" => "router"}
  end

  defp refresh_dashboard_assigns(socket) do
    active = PolicyTraining.active_artifacts_summary()

    socket
    |> assign(:summary, Benchmark.benchmark_summary())
    |> assign(:suites, Benchmark.list_suites())
    |> assign(:recent_runs, Benchmark.list_recent_runs())
    |> assign(:available_subjects, Benchmark.available_subjects())
    |> assign(:recent_training_runs, PolicyTraining.list_training_runs())
    |> assign(:active_router_artifact, active["router"])
    |> assign(:active_budget_artifact, active["budget_hint"])
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp format_latency(nil), do: "n/a"
  defp format_latency(value), do: "#{value}ms"

  defp held_out_summary(run) do
    held_out = run.held_out_metrics || %{}

    cond do
      Map.has_key?(held_out, "reward") ->
        "reward #{Float.round(Map.get(held_out, "reward", 0.0), 3)}"

      Map.has_key?(held_out, "precision") ->
        "precision #{Float.round(Map.get(held_out, "precision", 0.0), 3)}"

      true ->
        "n/a"
    end
  end
end
