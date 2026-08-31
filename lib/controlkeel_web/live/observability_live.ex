defmodule ControlKeelWeb.ObservabilityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
  alias ControlKeel.Platform
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]
    socket = socket |> assign(:session_id, nil) |> assign(:session_title, nil)

    case Observability.session_run(id) do
      {:ok, run} ->
        if Accounts.session_accessible?(run.session, org_id) do
          {:ok,
           socket
           |> assign(:page_title, "Observability — #{run.session.title}")
           |> assign(:run, run)
           |> assign(:session_id, run.session.id)
           |> assign(:session_title, run.session.title)
           |> assign(:audit_exports, Platform.list_audit_exports(run.session.id))}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session observability not found.")
           |> push_navigate(to: ~p"/")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Session observability not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-run-page"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 class="text-xl font-semibold text-primary">{@run.session.objective}</h1>
          <p class="text-muted-foreground text-sm mt-1">
            Run health and governed activity for this session.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span class={obs_health_pill_class(@run.health.status)}>{@run.health.status}</span>
          <span class={neutral_pill_class()}>session ##{@run.session.id}</span>
        </div>
      </div>

      <CommandPill.command_pill command={"controlkeel obs run #{@run.session.id}"} />

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div
          id="observability-health-card"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-2"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Health</p>
          <p class="text-2xl font-semibold">{@run.health.label}</p>
          <ul class="list-disc pl-5">
            <%= for reason <- @run.health.reasons do %>
              <li class="text-muted-foreground text-xs leading-relaxed">{reason}</li>
            <% end %>
          </ul>
        </div>

        <div
          id="observability-costs"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Budget</p>
          <p class="text-2xl font-semibold">
            {@run.budget["decision"] || "unknown"}
          </p>
          <p class="text-muted-foreground text-xs">
            {format_currency(@run.budget["spent_cents"] || 0)} / {format_currency(
              @run.budget["session_budget_cents"] || 0
            )} used
          </p>
          <p class="text-muted-foreground text-xs">
            Rolling 24h: {format_currency(@run.budget["rolling_24h_spend_cents"] || 0)} / {format_currency(
              @run.budget["daily_budget_cents"] || 0
            )}
          </p>
        </div>

        <div
          id="observability-findings"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Findings
          </p>
          <p class="text-2xl font-semibold">
            {@run.findings.active} active / {@run.findings.total} total
          </p>
          <p class="text-muted-foreground text-xs">
            {@run.findings.critical} critical · {@run.findings.high} high · {@run.findings.blocked} blocked
          </p>
          <.link
            navigate={~p"/findings"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Open findings →
          </.link>
        </div>

        <div
          id="observability-gates"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Gates</p>
          <p class="text-2xl font-semibold">
            {@run.gates.pending_reviews} pending
          </p>
          <p class="text-muted-foreground text-xs">
            {@run.gates.total_reviews} total review gates
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          id="observability-timeline"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-3"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Timeline
          </p>
          <%= if @run.timeline.recent == [] do %>
            <p class="text-muted-foreground text-sm">No timeline events recorded yet.</p>
          <% else %>
            <div class="space-y-2 max-h-80 overflow-y-auto pr-1">
              <%= for event <- @run.timeline.recent do %>
                <div class="rounded-lg px-3 py-2 border bg-[rgba(255,255,255,0.02)]">
                  <div class="flex items-start justify-between gap-3">
                    <p class="text-sm font-medium">
                      {event.event_type || "event"}
                    </p>
                    <time class="text-[10px] font-mono text-muted-foreground whitespace-nowrap shrink-0">
                      {format_datetime(event.inserted_at)}
                    </time>
                  </div>
                  <p class="text-muted-foreground text-xs mt-1">
                    {event.summary || "No summary"} · {event.actor || "unknown"}
                  </p>
                </div>
              <% end %>
            </div>
          <% end %>
          <.link
            navigate={~p"/observability/sessions/#{@run.session.id}/timeline"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Open full timeline →
          </.link>
        </div>

        <div class="space-y-4">
          <div
            id="observability-tools"
            class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-3"
          >
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Hosts, models, and tools
            </p>
            <div class="grid grid-cols-2 gap-3">
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Invocations
                </p>
                <p class="text-base font-semibold">
                  {@run.hosts_models_tools.invocations}
                </p>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Estimated cost
                </p>
                <p class="text-base font-semibold">
                  {format_currency(@run.hosts_models_tools.estimated_cost_cents)}
                </p>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Sources
                </p>
                <p class=" text-xs">
                  {format_frequency(@run.hosts_models_tools.by_source)}
                </p>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Models
                </p>
                <p class=" text-xs">
                  {format_frequency(@run.hosts_models_tools.by_model)}
                </p>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Tools
                </p>
                <p class=" text-xs">
                  {format_frequency(@run.hosts_models_tools.by_tool)}
                </p>
              </div>
            </div>
          </div>

          <div
            id="observability-memory-proof"
            class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-3"
          >
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Context, memory, and proof
            </p>
            <div class="grid grid-cols-3 gap-3">
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Memory
                </p>
                <p class="text-base font-semibold">{@run.memory.records}</p>
                <.link
                  navigate={~p"/observability/sessions/#{@run.session.id}/memory"}
                  class="text-xs text-primary font-semibold hover:opacity-80 transition-opacity"
                >
                  Open →
                </.link>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Proofs
                </p>
                <p class="text-base font-semibold">{@run.proofs.count}</p>
                <.link
                  navigate={~p"/proofs"}
                  class="text-xs text-primary font-semibold hover:opacity-80 transition-opacity"
                >
                  Open →
                </.link>
              </div>
              <div class="space-y-1">
                <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                  Tasks
                </p>
                <p class="text-base font-semibold">
                  {@run.tasks.active}/{@run.tasks.total}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%= if @run.recommendations != [] do %>
        <div id="observability-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @run.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div
        id="observability-telemetry-export"
        class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-2"
      >
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Trace/proof export
        </p>
        <p class="text-muted-foreground text-sm leading-relaxed">
          Download the local observability envelope for this run, then preview it locally with <code class="text-primary font-semibold ml-2 text-xs">
              controlkeel obs import &lt;file&gt; --dry-run
            </code>.
        </p>
        <.link
          href={~p"/observability/sessions/#{@run.session.id}/export.json"}
          class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
        >
          Download JSON envelope →
        </.link>
      </div>

      <div
        id="observability-audit-log-export"
        class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-2"
      >
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Audit log export
        </p>
        <p class="text-muted-foreground text-sm leading-relaxed">
          Checksummed audit artifact of record for this session, proofs embedded. The same export
          behind <code class="text-primary font-semibold ml-1 text-xs">controlkeel audit-log</code>.
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <.link
            :for={format <- ~w(json csv pdf)}
            id={"observability-audit-export-#{format}"}
            href={~p"/observability/sessions/#{@run.session.id}/audit-log/#{format}"}
            class="rounded-lg px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.14em] border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            {String.upcase(format)}
          </.link>
        </div>
        <%= if @audit_exports == [] do %>
          <p class="text-muted-foreground text-xs">
            No audit exports recorded yet — download one above and its checksum appears here.
          </p>
        <% else %>
          <ul class="space-y-1 list-none p-0 m-0">
            <%= for export <- @audit_exports do %>
              <li class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span class="font-semibold uppercase">{export.format}</span>
                <code class="font-mono break-all">{export.checksum}</code>
                <span>{format_exported_at(export.generated_at)}</span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recent findings
          </p>
          <%= if @run.findings.recent == [] do %>
            <p class="text-muted-foreground text-sm">No findings recorded yet.</p>
          <% else %>
            <div class="space-y-2">
              <%= for finding <- @run.findings.recent do %>
                <div class="rounded-lg px-3 py-2 border bg-[rgba(255,255,255,0.02)]">
                  <p class="text-sm font-medium">{finding.title}</p>
                  <p class="text-muted-foreground text-xs">
                    {finding.severity} / {finding.status} · {finding.rule_id}
                  </p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recent review gates
          </p>
          <%= if @run.gates.latest == [] do %>
            <p class="text-muted-foreground text-sm">No review gates recorded yet.</p>
          <% else %>
            <div class="space-y-2">
              <%= for review <- @run.gates.latest do %>
                <div class="rounded-lg px-3 py-2 border bg-[rgba(255,255,255,0.02)]">
                  <.link
                    navigate={~p"/sessions/#{review.session_id}/reviews/#{review.id}"}
                    class="text-sm font-medium text-primary hover:opacity-80 transition-opacity"
                  >
                    {review.title}
                  </.link>
                  <p class="text-muted-foreground text-xs">
                    {review.review_type} / {review.status}
                  </p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp obs_health_pill_class("red"),
    do:
      "inline-flex items-center border rounded-full px-3 py-1.5 text-sm bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp obs_health_pill_class("yellow"),
    do:
      "inline-flex items-center border rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp obs_health_pill_class(_status),
    do:
      "inline-flex items-center border rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp format_currency(cents) when is_integer(cents), do: (cents / 100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp format_exported_at(nil), do: "unknown time"

  defp format_exported_at(%DateTime{} = at),
    do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
