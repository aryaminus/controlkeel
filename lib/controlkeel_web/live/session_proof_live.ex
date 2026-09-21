defmodule ControlKeelWeb.SessionProofLive do
  @moduledoc """
  Session-scoped proof detail behind the organization layout at
  `/:org_slug/workspaces/:ws_slug/sessions/:id/proofs/:proof_id`.

  Renders the immutable snapshot per the UI style guide (stat cards, panels,
  tone tokens); this module owns the session authorization, slug agreement,
  proof-ownership check, and session nav assigns.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission

  @impl true
  def mount(
        %{
          "id" => session_id,
          "proof_id" => proof_id,
          "org_slug" => org_slug,
          "ws_slug" => ws_slug
        },
        _session,
        socket
      ) do
    current_user = socket.assigns[:current_user]

    with {:ok, parsed_session_id} <- parse_id(session_id),
         {:ok, parsed_proof_id} <- parse_id(proof_id),
         %{} = session <- Mission.get_session_context(parsed_session_id),
         true <- ControlKeel.Accounts.session_accessible?(session, current_user),
         :ok <- check_session_scope(session, org_slug, ws_slug),
         %{} = proof <- Mission.get_proof_bundle_with_context(parsed_proof_id),
         true <- proof.session_id == session.id do
      {:ok, assign_session(socket, session, proof)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  defp assign_session(socket, session, proof) do
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
      %{
        label: "Proofs",
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}/proofs"
      },
      %{label: "Proof #{proof.id}", to: nil}
    ])
    |> assign(:page_title, proof.task.title)
    |> assign(:session, session)
    |> assign(:proof, proof)
    |> assign(:memory_hits, related_memory_hits(proof))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title title={@proof.task.title} />

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Version</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">v{@proof.version}</p>
          <p class="mt-1 text-xs text-muted-foreground">
            {format_datetime(@proof.generated_at, "Not recorded")}
          </p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Risk score</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@proof.risk_score}</p>
          <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class={["h-full rounded-full", risk_bar_tone(@proof.risk_score)]}
              style={"width: #{risk_bar_width(@proof.risk_score)}%"}
            />
          </div>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Deploy ready</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {if @proof.deploy_ready, do: "Yes", else: "No"}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {if @proof.deploy_ready, do: "certified ready", else: "review required"}
          </p>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <div class="flex items-center justify-between gap-3">
          <.section_title>Snapshot</.section_title>
          <span
            :if={gate = bundle_get(@proof, ["security_workflow", "release_gate_decision"])}
            class={[
              "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1",
              gate == "ready" && "bg-primary/10 text-primary ring-primary/20",
              gate == "blocked" && "bg-destructive/10 text-destructive ring-destructive/20"
            ]}
          >
            Release gate: {gate}
          </span>
        </div>
        <div class="mt-4 grid grid-cols-2 gap-x-6 gap-y-3 text-sm sm:grid-cols-3">
          <div>
            <p class="text-xs font-medium text-muted-foreground">Session</p>
            <p class="mt-1 text-foreground">{@proof.session.title}</p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Open findings</p>
            <p class="mt-1 text-foreground">{@proof.open_findings_count}</p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Blocked findings</p>
            <p class="mt-1 text-foreground">{@proof.blocked_findings_count}</p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Domain pack</p>
            <p class="mt-1 text-foreground">
              {format_domain_pack(get_in(@proof.session.execution_brief || %{}, ["domain_pack"]))}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Validation gate</p>
            <p class="mt-1 text-foreground">{@proof.bundle["validation_gate"] || "—"}</p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Compliance packs</p>
            <p class="mt-1 text-foreground">
              {length(List.wrap(@proof.bundle["compliance_attestations"]))}
            </p>
          </div>
        </div>
        <div class="mt-5 border-t pt-4">
          <p class="text-xs font-medium text-muted-foreground">Compliance attestations</p>
          <ul class="mt-2 grid gap-2 list-none p-0 m-0 text-sm">
            <%= for attestation <- List.wrap(@proof.bundle["compliance_attestations"]) do %>
              <li>
                {format_domain_pack(attestation["pack"])}: {attestation["status"]} ({attestation[
                  "blocked_count"
                ]} blocked)
              </li>
            <% end %>
          </ul>
        </div>
        <div class="mt-5 border-t pt-4">
          <p class="text-xs font-medium text-muted-foreground">Rollback instructions</p>
          <pre class="m-0 mt-2 rounded-xl border bg-muted/[0.03] p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words">{@proof.bundle["rollback_instructions"]}</pre>
        </div>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Assessment summary</.section_title>
        <div class="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div class="rounded-xl bg-muted/[0.03] p-5">
            <div class="flex items-center justify-between mb-4">
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Surface verification
              </p>
              <% ver_status = bundle_get(@proof, ["verification_assessment", "status"]) %>
              <span
                :if={ver_status}
                class={[
                  "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                  verification_status_tone(ver_status)
                ]}
              >
                {ver_status}
              </span>
            </div>
            <div class="flex items-baseline gap-2 mb-4">
              <% ver_score = bundle_get(@proof, ["verification_assessment", "score"]) %>
              <span class={["text-3xl font-bold tabular-nums", verification_score_tone(ver_score)]}>
                {ver_score || "—"}
              </span>
              <span :if={ver_score} class="text-sm text-muted-foreground">/ 100</span>
              <span
                :if={bundle_get(@proof, ["verification_assessment", "verification_ready"]) == true}
                class="ml-auto inline-flex items-center gap-1 rounded-full bg-primary/10 px-2.5 py-1 text-xs font-semibold text-primary ring-1 ring-primary/20"
              >
                <.icon name="hero-check-circle" class="size-3.5" /> Ready
              </span>
            </div>
            <% ver_evidence = bundle_get(@proof, ["verification_assessment", "evidence"], %{}) %>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
              <span class="text-muted-foreground">Passed checks</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {ver_evidence["passed_checks"] || 0}
              </span>
              <span class="text-muted-foreground">Task checks (strong)</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {ver_evidence["passed_task_checks"] || 0} / {ver_evidence[
                  "passed_strong_task_checks"
                ] || 0}
              </span>
              <span class="text-muted-foreground">Failed checks</span>
              <span class="text-right font-medium tabular-nums text-destructive">
                {ver_evidence["failed_task_checks"] || 0}
              </span>
              <span class="text-muted-foreground">External regressions</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {ver_evidence["external_regressions"] || 0}
              </span>
            </div>
          </div>

          <div class="rounded-xl bg-muted/[0.03] p-5">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-4">
              Task check counts
            </p>
            <% task_checks = bundle_get(@proof, ["task_checks"], %{}) %>
            <% ch_total = task_checks["total"] || 0 %>
            <% ch_passed = task_checks["passed"] || 0 %>
            <% ch_failed = task_checks["failed"] || 0 %>
            <% ch_warn = task_checks["warn"] || 0 %>
            <div class="flex items-baseline gap-2 mb-4">
              <span class="text-3xl font-bold tabular-nums text-foreground">{ch_total}</span>
              <span class="text-sm text-muted-foreground">total</span>
              <span class="ml-auto flex gap-3 text-sm tabular-nums">
                <span class="text-primary">{ch_passed} passed</span>
                <span class="text-destructive">{ch_failed} failed</span>
                <span class="text-warning">{ch_warn} warn</span>
              </span>
            </div>
            <% passed_pct = if ch_total > 0, do: round(ch_passed / ch_total * 100), else: 0 %>
            <% failed_pct = if ch_total > 0, do: round(ch_failed / ch_total * 100), else: 0 %>
            <div class="h-2 rounded-full bg-muted overflow-hidden mb-4">
              <div class="h-full flex">
                <div style={"width: #{passed_pct}%"} class="bg-primary transition-all rounded-l-full">
                </div>
                <div style={"width: #{failed_pct}%"} class="bg-destructive transition-all"></div>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
              <span class="text-muted-foreground">Passed strong</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {task_checks["passed_strong"] || 0}
              </span>
              <span class="text-muted-foreground">Strongest proof</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {task_checks["strongest_proof_strength"] || "—"}
              </span>
              <span class="text-muted-foreground">Hashed outputs</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {task_checks["hashed_outputs"] || 0}
              </span>
              <span class="text-muted-foreground">Git refs</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {length(task_checks["git_shas"] || [])}
              </span>
            </div>
          </div>

          <div class="rounded-xl bg-muted/[0.03] p-5">
            <div class="flex items-center justify-between mb-4">
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Context integrity
              </p>
              <% ctx = bundle_get(@proof, ["runtime_context_integrity"], %{}) %>
              <span class={[
                "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                context_status_tone(ctx["status"])
              ]}>
                <.icon
                  name={
                    if ctx["status"] == "clean",
                      do: "hero-check-circle",
                      else: "hero-exclamation-triangle"
                  }
                  class="size-3.5"
                />
                {ctx["status"] || "Unknown"}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
              <span class="text-muted-foreground">Partial reads</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {ctx["partial_read_count"] || 0}
              </span>
              <span class="text-muted-foreground">Compactions</span>
              <span class="text-right font-medium tabular-nums text-foreground">
                {ctx["compaction_count"] || 0}
              </span>
              <span :if={ctx["compaction_source"]} class="text-muted-foreground">
                Compaction source
              </span>
              <span
                :if={ctx["compaction_source"]}
                class="text-right font-medium tabular-nums text-foreground"
              >
                {ctx["compaction_source"]}
              </span>
            </div>
            <div :if={ctx["latest_compaction_reason"]} class="mt-3 rounded-lg bg-muted p-3">
              <p class="text-xs text-muted-foreground mb-1">Latest compaction</p>
              <p class="text-sm text-muted-foreground">{ctx["latest_compaction_reason"]}</p>
            </div>
          </div>

          <div class="rounded-xl bg-muted/[0.03] p-5">
            <div class="flex items-center justify-between mb-4">
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Deploy readiness
              </p>
              <span class={[
                "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold ring-1",
                deploy_badge_tone(@proof.deploy_ready)
              ]}>
                <.icon
                  name={if @proof.deploy_ready, do: "hero-check-circle", else: "hero-x-circle"}
                  class="size-3.5"
                />
                {if @proof.deploy_ready, do: "Ready", else: "Not ready"}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
              <span class="text-muted-foreground">Open findings</span>
              <span class="text-right font-medium tabular-nums text-warning">
                {@proof.open_findings_count}
              </span>
              <span class="text-muted-foreground">Blocked findings</span>
              <span class="text-right font-medium tabular-nums text-destructive">
                {@proof.blocked_findings_count}
              </span>
              <span class="text-muted-foreground">Approved findings</span>
              <span class="text-right font-medium tabular-nums text-success">
                {@proof.approved_findings_count}
              </span>
            </div>
          </div>
        </div>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Related memory</.section_title>
        <%= if @memory_hits == [] do %>
          <p class="mt-3 text-sm text-muted-foreground">
            No related memory hits for this task yet.
          </p>
        <% else %>
          <ul class="mt-3 divide-y divide-border list-none p-0 m-0">
            <%= for hit <- @memory_hits do %>
              <li class="py-3 first:pt-0 last:pb-0">
                <strong class="text-sm text-foreground">{hit.title}</strong>
                <p class="mt-1 text-sm text-muted-foreground">{hit.summary}</p>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Finding resolution</.section_title>
        <div class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <p class="text-xs font-medium text-muted-foreground">Approved</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {get_in(@proof.bundle, ["finding_resolution_summary", "approved"]) || 0}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Resolved</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {get_in(@proof.bundle, ["finding_resolution_summary", "resolved"]) || 0}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Open</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {get_in(@proof.bundle, ["finding_resolution_summary", "open"]) || 0}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-muted-foreground">Blocked</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {get_in(@proof.bundle, ["finding_resolution_summary", "blocked"]) || 0}
            </p>
          </div>
        </div>
      </section>

      <details class="group rounded-2xl border bg-card p-5 shadow-card">
        <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-primary cursor-pointer hover:text-primary transition-colors list-none flex items-center gap-2">
          <.icon
            name="hero-chevron-right"
            class="size-3.5 group-open:rotate-90 transition-transform"
          /> Raw proof payload
        </summary>
        <pre class="m-0 mt-3 rounded-xl border bg-muted/[0.03] p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap break-words overflow-auto max-h-96">{Jason.encode!(@proof.bundle, pretty: true)}</pre>
      </details>
    </div>
    """
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_id(_), do: :error

  defp bundle_get(proof, keys, default \\ nil) do
    if proof, do: get_in(proof.bundle || %{}, keys) || default, else: default
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(pack) when pack in ["baseline", "cost"], do: String.capitalize(pack)
  defp format_domain_pack(pack), do: Intent.pack_label(pack)

  defp verification_score_tone(score) when is_integer(score) do
    cond do
      score >= 80 -> "text-primary"
      score >= 50 -> "text-warning"
      true -> "text-destructive"
    end
  end

  defp verification_score_tone(_), do: "text-muted-foreground"

  defp verification_status_tone("strong"),
    do: "bg-primary/10 text-primary ring-primary/20"

  defp verification_status_tone("moderate"),
    do: "bg-warning/10 text-warning ring-warning/20"

  defp verification_status_tone("weak"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp verification_status_tone(_),
    do: "bg-muted text-muted-foreground ring-border"

  defp context_status_tone("clean"), do: "bg-primary/10 text-primary ring-primary/20"

  defp context_status_tone("degraded"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp context_status_tone(_), do: "bg-muted text-muted-foreground ring-border"

  defp deploy_badge_tone(true), do: "bg-primary/10 text-primary ring-primary/20"
  defp deploy_badge_tone(_), do: "bg-warning/10 text-warning ring-warning/20"

  defp risk_bar_tone(score) when is_float(score) do
    cond do
      score <= 0.3 -> "bg-primary"
      score <= 0.6 -> "bg-warning"
      true -> "bg-destructive"
    end
  end

  defp risk_bar_tone(_), do: "bg-muted-foreground"

  defp risk_bar_width(nil), do: 0
  defp risk_bar_width(score) when is_float(score), do: min(round(score * 100), 100)
  defp risk_bar_width(_), do: 0

  defp related_memory_hits(proof) do
    related = Memory.list_related_to_task(proof.task_id, 5)

    if related != [] do
      related
    else
      Memory.search(proof.task.title,
        session_id: proof.session_id,
        task_id: proof.task_id,
        top_k: 5
      ).entries
    end
  end
end
