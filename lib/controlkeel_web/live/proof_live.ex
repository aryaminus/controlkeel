defmodule ControlKeelWeb.ProofLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case SessionScope.fetch_session(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session ->
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
            {:ok, assign_scope(socket, session, org_slug, ws_slug)}
        end
    end
  end

  defp assign_scope(socket, session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    socket
    |> assign(:page_title, "Proofs")
    |> assign(:proof, nil)
    |> assign(:memory_hits, [])
    |> assign(:session, session)
    |> assign(:org_slug, org_slug)
    |> assign(:ws_slug, ws_slug)
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
      %{label: "Proofs", to: nil}
    ])
  end

  defp scoped_session(socket), do: socket.assigns[:session]

  defp proof_not_found(socket) do
    socket
    |> assign(:page_title, "Proof not found")
    |> assign(:proof, nil)
    |> assign(:memory_hits, [])
  end

  @impl true
  def handle_params(%{"proof_id" => proof_id}, _uri, socket) do
    case scoped_session(socket) do
      nil ->
        {:noreply, socket}

      session ->
        session_id = session.id

        case parse_int(proof_id) do
          nil ->
            {:noreply, proof_not_found(socket)}

          parsed_id ->
            case Mission.get_proof_bundle_with_context(parsed_id) do
              %{session_id: ^session_id} = proof ->
                memory_hits = related_memory_hits(proof)
                workspace = session.workspace
                org = workspace && workspace.org

                {:noreply,
                 socket
                 |> assign(:page_title, "#{proof.task.title} — Proofs")
                 |> assign(:proof, proof)
                 |> assign(:memory_hits, memory_hits)
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
                   %{label: proof.task.title, to: nil}
                 ])}

              _ ->
                {:noreply, proof_not_found(socket)}
            end
        end
    end
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title
        :if={@proof}
        title={@proof.task.title}
        subtitle="Immutable evidence for this task version."
      />

      <.link
        :if={!@proof}
        navigate={~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@session.id}/proofs"}
        class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-3" /> Back to proofs
      </.link>

      <section :if={!@proof} class="rounded-2xl border bg-card p-5 shadow-card">
        <p class="text-base font-medium text-foreground">Proof not found</p>
        <p class="mt-1 text-sm text-muted-foreground">
          No proof bundle exists with this identifier.
        </p>
      </section>

      <div :if={@proof} class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Task</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@proof.task.title}</p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Version</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">v{@proof.version}</p>
          <p class="mt-1 text-xs text-muted-foreground">{@proof.status}</p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Risk score</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@proof.risk_score}</p>
          <p class="mt-3">
            <span class={[
              "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              risk_tier_pill_class(@proof.session.risk_tier)
            ]}>
              {@proof.session.risk_tier} risk
            </span>
          </p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Deploy ready</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {if @proof.deploy_ready, do: "Ready", else: "Not ready"}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@proof.bundle["validation_gate"] || "No validation gate recorded"}
          </p>
        </article>
      </div>

      <section :if={@proof} class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Snapshot</.section_title>
        <dl class="mt-4 grid gap-x-6 gap-y-4 sm:grid-cols-2">
          <div>
            <dt class="text-sm font-medium text-muted-foreground">Session</dt>
            <dd class="mt-1 text-sm text-foreground">{@proof.session.title}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-muted-foreground">Generated</dt>
            <dd class="mt-1 text-sm text-foreground">
              {format_datetime(@proof.generated_at, "Not recorded")}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-muted-foreground">Open findings</dt>
            <dd class="mt-1 text-sm text-foreground">{@proof.open_findings_count}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-muted-foreground">Blocked findings</dt>
            <dd class="mt-1 text-sm text-foreground">{@proof.blocked_findings_count}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-muted-foreground">Domain pack</dt>
            <dd class="mt-1 text-sm text-foreground">
              {format_domain_pack(get_in(@proof.session.execution_brief || %{}, ["domain_pack"]))}
            </dd>
          </div>
        </dl>
      </section>

      <section :if={@proof} class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Compliance attestations</.section_title>
        <%= if List.wrap(@proof.bundle["compliance_attestations"]) == [] do %>
          <p class="mt-3 text-sm text-muted-foreground">No attestations recorded.</p>
        <% else %>
          <ul class="mt-2 divide-y divide-border">
            <%= for attestation <- List.wrap(@proof.bundle["compliance_attestations"]) do %>
              <li class="flex items-center justify-between gap-3 py-2.5">
                <span class="text-sm text-foreground">
                  {format_domain_pack(attestation["pack"])}
                </span>
                <span class="text-sm text-muted-foreground">
                  {attestation["status"]} · {attestation["blocked_count"]} blocked
                </span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>

      <section :if={@proof} class="rounded-2xl border bg-card p-5 shadow-card">
        <.section_title>Rollback instructions</.section_title>
        <pre class="mt-4 rounded-xl border bg-muted/50 p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words">{@proof.bundle["rollback_instructions"]}</pre>
      </section>

      <div :if={@proof} class="grid gap-4 lg:grid-cols-2">
        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Related memory</.section_title>
          <%= if @memory_hits == [] do %>
            <p class="mt-3 text-sm text-muted-foreground">
              No related memory hits for this task yet.
            </p>
          <% else %>
            <ul class="mt-3 space-y-3">
              <%= for hit <- @memory_hits do %>
                <li>
                  <p class="text-sm font-medium text-foreground">{hit.title}</p>
                  <p class="mt-0.5 text-sm text-muted-foreground">{hit.summary}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <.section_title>Finding resolution</.section_title>
          <dl class="mt-4 grid grid-cols-2 gap-4">
            <div>
              <dt class="text-sm font-medium text-muted-foreground">Approved</dt>
              <dd class="mt-1 text-xl font-semibold text-foreground/90 tabular-nums">
                {get_in(@proof.bundle, ["finding_resolution_summary", "approved"]) || 0}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-muted-foreground">Resolved</dt>
              <dd class="mt-1 text-xl font-semibold text-foreground/90 tabular-nums">
                {get_in(@proof.bundle, ["finding_resolution_summary", "resolved"]) || 0}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-muted-foreground">Open</dt>
              <dd class="mt-1 text-xl font-semibold text-foreground/90 tabular-nums">
                {get_in(@proof.bundle, ["finding_resolution_summary", "open"]) || 0}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-muted-foreground">Blocked</dt>
              <dd class="mt-1 text-xl font-semibold text-foreground/90 tabular-nums">
                {get_in(@proof.bundle, ["finding_resolution_summary", "blocked"]) || 0}
              </dd>
            </div>
          </dl>
        </section>
      </div>

      <div :if={@proof} class="grid gap-4 sm:grid-cols-2">
        <% ver_status = bundle_get(@proof, ["verification_assessment", "status"]) %>
        <% ver_score = bundle_get(@proof, ["verification_assessment", "score"]) %>
        <% ver_evidence = bundle_get(@proof, ["verification_assessment", "evidence"], %{}) %>
        <% task_checks = bundle_get(@proof, ["task_checks"], %{}) %>
        <% ctx = bundle_get(@proof, ["runtime_context_integrity"], %{}) %>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center gap-2">
            <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
              <.icon name="hero-check-badge" class="size-4" />
            </span>
            <.card_title>Surface verification</.card_title>
            <span
              :if={ver_status}
              class={[
                "ml-auto inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                verification_status_color(ver_status)
              ]}
            >
              {ver_status}
            </span>
          </div>
          <div class="mt-4 flex items-baseline gap-2">
            <span class={[
              "text-xl font-semibold text-foreground/90 tabular-nums",
              verification_score_color(ver_score)
            ]}>
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
          <div class="mt-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
            <p class="text-muted-foreground">Passed checks</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {ver_evidence["passed_checks"] || 0}
            </p>
            <p class="text-muted-foreground">Task checks (strong)</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {ver_evidence["passed_task_checks"] || 0} / {ver_evidence[
                "passed_strong_task_checks"
              ] || 0}
            </p>
            <p class="text-muted-foreground">Failed checks</p>
            <p class="text-right font-medium tabular-nums text-destructive">
              {ver_evidence["failed_task_checks"] || 0}
            </p>
            <p class="text-muted-foreground">External regressions</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {ver_evidence["external_regressions"] || 0}
            </p>
          </div>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center gap-2">
            <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
              <.icon name="hero-list-bullet" class="size-4" />
            </span>
            <.card_title>Task check counts</.card_title>
          </div>
          <% ch_total = task_checks["total"] || 0 %>
          <% ch_passed = task_checks["passed"] || 0 %>
          <% ch_failed = task_checks["failed"] || 0 %>
          <% ch_warn = task_checks["warn"] || 0 %>
          <div class="mt-4 flex items-baseline gap-2">
            <span class="text-xl font-semibold text-foreground/90 tabular-nums">{ch_total}</span>
            <span class="text-sm text-muted-foreground">total</span>
            <span class="ml-auto flex gap-3 text-sm tabular-nums">
              <span class="text-primary">{ch_passed} passed</span>
              <span class="text-destructive">{ch_failed} failed</span>
              <span class="text-warning">{ch_warn} warn</span>
            </span>
          </div>
          <% passed_pct = if ch_total > 0, do: round(ch_passed / ch_total * 100), else: 0 %>
          <% failed_pct = if ch_total > 0, do: round(ch_failed / ch_total * 100), else: 0 %>
          <div class="mt-3 h-2 overflow-hidden rounded-full bg-muted">
            <div class="flex h-full">
              <div style={"width: #{passed_pct}%"} class="bg-primary transition-all"></div>
              <div style={"width: #{failed_pct}%"} class="bg-destructive transition-all"></div>
            </div>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
            <p class="text-muted-foreground">Passed strong</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {task_checks["passed_strong"] || 0}
            </p>
            <p class="text-muted-foreground">Strongest proof</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {task_checks["strongest_proof_strength"] || "—"}
            </p>
            <p class="text-muted-foreground">Hashed outputs</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {task_checks["hashed_outputs"] || 0}
            </p>
            <p class="text-muted-foreground">Git refs</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {length(task_checks["git_shas"] || [])}
            </p>
          </div>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center gap-2">
            <span class={[
              "rounded-full w-8 h-8 flex items-center justify-center",
              ctx["status"] == "clean" && "bg-success/10 text-success",
              ctx["status"] != "clean" && "bg-destructive/10 text-destructive"
            ]}>
              <.icon
                name={
                  if ctx["status"] == "clean",
                    do: "hero-check-circle",
                    else: "hero-exclamation-triangle"
                }
                class="size-4"
              />
            </span>
            <.card_title>Context integrity</.card_title>
            <span class={[
              "ml-auto inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              context_status_color(ctx["status"])
            ]}>
              {ctx["status"] || "Unknown"}
            </span>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
            <p class="text-muted-foreground">Partial reads</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {ctx["partial_read_count"] || 0}
            </p>
            <p class="text-muted-foreground">Compactions</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {ctx["compaction_count"] || 0}
            </p>
            <p :if={ctx["compaction_source"]} class="text-muted-foreground">Compaction source</p>
            <p
              :if={ctx["compaction_source"]}
              class="text-right font-medium tabular-nums text-foreground"
            >
              {ctx["compaction_source"]}
            </p>
          </div>
          <div :if={ctx["latest_compaction_reason"]} class="mt-3 rounded-xl bg-muted/50 p-3">
            <p class="text-xs text-muted-foreground">Latest compaction</p>
            <p class="mt-1 text-sm text-muted-foreground">{ctx["latest_compaction_reason"]}</p>
          </div>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="flex items-center gap-2">
            <span class={[
              "rounded-full w-8 h-8 flex items-center justify-center",
              @proof.deploy_ready && "bg-success/10 text-success",
              !@proof.deploy_ready && "bg-warning/10 text-warning"
            ]}>
              <.icon
                name={if @proof.deploy_ready, do: "hero-check-circle", else: "hero-x-circle"}
                class="size-4"
              />
            </span>
            <.card_title>Deploy readiness</.card_title>
            <span class={[
              "ml-auto inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              deploy_badge_class(@proof.deploy_ready)
            ]}>
              {if @proof.deploy_ready, do: "Ready", else: "Not ready"}
            </span>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
            <p class="text-muted-foreground">Validation gate</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {@proof.bundle["validation_gate"] || "—"}
            </p>
            <p class="text-muted-foreground">Open findings</p>
            <p class="text-right font-medium tabular-nums text-warning">
              {@proof.open_findings_count}
            </p>
            <p class="text-muted-foreground">Blocked findings</p>
            <p class="text-right font-medium tabular-nums text-destructive">
              {@proof.blocked_findings_count}
            </p>
            <p class="text-muted-foreground">Compliance packs</p>
            <p class="text-right font-medium tabular-nums text-foreground">
              {length(List.wrap(@proof.bundle["compliance_attestations"]))}
            </p>
          </div>
          <p :if={gate = bundle_get(@proof, ["security_workflow", "release_gate_decision"])} class="mt-3">
            <span class={[
              "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              gate == "ready" && "bg-success/10 text-success ring-success/20",
              gate == "blocked" && "bg-destructive/10 text-destructive ring-destructive/20"
            ]}>
              Release gate: {gate}
            </span>
          </p>
        </article>
      </div>

      <details :if={@proof} class="rounded-2xl border bg-card p-5 shadow-card group">
        <summary class="flex cursor-pointer items-center gap-2 text-sm font-medium text-muted-foreground transition hover:text-primary">
          <.icon
            name="hero-chevron-right"
            class="size-4 transition-transform group-open:rotate-90"
          /> Raw proof payload
        </summary>
        <pre class="mt-4 max-h-96 overflow-auto rounded-xl border bg-muted/50 p-4 font-mono text-xs leading-relaxed whitespace-pre-wrap break-words">{Jason.encode!(@proof.bundle, pretty: true)}</pre>
      </details>
    </div>
    """
  end

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

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(pack) when pack in ["baseline", "cost"], do: String.capitalize(pack)
  defp format_domain_pack(pack), do: Intent.pack_label(pack)

  defp bundle_get(proof, keys, default \\ nil) do
    if proof, do: get_in(proof.bundle || %{}, keys) || default, else: default
  end

  defp verification_score_color(score) when is_integer(score) do
    cond do
      score >= 80 -> "text-primary"
      score >= 50 -> "text-warning"
      true -> "text-destructive"
    end
  end

  defp verification_score_color(_), do: "text-muted-foreground"

  defp verification_status_color("strong"), do: "bg-primary/10 text-primary ring-primary/20"

  defp verification_status_color("moderate"),
    do: "bg-warning/10 text-warning ring-warning/20"

  defp verification_status_color("weak"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp verification_status_color(_), do: "bg-muted text-muted-foreground ring-border"

  defp context_status_color("clean"), do: "bg-success/10 text-success ring-success/20"

  defp context_status_color("degraded"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp context_status_color(_), do: "bg-muted text-muted-foreground ring-border"

  defp deploy_badge_class(true), do: "bg-success/10 text-success ring-success/20"

  defp deploy_badge_class(_),
    do: "bg-warning/10 text-warning ring-warning/20"

  defp risk_tier_pill_class("low"), do: "bg-success/10 text-success ring-success/20"

  defp risk_tier_pill_class("moderate"), do: "bg-warning/10 text-warning ring-warning/20"

  defp risk_tier_pill_class(tier) when tier in ["high", "critical"],
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp risk_tier_pill_class(_), do: "bg-muted text-muted-foreground ring-border"
end
