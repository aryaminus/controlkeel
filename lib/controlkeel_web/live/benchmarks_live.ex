defmodule ControlKeelWeb.BenchmarksLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Benchmark
  alias ControlKeel.Intent
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
     |> assign(:filter_form, to_form(%{"domain_pack" => ""}, as: :filters))
     |> assign(:domain_pack_options, domain_pack_options())
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

  def handle_params(%{"domain_pack" => domain_pack} = _params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:page_title, "Benchmarks")
     |> assign(:filter_form, to_form(%{"domain_pack" => domain_pack}, as: :filters))
     |> refresh_dashboard_assigns(domain_pack)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:page_title, "Benchmarks")
     |> assign(:filter_form, to_form(%{"domain_pack" => ""}, as: :filters))
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

  def handle_event("filter_domain", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: ~p"/benchmarks?#{domain_filter_params(filters)}")}
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

  def handle_event("preset_benchmark", %{"preset" => preset}, socket) do
    case benchmark_presets()[preset] do
      nil ->
        {:noreply, socket}

      patch ->
        merged =
          socket.assigns.form.params
          |> Map.merge(patch)

        {:noreply, assign(socket, :form, to_form(merged, as: :benchmark))}
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
            <div>
              <h3>Domain packs</h3>
              <p class="ck-note">
                {Enum.map_join(Benchmark.domain_packs_for_run(@run), ", ", &format_domain_pack/1)}
              </p>
            </div>
          </div>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Promotion integrity</p>
          <% integrity = get_in(Benchmark.run_eval_profile(@run), ["promotion_integrity"]) || %{} %>
          <div class="ck-finding-head">
            <h3>{integrity["status"] || "unknown"}</h3>
            <span class="ck-pill ck-pill-neutral">
              {Enum.join(integrity["evidence_channels"] || [], ", ")}
            </span>
          </div>
          <p class="ck-note">
            <%= case integrity["warnings"] || [] do %>
              <% [] -> %>
                Held-out, diversity, and classification evidence are present for this run.
              <% warnings -> %>
                Warnings: {Enum.join(warnings, ", ")}
            <% end %>
          </p>
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
                      <p class="ck-note">
                        {format_domain_pack(get_in(row.scenario.metadata || %{}, ["domain_pack"]))} • {get_in(
                          row.scenario.metadata || %{},
                          ["risk_tier"]
                        ) || "n/a"}
                      </p>
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

        <div class="ck-grid ck-grid-dashboard" style="margin-top: 1.5rem;">
          <div class="ck-card">
            <p class="ck-mini-label">Blessed external path</p>
            <h3 style="margin: 0 0 0.5rem;">OpenCode vs ControlKeel</h3>
            <p class="ck-note">
              The recommended first external comparison path is OpenCode. Start with a manual import
              subject for the quickest reproducible run, then swap to a shell-based wrapper if you
              want fully scripted replay.
            </p>
            <ul class="ck-mini-list" style="margin-top: 0.75rem;">
              <li>
                Create `controlkeel/benchmark_subjects.json` from `docs/examples/opencode-benchmark-subjects.json`.
              </li>
              <li>
                Run the suite once with `opencode_manual` to create awaiting-import placeholders.
              </li>
              <li>
                Import captured OpenCode output or replace the subject with a scripted shell command later.
              </li>
            </ul>
          </div>
          <div class="ck-card">
            <p class="ck-mini-label">Available subjects</p>
            <div class="ck-tag-list">
              <%= for subject <- @available_subjects do %>
                <span class="ck-tag">{subject_label(subject)}</span>
              <% end %>
            </div>
            <p class="ck-note" style="margin-top: 0.75rem;">
              Built-ins are always present. External subjects appear when the current project has a
              `controlkeel/benchmark_subjects.json` file.
            </p>
          </div>
        </div>

        <div class="ck-card ck-browser-filters" style="margin-top: 1.5rem;">
          <.form for={@filter_form} id="benchmark-filters" phx-change="filter_domain">
            <div class="ck-filter-grid">
              <.input
                field={@filter_form[:domain_pack]}
                type="select"
                label="Domain pack"
                prompt="All domains"
                options={@domain_pack_options}
              />
            </div>
          </.form>
        </div>

        <div class="ck-card ck-browser-filters">
          <datalist id="benchmark-subject-suggestions">
            <%= for subject <- @available_subjects do %>
              <option value={subject["id"]}>{subject["label"] || subject["id"]}</option>
            <% end %>
          </datalist>
          <p class="ck-mini-label" style="margin-bottom: 0.5rem;">Quick presets</p>
          <div class="ck-action-row" style="margin-bottom: 1rem; flex-wrap: wrap; gap: 0.5rem;">
            <button
              type="button"
              class="ck-link"
              id="benchmark-preset-opencode"
              phx-click="preset_benchmark"
              phx-value-preset="opencode_compare"
            >
              OpenCode comparison
            </button>
            <button
              type="button"
              class="ck-link"
              id="benchmark-preset-ck-only"
              phx-click="preset_benchmark"
              phx-value-preset="ck_only"
            >
              ControlKeel validate only
            </button>
            <button
              type="button"
              class="ck-link"
              id="benchmark-preset-proxy"
              phx-click="preset_benchmark"
              phx-value-preset="ck_proxy"
            >
              Validate + governed proxy
            </button>
          </div>
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
                label="Subjects (comma-separated)"
                placeholder="controlkeel_validate,opencode_manual"
                list="benchmark-subject-suggestions"
                id="benchmark-subjects-input"
              />
              <.input
                field={@form[:baseline_subject]}
                type="text"
                label="Baseline subject"
                placeholder="controlkeel_validate"
                list="benchmark-subject-suggestions"
                id="benchmark-baseline-input"
              />
              <.input
                field={@form[:domain_pack]}
                type="select"
                label="Run only this domain"
                prompt="All suite scenarios"
                options={@domain_pack_options}
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
          <p class="ck-note" style="margin-top: 0.5rem;">
            For a reproducible external comparison, start with `controlkeel_validate,opencode_manual`
            and import the OpenCode output after the placeholder run finishes.
          </p>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Built-in suites</p>
            <div class="ck-finding-list">
              <%= for suite <- @suites do %>
                <article class="ck-finding-item" id={"suite-#{suite.slug}"}>
                  <div class="ck-finding-head">
                    <h3>{suite.name}</h3>
                    <span class="ck-pill ck-pill-neutral">v{suite.version}</span>
                  </div>
                  <p class="ck-note">{suite.description}</p>
                  <div class="ck-metric-row">
                    <span>{length(suite.scenarios)} scenarios</span>
                    <span>{suite.status}</span>
                  </div>
                  <div class="ck-tag-list" style="margin-top: 0.5rem;">
                    <%= for pack <- Benchmark.domain_packs_for_suite(suite) do %>
                      <span class="ck-tag">{format_domain_pack(pack)}</span>
                    <% end %>
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
                <:col :let={run} label="Domains">
                  {Enum.map_join(Benchmark.domain_packs_for_run(run), ", ", &format_domain_pack/1)}
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
                <p :if={@active_router_artifact} class="ck-note">
                  Integrity: {policy_integrity_label(@active_router_artifact)}
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
                <p :if={@active_budget_artifact} class="ck-note">
                  Integrity: {policy_integrity_label(@active_budget_artifact)}
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
      "subjects" => "controlkeel_validate,opencode_manual",
      "baseline_subject" => "controlkeel_validate",
      "domain_pack" => ""
    }
  end

  defp benchmark_presets do
    %{
      "opencode_compare" => %{
        "subjects" => "controlkeel_validate,opencode_manual",
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_only" => %{
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_proxy" => %{
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate"
      }
    }
  end

  defp default_policy_params do
    %{"type" => "router"}
  end

  defp refresh_dashboard_assigns(socket, domain_pack \\ nil) do
    active = PolicyTraining.active_artifacts_summary()
    filter_opts = benchmark_filter_opts(domain_pack)

    socket
    |> assign(:summary, Benchmark.benchmark_summary(filter_opts))
    |> assign(:suites, Benchmark.list_suites(filter_opts))
    |> assign(:recent_runs, Benchmark.list_recent_runs(filter_opts))
    |> assign(:available_subjects, Benchmark.available_subjects())
    |> assign(:recent_training_runs, PolicyTraining.list_training_runs())
    |> assign(:active_router_artifact, active["router"])
    |> assign(:active_budget_artifact, active["budget_hint"])
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp subject_label(subject) do
    label = subject["label"] || subject["id"] || "Unknown subject"

    suffix =
      cond do
        subject["configured"] == false -> " (needs config)"
        subject["type"] in ["manual_import", "shell"] -> " (external)"
        true -> ""
      end

    label <> suffix
  end

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

  defp policy_integrity_label(nil), do: "not available"

  defp policy_integrity_label(artifact) do
    integrity = get_in(artifact.metrics || %{}, ["gates", "integrity"]) || %{}
    warnings = integrity["warnings"] || []

    case warnings do
      [] -> integrity["status"] || "ready"
      _ -> "#{integrity["status"] || "warn"} (#{Enum.join(warnings, ", ")})"
    end
  end

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  defp domain_filter_params(filters) do
    filters
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp domain_pack_options do
    Enum.map(Intent.supported_packs(), &{Intent.pack_label(&1), &1})
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)
end
