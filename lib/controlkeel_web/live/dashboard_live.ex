defmodule ControlKeelWeb.DashboardLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Agent.ACPRegistry
  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    project_root = ControlKeelWeb.Endpoint.config(:project_root) || File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(
       benchmark_summary: Benchmark.benchmark_summary(),
       provider_status: ProviderBroker.status(project_root),
       recent_sessions: Mission.list_recent_sessions_for_user(socket.assigns[:current_user]),
       registry_status: ACPRegistry.status(),
       ship_summary: Analytics.funnel_summary(),
       runtime_mode: Mode.current()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <% catch_rate = @benchmark_summary.average_catch_rate
    overhead = @benchmark_summary.average_overhead_percent
    proof_coverage = @ship_summary.outcome_metrics.proof_backed_task_coverage_percent
    deploy_ready = @ship_summary.outcome_metrics.deploy_ready_task_rate_percent
    avg_findings = @ship_summary.average_findings_per_session %>

    <div class="w-full space-y-8">
      <.page_title
        title="Agent Control Plane"
        subtitle="Live session state, findings, proof coverage, benchmark signal, and ship readiness in one operator view."
      />

      <%!-- Key metrics --%>
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Benchmark Catch Rate</p>
            <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
              <.icon name="hero-shield-check" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_percent(catch_rate)}
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-primary"
              style={"width: #{min(catch_rate || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">
            {@benchmark_summary.total_runs} runs across {@benchmark_summary.total_suites} suites
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Proof Coverage</p>
            <span class="rounded-full bg-info/10 w-8 h-8 flex items-center justify-center text-info">
              <.icon name="hero-document-check" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_percent(proof_coverage)}
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-info"
              style={"width: #{min(proof_coverage || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Done tasks with attached evidence</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Deploy Ready Rate</p>
            <span class="rounded-full bg-success/10 w-8 h-8 flex items-center justify-center text-success">
              <.icon name="hero-rocket-launch" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_percent(deploy_ready)}
          </p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-success"
              style={"width: #{min(deploy_ready || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Release-ready task outcomes</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Finding Density</p>
            <span class="rounded-full bg-warning/10 w-8 h-8 flex items-center justify-center text-warning">
              <.icon name="hero-exclamation-triangle" class="size-4" />
            </span>
          </div>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_number(avg_findings)}
          </p>
          <p class="mt-4 text-xs text-muted-foreground">Average findings per recent session</p>
        </article>
      </div>

      <div class="grid gap-6 grid-cols-2 w-full">
        <%!-- Delivery Funnel --%>

        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-6">
          <div class="flex items-center justify-between gap-3">
            <.section_title>Delivery Funnel</.section_title>
            <span class="rounded-full border px-3 py-1 text-xs text-muted-foreground">
              {@ship_summary.recent_session_count} sessions
            </span>
          </div>

          <div class="space-y-4">
            <%= for step <- @ship_summary.steps do %>
              <div>
                <div class="flex items-center justify-between gap-3 text-sm">
                  <span class="capitalize text-muted-foreground">
                    {String.replace(step.step, "_", " ")}
                  </span>
                  <span class="font-semibold">{step.count}</span>
                </div>
                <div class="mt-2 h-2 overflow-hidden rounded-full bg-muted">
                  <div
                    class="h-full rounded-full bg-primary"
                    style={"width: #{min(step.conversion_percent || 0, 100)}%"}
                  />
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <%!-- Provider and bootstrap status --%>
        <section
          id="skills-provider-status"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-6"
        >
          <.section_title>
            Provider and bootstrap status
          </.section_title>

          <div class="space-y-2">
            <p class="text-sm text-muted-foreground">
              Provider:
              <span class="font-semibold text-foreground">
                {@provider_status["selected_provider"]} / {@provider_status[
                  "selected_model"
                ] ||
                  "default"}
              </span>
            </p>
            <p class="text-sm text-muted-foreground">
              Base URL:
              <span class="font-semibold text-foreground">
                {selected_base_url(@provider_status)}
              </span>
            </p>
            <p class="text-sm text-muted-foreground">
              Auth:
              <span class="font-semibold text-foreground">
                {@provider_status["selected_auth_mode"]} / {@provider_status[
                  "selected_auth_owner"
                ]}
              </span>
            </p>
            <p class="text-sm text-muted-foreground">
              Bootstrap mode:
              <span class="font-semibold text-foreground">
                {get_in(@provider_status, [
                  "bootstrap",
                  "mode"
                ]) || "unknown"}
              </span>
            </p>
            <p class="text-sm text-muted-foreground">
              Fallback chain:
              <span class="font-semibold text-foreground">
                {Enum.join(
                  @provider_status["fallback_chain"] || [],
                  ", "
                )}
              </span>
            </p>
          </div>
        </section>
      </div>

      <div class="grid gap-6 grid-cols-2 w-full">
        <%!-- ACP registry cache --%>
        <section
          id="skills-registry-status"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-6"
        >
          <div class="flex items-center justify-between gap-3">
            <.section_title>ACP registry cache</.section_title>
            <span class={[
              "rounded-full border px-3 py-1 text-xs",
              (@registry_status["stale"] && "border-warning/20 bg-warning/10 text-warning") ||
                "border-border bg-muted text-primary"
            ]}>
              {if @registry_status["stale"], do: "stale", else: "fresh"}
            </span>
          </div>

          <div class="flex items-start">
            <div class="grid gap-[0.55rem] flex-1">
              <p class="text-sm text-muted-foreground">
                Entries:
                <span class="font-semibold text-foreground">{@registry_status["entry_count"]}</span>
                / matched integrations:
                <span class="font-semibold text-foreground">
                  {@registry_status[
                    "matched_integrations"
                  ]}
                </span>
              </p>
              <p class="text-sm text-muted-foreground">
                Fetched at:
                <span class="font-semibold text-foreground">
                  {@registry_status["fetched_at"] ||
                    "never"}
                </span>
              </p>
            </div>
          </div>
        </section>

        <%!-- Signal Preview --%>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-6">
          <.section_title>Signal Preview</.section_title>

          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p class="text-muted-foreground">Avg overhead</p>
              <p class="mt-1 font-semibold">{format_percent(overhead)}</p>
            </div>

            <div>
              <p class="text-muted-foreground">First finding</p>
              <p class="mt-1 font-semibold">
                {if @ship_summary.average_time_to_first_finding_seconds,
                  do: "#{format_number(@ship_summary.average_time_to_first_finding_seconds)}s",
                  else: "Not recorded"}
              </p>
            </div>
          </div>
        </section>
      </div>

      <%!-- Provider and Autonomy --%>
      <section class="space-y-4">
        <.section_title>Provider and Autonomy</.section_title>

        <div class="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          <%!-- Provider snapshot --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
                <.icon name="hero-server-stack" class="size-4" />
              </span>
              <.card_title>Provider snapshot</.card_title>
            </div>
            <dl class="mt-4 space-y-3 text-sm">
              <div>
                <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Current mode
                </dt>
                <dd class="mt-0.5 font-medium text-foreground">
                  {provider_mode_label(@provider_status)}
                </dd>
              </div>
              <div>
                <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Current provider
                </dt>
                <dd class="mt-0.5 font-medium text-foreground">{provider_name(@provider_status)}</dd>
              </div>
              <div>
                <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Setup scope
                </dt>
                <dd class="mt-0.5 leading-6 text-muted-foreground">
                  {setup_scope_copy(@provider_status)}
                </dd>
              </div>
              <div>
                <dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Attached agents
                </dt>
                <dd class="mt-0.5 leading-6 text-muted-foreground">
                  {attached_agents_copy(@provider_status)}
                </dd>
              </div>
            </dl>
          </article>

          <%!-- Provider guidance --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-info/10 w-8 h-8 flex items-center justify-center text-info">
                <.icon name="hero-information-circle" class="size-4" />
              </span>
              <.card_title>Provider guidance</.card_title>
            </div>
            <p class="mt-4 text-sm leading-6 text-muted-foreground">
              {provider_guidance(@provider_status)}
            </p>
            <p class="mt-3 text-xs italic leading-5 text-muted-foreground">
              Autonomy and findings map to human review severity. LLM advisory requires a provider, while validate responses still report advisory status.
              See <code class="font-mono text-[11px] text-muted-foreground">docs/autonomy-and-findings.md</code>.
            </p>
          </article>

          <%!-- Resolution order --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
                <.icon name="hero-link" class="size-4" />
              </span>
              <.card_title>Resolution order</.card_title>
            </div>
            <ol class="mt-4 space-y-2 text-sm text-muted-foreground list-decimal ml-5">
              <%= for item <- provider_resolution_steps() do %>
                <li>{item}</li>
              <% end %>
            </ol>
          </article>

          <%!-- Always available --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-success/10 w-8 h-8 flex items-center justify-center text-success">
                <.icon name="hero-check-badge" class="size-4" />
              </span>
              <.card_title>Always available</.card_title>
            </div>
            <ul class="mt-4 space-y-2 text-sm text-muted-foreground list-disc ml-5">
              <%= for item <- always_available_capabilities() do %>
                <li>{item}</li>
              <% end %>
            </ul>
          </article>

          <%!-- Model-backed features --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-info/10 w-8 h-8 flex items-center justify-center text-info">
                <.icon name="hero-cpu-chip" class="size-4" />
              </span>
              <.card_title>Model-backed features</.card_title>
            </div>
            <ul class="mt-4 space-y-2 text-sm text-muted-foreground list-disc ml-5">
              <%= for item <- model_backed_capabilities(@provider_status) do %>
                <li>{item}</li>
              <% end %>
            </ul>
          </article>

          <%!-- Autonomy defaults --%>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-warning/10 w-8 h-8 flex items-center justify-center text-warning">
                <.icon name="hero-shield-exclamation" class="size-4" />
              </span>
              <.card_title>Autonomy defaults</.card_title>
            </div>
            <ul class="mt-4 space-y-2 text-sm text-muted-foreground list-disc ml-5">
              <%= for item <- autonomy_defaults() do %>
                <li>{item}</li>
              <% end %>
            </ul>
          </article>
        </div>
      </section>

      <%!-- Recent Sessions --%>
      <section class="space-y-3">
        <div class="flex items-center justify-between gap-3">
          <.section_title>Recent Sessions</.section_title>
          <a
            href={~p"/sessions"}
            class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition hover:text-primary"
          >
            View all <.icon name="hero-arrow-up-right" class="size-3" />
          </a>
        </div>

        <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
              <tr>
                <th class="px-5 py-3 font-semibold">Session</th>
                <th class="px-5 py-3 font-semibold">Risk</th>
                <th class="px-5 py-3 font-semibold">Workload</th>
                <th class="px-5 py-3 font-semibold">Findings</th>
                <th class="px-5 py-3 font-semibold">Budget</th>
                <th class="px-5 py-3 font-semibold"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= if @recent_sessions == [] do %>
                <tr>
                  <td colspan="6" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-foreground">No sessions yet.</p>
                    <p class="mt-1 text-sm text-muted-foreground">
                      Start a session to populate live governance telemetry.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for session <- @recent_sessions do %>
                  <tr class="transition hover:bg-muted/30">
                    <td class="max-w-sm px-5 py-4">
                      <a
                        href={~p"/sessions/#{session.id}"}
                        class="font-medium text-foreground transition hover:text-primary"
                      >
                        {session.title}
                      </a>
                      <p class="mt-1 line-clamp-1 text-xs text-muted-foreground">
                        {session.objective}
                      </p>
                      <p class="mt-2 text-xs text-muted-foreground">
                        {session.workspace && session.workspace.name}
                      </p>
                    </td>
                    <td class="px-5 py-4">
                      <span class={[
                        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                        session.risk_tier in ["critical", "high"] &&
                          "bg-destructive/10 text-destructive ring-destructive/20",
                        session.risk_tier in ["medium", "moderate"] &&
                          "bg-warning/10 text-warning ring-warning/20",
                        session.risk_tier in ["low"] &&
                          "bg-success/10 text-success ring-success/20",
                        session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-muted text-muted-foreground ring-border"
                      ]}>
                        {session.risk_tier}
                      </span>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                        {Enum.count(session.tasks)}
                      </div>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon
                          name="hero-exclamation-circle"
                          class="size-4 text-muted-foreground"
                        />
                        {Enum.count(session.findings)}
                      </div>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      ${session.budget_cents |> Kernel./(100) |> trunc()}
                    </td>
                    <td class="px-5 py-4 text-right">
                      <a
                        href={~p"/sessions/#{session.id}"}
                        aria-label={"Inspect #{session.title}"}
                        class="inline-flex items-center justify-center rounded-full border p-2 text-muted-foreground transition hover:border-primary/40 hover:bg-primary/10 hover:text-foreground"
                      >
                        <.icon name="hero-arrow-right" class="size-3" />
                      </a>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_percent(value), do: "#{value}%"

  defp format_number(nil), do: "Not recorded"
  defp format_number(value) when is_float(value), do: Float.round(value, 1)
  defp format_number(value), do: value

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

  defp provider_name(%{"selected_provider" => provider}) when provider in [nil, "heuristic"] do
    "No provider selected"
  end

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
    Enum.map_join(agents, ", ", fn agent ->
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
      "Findings, proof bundles, and session audit trail",
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

  defp blank?(value), do: String.trim(to_string(value || "")) == ""

  defp selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  defp selected_base_url(_status), do: "default"
end
