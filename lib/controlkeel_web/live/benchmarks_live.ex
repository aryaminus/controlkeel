defmodule ControlKeelWeb.BenchmarksLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Benchmark
  alias ControlKeel.Intent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benchmarks")
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:eval_profile, %{})
     |> assign(:comparison, nil)
     |> assign(:import_slots, [])
     |> assign(:import_form, empty_import_form())
     |> assign(:subjects_dropdown_open, false)
     |> assign(:active_preset, "opencode_compare")
     |> assign(:form, to_form(default_form_params(), as: :benchmark))
     |> assign(:domain_pack_options, domain_pack_options())
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
         |> assign_run_details(run)
         |> assign(:page_title, "Benchmark Run #{run.id}")
         |> assign(:page_action, %{
           label: "Export CSV",
           to: ~p"/api/v1/benchmarks/runs/#{run.id}/export?format=csv",
           icon: "hero-document-text"
         })}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:eval_profile, %{})
     |> assign(:comparison, nil)
     |> assign(:import_slots, [])
     |> assign(:import_form, empty_import_form())
     |> assign(:page_title, "Benchmarks")
     |> assign(:page_action, nil)
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

  @impl true
  def handle_event(
        "import_result",
        %{"import" => import_params},
        %{assigns: %{run: run}} = socket
      )
      when is_struct(run, Benchmark.Run) do
    %{"subject" => subject, "scenario_slug" => scenario_slug, "payload" => payload_json} =
      import_params

    with {:ok, decoded} <- decode_import_payload(payload_json),
         attrs = Map.put(decoded, "scenario_slug", scenario_slug),
         {:ok, updated_run} <- Benchmark.import_result(run.id, subject, attrs) do
      label = subject_label_by_id(socket.assigns.subjects_by_id, subject)

      {:noreply,
       socket
       |> assign_run_details(updated_run)
       |> put_flash(:info, "Imported #{label} result for #{scenario_slug}.")}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Import payload must be valid JSON: #{Exception.message(error)}"
         )}

      {:error, :invalid_payload_shape} ->
        {:noreply, put_flash(socket, :error, "Import payload must be a JSON object.")}

      {:error, :scenario_slug_required} ->
        {:noreply, put_flash(socket, :error, "Select a scenario for the import.")}

      {:error, :result_not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No matching benchmark result slot exists for that run, subject, and scenario_slug."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Benchmark run not found.")}

      # Not redundant despite the type checker's warning: Benchmark.import_result
      # can return unmodelled errors such as %Ecto.Changeset{} (same rationale as
      # ApiController.import_benchmark_result). Do not remove.
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to import benchmark output: #{inspect(reason)}")}
    end
  end

  def handle_event("import_result", _params, socket) do
    {:noreply, put_flash(socket, :error, "Import requires an open benchmark run.")}
  end

  def handle_event("preset_benchmark", %{"preset" => preset}, socket) do
    case benchmark_presets()[preset] do
      nil ->
        {:noreply, socket}

      patch ->
        merged =
          socket.assigns.form.params
          |> Map.merge(patch)

        {:noreply,
         socket
         |> assign(:form, to_form(merged, as: :benchmark))
         |> assign(:active_preset, preset)}
    end
  end

  def handle_event("toggle_subject", %{"id" => id}, socket) do
    current =
      socket.assigns.form.params["subjects"]
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    updated =
      if id in current do
        Enum.reject(current, &(&1 == id))
      else
        current ++ [id]
      end

    new_params = Map.put(socket.assigns.form.params, "subjects", updated)

    {:noreply,
     socket
     |> assign(:form, to_form(new_params, as: :benchmark))
     |> assign(:active_preset, nil)}
  end

  def handle_event("toggle_subjects_dropdown", _params, socket) do
    {:noreply, assign(socket, :subjects_dropdown_open, !socket.assigns.subjects_dropdown_open)}
  end

  def handle_event("close_subjects_dropdown", _params, socket) do
    {:noreply, assign(socket, :subjects_dropdown_open, false)}
  end

  def handle_event("benchmark_form_change", %{"benchmark" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params, as: :benchmark))
     |> assign(:active_preset, nil)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="w-full space-y-8">
      <%!-- Key stat cards --%>
      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Catch rate</p>
            <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
              <.icon name="hero-shield-check" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@run.catch_rate}%
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-primary"
              style={"width: #{min(@run.catch_rate || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Catch performance across scenarios</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Block rate</p>
            <span class="rounded-full bg-warning/10 w-8 h-8 flex items-center justify-center text-warning">
              <.icon name="hero-no-symbol" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@detail_metrics.block_rate}%
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-warning"
              style={"width: #{min(@detail_metrics.block_rate || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Active violation blocks</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Expected rule hit rate</p>
            <span class="rounded-full bg-success/10 w-8 h-8 flex items-center justify-center text-success">
              <.icon name="hero-check-badge" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@detail_metrics.expected_rule_hit_rate}%
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-success"
              style={"width: #{min(@detail_metrics.expected_rule_hit_rate || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Target rule activation rate</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Average overhead</p>
            <span class="rounded-full bg-info/10 w-8 h-8 flex items-center justify-center text-info">
              <.icon name="hero-clock" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_percent(@run.average_overhead_percent)}
          </p>
          <p class="mt-4 text-xs text-muted-foreground">
            Median latency {format_latency(@run.median_latency_ms)}
          </p>
        </article>
      </div>

      <%!-- Run metadata panel --%>
      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Run metadata</.section_title>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <p class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Status
            </p>
            <div class="mt-1">
              <span class={[
                "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize border",
                status_badge_class(@run.status)
              ]}>
                {run_status_label(@run.status)}
              </span>
            </div>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Baseline subject
            </p>
            <p class="mt-1 text-sm font-medium text-foreground/90">
              {subject_label_by_id(@subjects_by_id, @run.baseline_subject)}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Subjects
            </p>
            <p class="mt-1 text-sm font-medium text-foreground/90">
              {Enum.map_join(@run.subjects, ", ", &subject_label_by_id(@subjects_by_id, &1))}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Domain packs
            </p>
            <div class="mt-1 flex flex-wrap gap-1.5">
              <%= for pack <- Benchmark.domain_packs_for_run(@run) do %>
                <span class="inline-flex rounded-full bg-muted px-2.5 py-0.5 text-xs text-muted-foreground">
                  {format_domain_pack(pack)}
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </section>

      <%!-- Promotion integrity panel --%>
      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
        <% integrity = get_in(@eval_profile, ["promotion_integrity"]) || %{} %>
        <div class="flex items-center justify-between gap-4">
          <.section_title>Promotion integrity</.section_title>
          <span
            :if={(integrity["evidence_channels"] || []) != []}
            class="inline-flex rounded-full bg-primary/10 px-2.5 py-1 text-xs font-semibold text-primary"
          >
            {Enum.join(integrity["evidence_channels"], ", ")}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <.card_title>{integrity["status"] || "unknown"}</.card_title>
        </div>
        <p class="text-sm text-muted-foreground">
          <%= case integrity["warnings"] || [] do %>
            <% [] -> %>
              Held-out, diversity, and classification evidence are present for this run.
            <% warnings -> %>
              Warnings: {Enum.join(warnings, ", ")}
          <% end %>
        </p>
      </section>

      <%!-- Manual import panel (awaiting-import only) --%>
      <%= if @run.status == "awaiting_import" and @import_slots != [] do %>
        <section id="import-panel" class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Manual import</.section_title>
          <p class="text-sm text-muted-foreground">
            This run is waiting on imported results for the slots below. Paste the captured subject output as JSON (for example an OpenCode transcript artifact) to complete the run.
          </p>

          <ul class="flex flex-wrap gap-2" id="import-slots">
            <%= for slot <- @import_slots do %>
              <li
                id={"import-slot-#{slot.subject}-#{slot.scenario_slug}"}
                class="inline-flex items-center rounded-full bg-muted border px-3 py-1 text-xs text-muted-foreground"
              >
                {subject_label_by_id(@subjects_by_id, slot.subject)} · {slot.scenario_name}
              </li>
            <% end %>
          </ul>

          <.form
            for={@import_form}
            id="benchmark-import-form"
            phx-submit="import_result"
            class="space-y-4"
          >
            <div class="grid gap-4 sm:grid-cols-2">
              <div>
                <label
                  class="block text-sm font-medium text-muted-foreground mb-1"
                  for="import-subject"
                >
                  Subject
                </label>
                <select
                  id="import-subject"
                  name="import[subject]"
                  class="select w-full rounded-xl border bg-card px-3 py-2 text-sm text-foreground focus:outline-none focus:border-primary"
                >
                  <%= for subject <- @import_slots |> Enum.map(& &1.subject) |> Enum.uniq() do %>
                    <option value={subject}>
                      {subject_label_by_id(@subjects_by_id, subject)}
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label
                  class="block text-sm font-medium text-muted-foreground mb-1"
                  for="import-scenario"
                >
                  Scenario
                </label>
                <select
                  id="import-scenario"
                  name="import[scenario_slug]"
                  class="select w-full rounded-xl border bg-card px-3 py-2 text-sm text-foreground focus:outline-none focus:border-primary"
                >
                  <%= for slot <- @import_slots do %>
                    <option value={slot.scenario_slug}>
                      {slot.scenario_name} ({slot.scenario_slug})
                    </option>
                  <% end %>
                </select>
              </div>
            </div>

            <div>
              <label
                class="block text-sm font-medium text-muted-foreground mb-1"
                for="import-payload"
              >
                Result JSON
              </label>
              <textarea
                id="import-payload"
                name="import[payload]"
                rows="6"
                required
                placeholder='{"content": "...", "path": "app/main.py", "kind": "code", "duration_ms": 12, "metadata": {}}'
                class="w-full rounded-xl border bg-card px-3 py-2 text-foreground font-mono text-xs focus:outline-none focus:border-primary"
              />
            </div>

            <div>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
              >
                Import result
              </button>
            </div>
          </.form>
        </section>
      <% end %>

      <%!-- Comparison panel --%>
      <section id="comparison-panel" class="rounded-2xl border bg-card p-5 shadow-card space-y-6">
        <.section_title>Subject comparison</.section_title>

        <%= if @comparison do %>
          <% summary = @comparison["summary"] %>
          <div class="space-y-1">
            <.card_title>{summary["headline"]}</.card_title>
            <p class="text-sm text-foreground/90">
              Best subject:
              <span class="font-semibold text-primary">
                {subject_label_by_id(@subjects_by_id, summary["best_subject"])}
              </span>
              <span class="text-muted-foreground">
                (catch {format_percent(summary["best_catch_rate"])}, max lift {format_delta_points(
                  summary["max_catch_rate_lift_points"]
                )} pts)
              </span>
            </p>
            <p class="text-sm text-muted-foreground">{summary["efficiency_headline"]}</p>
          </div>

          <div
            class="rounded-xl border bg-muted/40 p-4 font-mono text-xs text-muted-foreground overflow-x-auto space-y-1"
            id="comparison-chart"
          >
            <%= for row <- @comparison["chart"] do %>
              <p class="whitespace-pre" id={"comparison-chart-#{row["subject"]}"}>
                {row["label"]}
              </p>
            <% end %>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <%= for metrics <- @comparison["subjects"] do %>
              <% delta = metrics["delta_vs_baseline"] || %{} %>
              <% classification = metrics["classification"] || %{} %>
              <article
                id={"comparison-subject-#{metrics["subject"]}"}
                class="rounded-xl border bg-muted/20 p-4 space-y-3"
              >
                <div class="flex items-center justify-between gap-2">
                  <strong class="font-semibold text-foreground/90">
                    {subject_label_by_id(@subjects_by_id, metrics["subject"])}
                  </strong>
                  <div class="flex items-center gap-1.5 shrink-0">
                    <%= if metrics["is_baseline"] do %>
                      <span class="inline-flex rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                        baseline
                      </span>
                    <% end %>
                    <%= if metrics["subject"] == summary["best_subject"] do %>
                      <span class="inline-flex rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                        best catch rate
                      </span>
                    <% end %>
                  </div>
                </div>

                <div class="space-y-1.5 text-sm">
                  <p class="text-foreground/90">
                    Catch <span class="font-semibold">{format_percent(metrics["catch_rate"])}</span>
                    <span class="text-muted-foreground">
                      (Δ {format_delta_points(delta["catch_rate_points"])} pts)
                    </span>
                  </p>
                  <p class="text-foreground/90">
                    Block <span class="font-semibold">{format_percent(metrics["block_rate"])}</span>
                    <span class="text-muted-foreground">
                      (Δ {format_delta_points(delta["block_rate_points"])} pts)
                    </span>
                  </p>
                  <p class="text-foreground/90">
                    Expected rule hit
                    <span class="font-semibold">
                      {format_percent(metrics["expected_rule_hit_rate"])}
                    </span>
                    <span class="text-muted-foreground">
                      (Δ {format_delta_points(delta["expected_rule_hit_rate_points"])} pts)
                    </span>
                  </p>
                  <p class="text-xs text-muted-foreground pt-1.5 border-t border-border">
                    TPR {format_ratio_percent(classification["tpr"])} · FPR {format_ratio_percent(
                      classification["fpr"]
                    )} · Youden's J {format_ratio_percent(classification["youdens_j"])}
                  </p>
                  <p class="text-xs text-muted-foreground">
                    Latency {format_latency(metrics["median_latency_ms"])}
                    <span class="text-muted-foreground/80">
                      (Δ {format_signed_ms(delta["latency_ms"])})
                    </span>
                    · Tokens {metrics["total_tokens"] || 0}
                    <span class="text-muted-foreground/80">
                      (Δ {format_signed_int(delta["total_tokens"])})
                    </span>
                    · Cost {format_cents(metrics["estimated_cost_cents"])}
                    <span class="text-muted-foreground/80">
                      (Δ {format_signed_cents(delta["estimated_cost_cents"])})
                    </span>
                  </p>
                  <p class="text-xs text-muted-foreground">
                    CK tool calls {metrics["ck_tool_call_count"] || 0}
                    <span class="text-muted-foreground/80">
                      ({format_percent(metrics["ck_tool_call_rate"])} of tasks)
                    </span>
                  </p>
                </div>
              </article>
            <% end %>
          </div>

          <div class="rounded-xl border bg-muted/20 p-4 space-y-2 text-sm">
            <p>
              <span class="font-semibold text-foreground">Safe claim:</span>
              <span class="text-muted-foreground">
                {get_in(@comparison, ["claim_guidance", "safe_claim"])}
              </span>
            </p>
            <p>
              <span class="font-semibold text-foreground">Caveat:</span>
              <span class="text-muted-foreground">
                {get_in(@comparison, ["claim_guidance", "caveat"])}
              </span>
            </p>
          </div>
        <% else %>
          <div class="rounded-xl border border-dashed p-8 text-center">
            <p class="text-sm font-medium text-foreground">No comparable subjects</p>
            <p class="text-xs text-muted-foreground mt-1">
              Comparison needs a run with at least two distinct subjects.
            </p>
          </div>
        <% end %>
      </section>

      <%!-- Scenario matrix panel --%>
      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <div class="flex items-center justify-between gap-4">
          <.section_title>Scenario matrix</.section_title>
          <span class="text-xs text-muted-foreground">
            {length(@matrix.scenarios)} {if length(@matrix.scenarios) == 1,
              do: "scenario",
              else: "scenarios"}
          </span>
        </div>

        <%= if @matrix.scenarios == [] do %>
          <div class="rounded-xl border border-dashed p-8 text-center">
            <p class="text-sm font-medium text-foreground">No scenarios recorded</p>
            <p class="text-xs text-muted-foreground mt-1">
              This run has no scenario results yet.
            </p>
          </div>
        <% else %>
          <div class="grid gap-4 md:grid-cols-2">
            <%= for row <- @matrix.scenarios do %>
              <article
                id={"scenario-#{row.scenario.slug}"}
                class="rounded-xl border bg-muted/20 p-4 space-y-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0 space-y-0.5">
                    <strong class="block text-sm font-semibold text-foreground/90">
                      {row.scenario.name}
                    </strong>
                    <p class="text-xs text-muted-foreground">
                      {row.scenario.incident_label}
                    </p>
                  </div>
                  <div class="flex flex-col items-end gap-1 shrink-0">
                    <span class="inline-flex rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                      {format_domain_pack(get_in(row.scenario.metadata || %{}, ["domain_pack"]))}
                    </span>
                    <span class="text-[10px] uppercase tracking-wider text-muted-foreground font-medium">
                      {get_in(row.scenario.metadata || %{}, ["risk_tier"]) || "n/a"}
                    </span>
                  </div>
                </div>

                <div class="space-y-2">
                  <%= for {result, subject_id} <- Enum.zip(row.results, @matrix.subjects) do %>
                    <.scenario_result
                      result={result}
                      subject_label={subject_label_by_id(@subjects_by_id, subject_id)}
                    />
                  <% end %>
                </div>
              </article>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="w-full space-y-8">
      <.page_title
        title="Benchmark engine"
        subtitle="Compare governed subjects and external agents on the same scenario suites, then keep the results as product evidence."
      />

      <div class="grid gap-6 lg:grid-cols-3">
        <%!-- Runner form & presets panel --%>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-6 lg:col-span-2">
          <div class="space-y-3">
            <.section_title>Quick presets</.section_title>
            <p class="text-sm text-muted-foreground max-w-xl leading-relaxed">
              One-click subject and suite configurations. Pick one to populate the form below.
            </p>

            <div class="flex flex-wrap gap-2">
              <button
                :for={{preset_id, preset_value, preset_label} <- preset_chips()}
                type="button"
                id={preset_id}
                phx-click="preset_benchmark"
                phx-value-preset={preset_value}
                aria-pressed={to_string(preset_value == @active_preset)}
                class={[
                  "inline-flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-xs font-semibold transition cursor-pointer",
                  if(preset_value == @active_preset,
                    do: "border-primary/40 bg-primary/10 text-primary",
                    else: "bg-muted text-muted-foreground hover:bg-muted/80 hover:text-foreground"
                  )
                ]}
              >
                {preset_label}
              </button>
            </div>
          </div>

          <.form
            for={@form}
            id="benchmark-runner"
            phx-submit="run"
            phx-change="benchmark_form_change"
            class="space-y-4"
          >
            <div class="flex flex-col gap-4">
              <.input
                field={@form[:suite]}
                type="select"
                label="Suite"
                options={Enum.map(@suites, &{"#{&1.name} (#{&1.slug})", &1.slug})}
              />
              <.subject_multi_select
                field={@form[:subjects]}
                label="Subjects"
                options={subject_options(@available_subjects)}
                selected={@form[:subjects].value}
                open={@subjects_dropdown_open}
                id="benchmark-subjects-input"
              />
              <.input
                field={@form[:baseline_subject]}
                type="select"
                label="Baseline subject"
                options={subject_options(@available_subjects)}
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
            <div class="flex items-center justify-between gap-4 pt-2">
              <p class="text-xs text-muted-foreground">
                Configure the suite above, then start the run.
              </p>
              <.button type="submit" class="shrink-0">
                <.icon name="hero-play" class="size-4" /> Run benchmark
              </.button>
            </div>
          </.form>
          <p class="text-xs text-muted-foreground">
            For a reproducible external comparison, start with
            <code class="font-mono text-foreground/80">controlkeel_validate,opencode_manual</code>
            and import the OpenCode output after the awaiting-import run finishes.
          </p>
        </section>

        <%!-- Aggregate summary & blessed external path --%>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-6 h-fit">
          <div class="grid grid-cols-2 gap-4 border-b border-border pb-5">
            <div>
              <p class="text-xs font-medium text-muted-foreground">Suites</p>
              <p class="mt-1 text-xl font-semibold text-foreground/90">{@summary.total_suites}</p>
            </div>
            <div>
              <p class="text-xs font-medium text-muted-foreground">Runs</p>
              <p class="mt-1 text-xl font-semibold text-foreground/90">{@summary.total_runs}</p>
            </div>
            <div>
              <p class="text-xs font-medium text-muted-foreground">Avg Catch Rate</p>
              <p class="mt-1 text-xl font-semibold text-foreground/90">
                {format_percent(@summary.average_catch_rate)}
              </p>
            </div>
            <div>
              <p class="text-xs font-medium text-muted-foreground">Avg Overhead</p>
              <p class="mt-1 text-xl font-semibold text-foreground/90">
                {format_percent(@summary.average_overhead_percent)}
              </p>
            </div>
          </div>

          <div class="space-y-2">
            <.section_title>OpenCode vs ControlKeel</.section_title>
            <p class="text-sm text-muted-foreground leading-relaxed">
              The recommended first external comparison path is OpenCode. Start with a manual import
              subject for the quickest reproducible run, then swap to a shell-based wrapper if you
              want fully scripted replay.
            </p>
            <ul class="space-y-2 pt-2 text-xs text-muted-foreground list-disc ml-4">
              <li>
                Create or review
                <code class="font-mono text-foreground/80">controlkeel/benchmark_subjects.json</code>
                with the OpenCode subject you want to import.
              </li>
              <li>
                Run the suite once with
                <code class="font-mono text-foreground/80">opencode_manual</code>
                to create awaiting-import records.
              </li>
              <li>
                Import captured OpenCode output or replace the subject with a scripted shell command later.
              </li>
            </ul>
          </div>
        </section>
      </div>

      <%!-- Recent runs table --%>
      <section class="rounded-2xl border bg-card shadow-card overflow-clip">
        <div class="p-5 border-b border-border flex items-center justify-between gap-3">
          <.section_title>Recent runs</.section_title>
          <span :if={@recent_runs != []} class="text-xs text-muted-foreground">
            {length(@recent_runs)} {if length(@recent_runs) == 1, do: "run", else: "runs"}
          </span>
        </div>
        <div class="overflow-x-auto">
          <table id="benchmark-runs" class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
              <tr>
                <th class="px-5 py-3 font-semibold">Suite</th>
                <th class="px-5 py-3 font-semibold">Status</th>
                <th class="px-5 py-3 font-semibold">Catch rate</th>
                <th class="px-5 py-3 font-semibold">Baseline</th>
                <th class="px-5 py-3 font-semibold">Domains</th>
                <th class="px-5 py-3 font-semibold text-right">Overhead</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= if @recent_runs == [] do %>
                <tr>
                  <td colspan="6" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-foreground">No benchmark runs yet.</p>
                    <p class="mt-1 text-sm text-muted-foreground">
                      Pick a preset above and run your first suite to see results here.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for run <- @recent_runs do %>
                  <tr id={"run-#{run.id}"} class="relative transition hover:bg-muted/30">
                    <td class="px-5 py-4 font-semibold">
                      <.link
                        navigate={~p"/benchmarks/runs/#{run.id}"}
                        class="text-foreground/90 hover:text-primary after:absolute after:inset-0"
                      >
                        {run.suite.name || run.suite.slug}
                      </.link>
                    </td>
                    <td class="px-5 py-4">
                      <span class={[
                        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize border",
                        status_badge_class(run.status)
                      ]}>
                        {run_status_label(run.status)}
                      </span>
                    </td>
                    <td class="px-5 py-4 font-semibold text-foreground/90">
                      {format_percent(run.catch_rate)}
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      {subject_label_by_id(@subjects_by_id, run.baseline_subject)}
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex flex-wrap gap-1.5">
                        <%= for pack <- Benchmark.domain_packs_for_run(run) do %>
                          <span class="inline-flex rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                            {format_domain_pack(pack)}
                          </span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-5 py-4 text-right text-muted-foreground font-mono">
                      {format_percent(run.average_overhead_percent)}
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>

      <%!-- Built-in suites catalog --%>
      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <div>
          <.section_title>Built-in suites</.section_title>
          <p class="text-xs text-muted-foreground mt-1">
            Built-ins are always present. External subjects appear when the current project has a
            <code class="font-mono text-foreground/80">controlkeel/benchmark_subjects.json</code>
            file.
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 mt-4">
          <%= for suite <- @suites do %>
            <article
              class="rounded-xl border bg-muted/20 p-4 space-y-3 flex flex-col justify-between"
              id={"suite-#{suite.slug}"}
            >
              <div class="space-y-2">
                <div class="flex items-center justify-between gap-3">
                  <.card_title>{suite.name}</.card_title>
                  <span class="inline-flex rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary shrink-0">
                    v{suite.version}
                  </span>
                </div>
                <p class="text-xs text-muted-foreground line-clamp-2">{suite.description}</p>
              </div>
              <div class="space-y-2 pt-2 border-t border-border/50">
                <div class="flex items-center justify-between text-xs text-muted-foreground">
                  <span>{length(suite.scenarios)} scenarios</span>
                  <span class="capitalize">{suite.status}</span>
                </div>
                <div class="flex flex-wrap gap-1.5">
                  <%= for pack <- Benchmark.domain_packs_for_suite(suite) do %>
                    <span class="inline-flex rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                      {format_domain_pack(pack)}
                    </span>
                  <% end %>
                </div>
              </div>
            </article>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp default_form_params do
    %{
      "suite" => "vibe_failures_v1",
      "subjects" => ["controlkeel_validate", "opencode_manual"],
      "baseline_subject" => "controlkeel_validate",
      "domain_pack" => ""
    }
  end

  defp preset_chips do
    [
      {"benchmark-preset-opencode", "opencode_compare", "OpenCode comparison"},
      {"benchmark-preset-ck-only", "ck_only", "ControlKeel validate only"},
      {"benchmark-preset-proxy", "ck_proxy", "Validate + governed proxy"},
      {"benchmark-preset-copilot-vs-opencode", "copilot_vs_opencode", "Copilot vs OpenCode"},
      {"benchmark-preset-full-compare", "full_compare", "Full host comparison"}
    ]
  end

  defp benchmark_presets do
    %{
      "opencode_compare" => %{
        "subjects" => ["controlkeel_validate", "opencode_manual"],
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_only" => %{
        "subjects" => ["controlkeel_validate"],
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_proxy" => %{
        "subjects" => ["controlkeel_validate", "controlkeel_proxy"],
        "baseline_subject" => "controlkeel_validate"
      },
      "copilot_vs_opencode" => %{
        "suite" => "host_comparison_v1",
        "subjects" => ["controlkeel_validate", "opencode_manual", "copilot_manual"],
        "baseline_subject" => "controlkeel_validate"
      },
      "full_compare" => %{
        "suite" => "host_comparison_v1",
        "subjects" => [
          "controlkeel_validate",
          "opencode_manual",
          "copilot_manual",
          "gemini_manual",
          "codex_manual",
          "claude_manual"
        ],
        "baseline_subject" => "controlkeel_validate"
      }
    }
  end

  defp refresh_dashboard_assigns(socket) do
    subjects = Benchmark.available_subjects()

    socket
    |> assign(:summary, Benchmark.benchmark_summary([]))
    |> assign(:suites, Benchmark.list_suites([]))
    |> assign(:recent_runs, Benchmark.list_recent_runs([]))
    |> assign(:available_subjects, subjects)
    |> assign(:subjects_by_id, Map.new(subjects, fn s -> {s["id"], s} end))
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp comparable_run?(%Benchmark.Run{subjects: subjects}) do
    # Optimize unique count by avoiding intermediate list allocations
    subjects |> List.wrap() |> MapSet.new() |> MapSet.size() >= 2
  end

  defp assign_run_details(socket, %Benchmark.Run{} = run) do
    socket
    |> assign(:run, run)
    |> assign(:matrix, Benchmark.run_matrix(run))
    |> assign(:detail_metrics, Benchmark.run_detail_metrics(run))
    |> assign(:eval_profile, Benchmark.run_eval_profile(run))
    |> assign(:comparison, if(comparable_run?(run), do: Benchmark.compare_run(run), else: nil))
    |> assign(:import_slots, import_slots(run))
  end

  defp import_slots(%Benchmark.Run{} = run) do
    run.results
    |> Enum.filter(&(&1.status == "awaiting_import"))
    |> Enum.sort_by(&{&1.subject, &1.scenario.position})
    |> Enum.map(fn result ->
      %{
        subject: result.subject,
        scenario_slug: result.scenario.slug,
        scenario_name: result.scenario.name
      }
    end)
  end

  defp empty_import_form do
    to_form(%{"subject" => "", "scenario_slug" => "", "payload" => ""}, as: :import)
  end

  defp decode_import_payload(json) do
    case Jason.decode(json) do
      {:ok, attrs} when is_map(attrs) -> {:ok, attrs}
      {:ok, _other} -> {:error, :invalid_payload_shape}
      {:error, %Jason.DecodeError{} = error} -> {:error, error}
    end
  end

  defp format_signed(nil, _suffix, _decimals), do: "n/a"

  defp format_signed(value, suffix, decimals) when is_number(value) do
    formatted =
      if decimals do
        :erlang.float_to_binary(value / 1, decimals: decimals)
      else
        Integer.to_string(round(value))
      end

    if value >= 0 do
      "+#{formatted}#{suffix}"
    else
      "#{formatted}#{suffix}"
    end
  end

  defp format_delta_points(value), do: format_signed(value, "", 1)
  defp format_signed_int(value), do: format_signed(value, "", nil)
  defp format_signed_ms(value), do: format_signed(value, " ms", nil)
  defp format_signed_cents(value), do: format_signed(value, "¢", 1)

  defp format_ratio_percent(nil), do: "n/a"

  defp format_ratio_percent(value) when is_number(value),
    do: "#{Float.round(value * 100, 1)}%"

  defp format_cents(nil), do: "n/a"

  defp format_cents(value) when is_number(value),
    do: "#{:erlang.float_to_binary(value / 1, decimals: 1)}¢"

  defp decision_badge_class("block"),
    do: "bg-destructive/10 text-destructive border-destructive/20"

  defp decision_badge_class("warn"),
    do: "bg-warning/10 text-warning border-warning/20"

  defp decision_badge_class("allow"),
    do: "bg-success/10 text-success border-success/20"

  defp decision_badge_class(_),
    do: "bg-muted text-muted-foreground border-border"

  defp decision_label(nil), do: "no ruling"
  defp decision_label("block"), do: "blocked"
  defp decision_label("warn"), do: "warned"
  defp decision_label("allow"), do: "allowed"
  defp decision_label(other), do: other

  defp status_label(nil), do: "unknown"
  defp status_label("completed"), do: "completed"
  defp status_label("failed"), do: "failed"
  defp status_label("timed_out"), do: "timed out"
  defp status_label("awaiting_import"), do: "awaiting import"
  defp status_label("pending"), do: "pending"
  defp status_label(other), do: String.replace(other, "_", " ")

  defp status_badge_class(status) when status in ["failed", "timed_out"] do
    "bg-destructive/10 text-destructive border-destructive/20"
  end

  defp status_badge_class(status) when status in ["awaiting_import", "pending"] do
    "bg-warning/10 text-warning border-warning/20"
  end

  defp status_badge_class("completed") do
    "bg-success/10 text-success border-success/20"
  end

  defp status_badge_class(_) do
    "bg-muted text-muted-foreground border-border"
  end

  defp subject_options(subjects) do
    Enum.map(subjects, fn subject ->
      {subject_label(subject), subject["id"]}
    end)
  end

  defp scenario_result(assigns) do
    ~H"""
    <div class="rounded-lg bg-card/60 border border-border/50 px-3 py-2.5 space-y-1.5">
      <%= if @result do %>
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="text-xs font-semibold text-foreground/90 truncate">{@subject_label}</span>
            <%= if @result.matched_expected do %>
              <.icon name="hero-check-badge" class="size-4 text-primary shrink-0" />
            <% end %>
          </div>
          <div class="flex flex-wrap gap-1.5 justify-end shrink-0">
            <span class={[
              "inline-flex rounded-full px-2 py-0.5 text-[0.7rem] font-medium border",
              decision_badge_class(@result.decision)
            ]}>
              {decision_label(@result.decision)}
            </span>
            <span class={[
              "inline-flex rounded-full px-2 py-0.5 text-[0.7rem] font-medium border",
              status_badge_class(@result.status)
            ]}>
              {status_label(@result.status)}
            </span>
          </div>
        </div>
        <div class="flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-muted-foreground">
          <span>{@result.findings_count} findings</span>
          <span>latency {format_latency(@result.latency_ms)}</span>
          <span>overhead {format_percent(@result.overhead_percent)}</span>
        </div>
      <% else %>
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs text-muted-foreground truncate">{@subject_label}</span>
          <span class="text-[10px] text-muted-foreground uppercase tracking-wider font-medium">
            no result
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp subject_multi_select(assigns) do
    assigns =
      assigns
      |> assign(:selected, List.wrap(assigns[:selected]))
      |> assign(
        :labels_by_value,
        Map.new(assigns[:options] || [], fn {label, value} -> {value, label} end)
      )
      |> assign_new(:open, fn -> false end)

    ~H"""
    <div
      class="fieldset mb-2 relative"
      id={@id}
      phx-click-away={@open && "close_subjects_dropdown"}
    >
      <span :if={@label} class="label mb-1 block text-sm font-medium text-foreground">{@label}</span>
      <div :if={@selected != []} class="flex flex-wrap gap-2 mb-2">
        <span
          :for={selected_value <- @selected}
          class="inline-flex items-center gap-1 rounded-full border border-border bg-muted/50 text-muted-foreground pl-3 pr-1.5 py-1 text-xs"
        >
          {Map.get(@labels_by_value, selected_value, selected_value)}
          <button
            type="button"
            phx-click="toggle_subject"
            phx-value-id={selected_value}
            aria-label={"Remove #{Map.get(@labels_by_value, selected_value, selected_value)}"}
            class="inline-flex items-center justify-center rounded-full p-0.5 hover:text-primary transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <.icon name="hero-x-mark" class="w-3 h-3" />
          </button>
        </span>
      </div>
      <button
        type="button"
        phx-click="toggle_subjects_dropdown"
        aria-haspopup="listbox"
        aria-expanded={to_string(@open)}
        class={[
          "select w-full flex items-center justify-between gap-2 px-3 py-2 text-left text-sm rounded-xl border bg-card text-foreground focus:outline-none focus:border-primary cursor-pointer"
        ]}
      >
        <span class="text-muted-foreground">Select subjects</span>
        <.icon
          name="hero-chevron-down"
          class={["w-4 h-4 shrink-0 transition-transform", @open && "rotate-180"]}
        />
      </button>
      <div
        :if={@open}
        class="absolute z-30 mt-1 w-full max-h-72 overflow-y-auto rounded-xl border bg-card shadow-card p-1"
        role="listbox"
        aria-label={@label}
        aria-multiselectable="true"
      >
        <button
          :for={{option_label, option_value} <- @options}
          type="button"
          role="option"
          aria-selected={if(option_value in @selected, do: "true", else: "false")}
          data-subject-id={option_value}
          phx-click="toggle_subject"
          phx-value-id={option_value}
          class={[
            "w-full flex items-center gap-2 px-3 py-2 rounded-lg text-left text-sm transition-colors cursor-pointer",
            if(option_value in @selected,
              do: "bg-primary/10 text-primary font-medium",
              else: "text-foreground hover:bg-muted"
            )
          ]}
        >
          <.icon
            name="hero-check"
            class={[
              "w-4 h-4 shrink-0",
              if(option_value in @selected, do: "text-primary", else: "opacity-0")
            ]}
          />
          <span class="truncate">{option_label}</span>
        </button>
      </div>
      <input
        :for={selected_value <- @selected}
        type="hidden"
        name={"#{@field.name}[]"}
        value={selected_value}
      />
    </div>
    """
  end

  defp subject_label_by_id(subjects_by_id, id) do
    subject_label(Map.get(subjects_by_id, id) || %{"id" => id})
  end

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

  defp domain_pack_options do
    Enum.map(Intent.supported_packs(), &{Intent.pack_label(&1), &1})
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)

  defp run_status_label(nil), do: "unknown"

  defp run_status_label(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.trim()
    |> String.capitalize()
  end
end
