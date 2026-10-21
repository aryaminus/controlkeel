defmodule ControlKeelWeb.CloudTelemetryLive do
  @moduledoc """
  Mission Control LiveView for cloud telemetry ingestion health.

  Shows install-to-first-finding funnel, queue depth (outbound), received
  events (inbound), and recent activity. Read-only — no actions on this view.

  Phase 2 acceptance gate: "Dashboard renders install-to-first-finding funnel
  for a seeded workspace."
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Budget
  alias ControlKeel.Platform
  alias ControlKeel.ProviderBroker.Config, as: ProviderConfig
  alias ControlKeel.Cloud.BaselineAnalyzer
  alias ControlKeel.Cloud.Guardrails
  alias ControlKeel.Cloud.Workspace.Baseline
  alias ControlKeel.Cloud.Telemetry.Ingestion
  alias ControlKeel.Cloud.Mcp.AuditLog
  alias ControlKeel.Cloud.Mcp.Registry
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.Telemetry.Sender
  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Queue
  alias ControlKeel.Cloud.Workspace.Identity

  @refresh_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    # Admin-only: operator dashboard shows cross-tenant data.
    # Require an active org membership with admin role.
    #
    # TODO(#287 follow-up 2): the gate below is "admin of the visitor's default
    # org", not an explicit platform-operator boundary, while the page renders
    # cross-tenant data. Decide the operator boundary or scope the page before
    # this surface can be considered safe for multi-tenant deployments.
    membership = resolve_membership(socket, session)

    socket =
      socket
      |> assign(:page_title, "Cloud telemetry")
      |> assign(:current_membership, membership)

    if admin?(membership) do
      if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

      {:ok, assign_view_state(socket)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Admin access required.")
       |> redirect(to: "/")}
    end
  end

  defp admin?(%ControlKeel.Accounts.Membership{status: "active", role: role}),
    do: ControlKeel.Accounts.role_at_least?(role, "admin")

  defp admin?(_), do: false

  defp resolve_membership(socket, session) do
    user =
      socket.assigns[:current_user] ||
        case Map.get(session, "current_user_id") || Map.get(session, :current_user_id) do
          user_id when is_integer(user_id) -> Accounts.get_user(user_id)
          _ -> nil
        end

    # Legacy global page: it has no org in the URL, so it resolves the
    # visitor's default org once at mount. Org-scoped pages resolve from
    # their `:org_slug` instead and never consult this.
    org_id = if user, do: Accounts.default_org_for_user(user.id)

    if user && is_integer(org_id), do: Accounts.get_active_membership(user.id, org_id)
  end

  @impl true
  def handle_info(:refresh, socket) do
    # Re-check the admin gate on every tick: LiveAuth refreshes
    # :current_membership in place when the role changes, so a demotion must
    # stop the cross-tenant surface without waiting for a navigation.
    if admin?(socket.assigns[:current_membership]) do
      Process.send_after(self(), :refresh, @refresh_ms)
      {:noreply, assign_view_state(socket)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Admin access required.")
       |> push_navigate(to: "/")}
    end
  end

  defp assign_view_state(socket) do
    metrics = Ingestion.global_funnel_metrics()
    queue_depth = Queue.pending_count()
    telemetry_state = Config.load()
    endpoint = Sender.endpoint()
    identity_summary = identity_summary()

    socket
    |> assign(:metrics, metrics)
    |> assign(:queue_depth, queue_depth)
    |> assign(:telemetry_state, telemetry_state)
    |> assign(:endpoint, endpoint)
    |> assign(:identity_summary, identity_summary)
    |> assign(:recent_events, Ingestion.global_recent(limit: 25))
    |> assign(:mcp_audit_summary, AuditLog.global_summary())
    |> assign(:mcp_audit_by_tool, AuditLog.global_counts_by_tool())
    |> assign(:mcp_audit_recent, AuditLog.global_recent(limit: 25))
    |> assign(:mcp_registry_summary, Registry.summary())
    |> assign(:mcp_registry_entries, Registry.entries())
    |> assign(:mcp_registry_denylist, Registry.denylist())
    |> assign(:guardrails_summary, Guardrails.summary())
    |> assign(:org_budgets, org_budget_overviews())
    |> assign(:cloud_runs_summary, RuntimeContext.global_status_counts())
    |> assign(:cloud_runs_recent, RuntimeContext.global_recent(limit: 15))
    |> assign(:amplification_ratios, Budget.amplification_ratios(limit: 10, since_hours: 24))
    |> assign(:behavioral_baselines, load_behavioral_baselines())
    |> assign(:fallback_chain, load_fallback_chain())
    |> assign(:nhi_summaries, load_nhi_summaries())
  end

  defp org_budget_overviews do
    Accounts.list_orgs(status: "active")
    |> Enum.map(fn org ->
      status = Accounts.org_budget_status(org.id)
      breakdown = Accounts.org_workspace_breakdown(org.id)

      Map.merge(status, %{
        org_name: org.name,
        org_slug: org.slug,
        workspaces: breakdown
      })
    end)
  end

  defp identity_summary do
    case Identity.load() do
      {:ok, identity} ->
        %{
          status: :connected,
          workspace_id: identity.workspace_id,
          fingerprint: Identity.short_fingerprint(identity)
        }

      {:error, :not_connected} ->
        %{status: :not_connected}

      {:error, _} ->
        %{status: :malformed}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="cloud-telemetry-page"
      class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16 max-[900px]:w-[min(100%-1.25rem,1180px)] max-[900px]:pt-6"
    >
      <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
        <div>
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">Cloud</p>
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Cloud telemetry</h1>
          <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Local-first by design. Cloud sync is opt-in per workspace.
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class={telemetry_pill_class(@telemetry_state.level)}>
            {@telemetry_state.level}
          </span>
          <span class="border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
            {@metrics.total} received
          </span>
          <span class="border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
            {@queue_depth} pending
          </span>
        </div>
      </div>

      <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
        <div
          id="cloud-telemetry-identity"
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
        >
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Workspace identity
          </p>
          {render_identity(assigns)}
        </div>

        <div
          id="cloud-telemetry-endpoint"
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
        >
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Endpoint
          </p>
          <strong>{@endpoint || "unconfigured"}</strong>
          <p class="text-muted-foreground">
            {if @endpoint,
              do: "drainer will POST batches here",
              else: "set :cloud_telemetry_endpoint to enable sync"}
          </p>
        </div>

        <div
          id="cloud-telemetry-queue"
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
        >
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Outbound queue
          </p>
          <strong>{@queue_depth} pending</strong>
          <p class="text-muted-foreground">Persistent, idempotent, retried on backoff</p>
        </div>

        <div
          id="cloud-telemetry-received"
          class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
        >
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Received total
          </p>
          <strong>{@metrics.total}</strong>
          <p class="text-muted-foreground">
            across {@metrics.workspaces} workspace(s){last_seen_note(@metrics.last_received_at)}
          </p>
        </div>
      </div>

      <div
        id="cloud-telemetry-funnel"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Install → attach → first finding funnel</h2>
        <table>
          <thead>
            <tr>
              <th>Stage</th>
              <th>Event kind</th>
              <th>Count</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>1. Install</td>
              <td><code>install.success</code></td>
              <td>{@metrics.install_success}</td>
            </tr>
            <tr>
              <td>2. Attach</td>
              <td><code>attach.success</code></td>
              <td>{@metrics.attach_success}</td>
            </tr>
            <tr>
              <td>3. First finding</td>
              <td><code>finding.created</code></td>
              <td>{@metrics.first_findings}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        id="cloud-telemetry-by-kind"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>All event kinds</h2>
        <%= if @metrics.by_kind == [] do %>
          <p class="text-muted-foreground">No events received yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Kind</th>
                <th>Count</th>
              </tr>
            </thead>
            <tbody>
              <%= for {kind, count} <- @metrics.by_kind do %>
                <tr>
                  <td><code>{kind}</code></td>
                  <td>{count}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-agent-runs"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Cloud-agent run packages</h2>
        <p class="text-muted-foreground">
          <%= for {status, count} <- Enum.sort(@cloud_runs_summary) do %>
            <strong>{status}</strong>: {count} ·
          <% end %>
          <%= if @cloud_runs_summary == %{} do %>
            No cloud-agent runs yet.
          <% end %>
        </p>

        <%= if @cloud_runs_recent != [] do %>
          <table>
            <thead>
              <tr>
                <th>Package</th>
                <th>Runtime</th>
                <th>Status</th>
                <th>Task</th>
                <th>Workspace</th>
                <th>Created</th>
              </tr>
            </thead>
            <tbody>
              <%= for pkg <- @cloud_runs_recent do %>
                <tr>
                  <td><code>#{pkg.id}</code></td>
                  <td><code>{pkg.runtime_target}</code></td>
                  <td>{pkg.status}</td>
                  <td>{pkg.task_id || "—"}</td>
                  <td>{pkg.workspace_id}</td>
                  <td>{DateTime.to_iso8601(pkg.inserted_at)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-org-budgets"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Org budget rollup</h2>
        <%= if @org_budgets == [] do %>
          <p class="text-muted-foreground">No active orgs.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Org</th>
                <th>Workspaces</th>
                <th>Spent (cents)</th>
                <th>Budget (cents)</th>
                <th>Remaining</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for o <- @org_budgets do %>
                <tr>
                  <td><code>{o.org_slug}</code> — {o.org_name}</td>
                  <td>{o.workspace_count}</td>
                  <td>{o.spent_cents}</td>
                  <td>{format_cap(o.budget_cents)}</td>
                  <td>{format_remaining(o.remaining_cents)}</td>
                  <td>{if o.over_cap?, do: "OVER CAP", else: "ok"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-amplification-ratio"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Token amplification ratio (last 24 h)</h2>
        <p class="text-muted-foreground">
          output_tokens / input_tokens per session — ratios &gt;&gt; 10 may indicate runaway generation.
        </p>
        <%= if @amplification_ratios == [] do %>
          <p class="text-muted-foreground">No invocations recorded in the last 24 hours.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Session</th>
                <th>Workspace</th>
                <th>Input tokens</th>
                <th>Output tokens</th>
                <th>Ratio</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @amplification_ratios do %>
                <tr>
                  <td><code>{row.session_id}</code></td>
                  <td><code>{row.workspace_id || "—"}</code></td>
                  <td>{row.input_tokens}</td>
                  <td>{row.output_tokens}</td>
                  <td class={amplification_class(row.ratio)}>{row.ratio}×</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-behavioral-baselines"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Behavioral baselines</h2>
        <p class="text-muted-foreground">
          Per-workspace tool-usage baselines. Run
          <code>controlkeel baseline compute --workspace-id &lt;id&gt;</code>
          to refresh. Deviations ≥ 3× baseline create findings automatically.
        </p>
        <%= if @behavioral_baselines == [] do %>
          <p class="text-muted-foreground">No active workspaces.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Workspace</th>
                <th>Org</th>
                <th>Tools baselined</th>
                <th>Sample sessions</th>
                <th>Last computed</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @behavioral_baselines do %>
                <tr>
                  <td>
                    <code>{row.workspace_id}</code>{if row.workspace_name,
                      do: " — #{row.workspace_name}",
                      else: ""}
                  </td>
                  <td>{row.org_name}</td>
                  <td>{row.tool_count}</td>
                  <td>{row.sample_sessions || "—"}</td>
                  <td>
                    {if row.computed_at, do: DateTime.to_iso8601(row.computed_at), else: "never"}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-mcp-guardrails"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Content guardrails</h2>
        <p class="text-muted-foreground">
          enabled: <strong>{@guardrails_summary.enabled}</strong>
          ·
          patterns: {@guardrails_summary.pattern_count}
          {if @guardrails_summary.allow_for_tools == [],
            do: "",
            else: " · allow-for: " <> Enum.join(@guardrails_summary.allow_for_tools, ", ")}
        </p>
        <%= if @guardrails_summary.enabled do %>
          <p class="text-muted-foreground">
            Active:
            <%= for name <- @guardrails_summary.patterns do %>
              <code>{name}</code>
            <% end %>
          </p>
        <% else %>
          <p class="text-muted-foreground">
            Disabled — set <code>:cloud_mcp_guardrails</code>
            with <code>enabled: true</code>
            to scan tool arguments for secrets.
          </p>
        <% end %>
      </div>

      <div
        id="cloud-mcp-registry"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Downstream MCP server registry</h2>
        <p class="text-muted-foreground">
          default policy: <strong>{@mcp_registry_summary.default_policy}</strong>
          · {@mcp_registry_summary.allowlist_count} allowlisted · {@mcp_registry_summary.requires_attestation} require attestation · {@mcp_registry_summary.denylist_count} denylisted
        </p>
        <%= if @mcp_registry_entries == [] and @mcp_registry_denylist == [] do %>
          <p class="text-muted-foreground">No downstream MCP servers configured.</p>
        <% else %>
          <%= if @mcp_registry_entries != [] do %>
            <table>
              <thead>
                <tr>
                  <th>Allowlisted</th>
                  <th>Attestation</th>
                  <th>URL</th>
                  <th>Note</th>
                </tr>
              </thead>
              <tbody>
                <%= for e <- @mcp_registry_entries do %>
                  <tr>
                    <td><code>{e.name}</code></td>
                    <td>{e.attestation}</td>
                    <td><code>{e.url || ""}</code></td>
                    <td>{e.note || ""}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
          <%= if @mcp_registry_denylist != [] do %>
            <p class="text-muted-foreground">
              Denylisted:
              <%= for name <- @mcp_registry_denylist do %>
                <code>{name}</code>
              <% end %>
            </p>
          <% end %>
        <% end %>
      </div>

      <div
        id="cloud-fallback-chain"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Provider fallback chain</h2>
        <%= if @fallback_chain == [] do %>
          <p class="text-muted-foreground">
            No fallback chain configured. Set one with <code>controlkeel provider set-fallback-chain anthropic openai openrouter</code>.
          </p>
        <% else %>
          <ol class="grid gap-4 m-0 p-0 list-none" style="margin-top: 0.5rem;">
            <%= for {provider, idx} <- Enum.with_index(@fallback_chain, 1) do %>
              <li><strong>#{idx}</strong> <code>{provider}</code></li>
            <% end %>
          </ol>
          <p class="text-muted-foreground" style="margin-top: 0.5rem;">
            When a provider's budget is exhausted the next available provider in this chain is selected automatically.
          </p>
        <% end %>
      </div>

      <div
        id="cloud-nhi-summary"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Non-human identity (NHI) lifecycle</h2>
        <%= if @nhi_summaries == [] do %>
          <p class="text-muted-foreground">No service accounts provisioned yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Workspace</th>
                <th>Org</th>
                <th>Total</th>
                <th>Active</th>
                <th>Revoked</th>
              </tr>
            </thead>
            <tbody>
              <%= for summary <- @nhi_summaries do %>
                <tr>
                  <td>{summary.workspace_name}</td>
                  <td>{summary.org_name}</td>
                  <td>{summary.total}</td>
                  <td>{summary.active}</td>
                  <td>{summary.revoked}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-mcp-audit-summary"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Hosted MCP / A2A audit</h2>
        <p class="text-muted-foreground">
          {@mcp_audit_summary.total} total · {@mcp_audit_summary.allowed} allowed · {@mcp_audit_summary.denied} denied
        </p>
        <%= if @mcp_audit_by_tool == [] do %>
          <p class="text-muted-foreground">No hosted MCP / A2A calls recorded yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Tool</th>
                <th>Allowed</th>
                <th>Denied</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @mcp_audit_by_tool do %>
                <tr>
                  <td><code>{row.tool_name}</code></td>
                  <td>{row.allowed}</td>
                  <td>{row.denied}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-mcp-audit-recent"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Recent tool dispatches</h2>
        <%= if @mcp_audit_recent == [] do %>
          <p class="text-muted-foreground">No calls yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Resource</th>
                <th>Tool</th>
                <th>Outcome</th>
                <th>Reason</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @mcp_audit_recent do %>
                <tr>
                  <td>{DateTime.to_iso8601(row.requested_at)}</td>
                  <td><code>{row.resource}</code></td>
                  <td><code>{row.tool_name}</code></td>
                  <td>{row.outcome}</td>
                  <td>{row.denial_reason || ""}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <div
        id="cloud-telemetry-recent"
        class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
      >
        <h2>Recent received events</h2>
        <%= if @recent_events == [] do %>
          <p class="text-muted-foreground">No events received yet.</p>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>Received at</th>
                <th>Kind</th>
                <th>Workspace</th>
                <th>Event ID</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @recent_events do %>
                <tr>
                  <td>{DateTime.to_iso8601(event.received_at)}</td>
                  <td><code>{event.kind}</code></td>
                  <td><code>{event.workspace_id}</code></td>
                  <td><code>{String.slice(event.event_id, 0, 16)}...</code></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </section>
    """
  end

  defp render_identity(
         %{identity_summary: %{status: :connected, workspace_id: ws, fingerprint: fp}} = assigns
       ) do
    assigns = assign(assigns, ws: ws, fp: fp)

    ~H"""
    <strong>{@ws}</strong>
    <p class="text-muted-foreground">fingerprint {@fp}…</p>
    """
  end

  defp render_identity(%{identity_summary: %{status: :not_connected}} = assigns) do
    ~H"""
    <strong>not connected</strong>
    <p class="text-muted-foreground">run <code>controlkeel cloud connect</code></p>
    """
  end

  defp render_identity(assigns) do
    ~H"""
    <strong>error</strong>
    <p class="text-muted-foreground">identity file malformed</p>
    """
  end

  defp telemetry_pill_class(:disabled),
    do:
      "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp telemetry_pill_class(_other),
    do: "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem]"

  defp format_cap(nil), do: "uncapped"
  defp format_cap(n) when is_integer(n), do: Integer.to_string(n)

  defp format_remaining(nil), do: "—"
  defp format_remaining(n) when is_integer(n), do: Integer.to_string(n)

  defp last_seen_note(nil), do: ""
  defp last_seen_note(%DateTime{} = ts), do: ", last #{DateTime.to_iso8601(ts)}"

  defp amplification_class(_ratio), do: ""

  defp load_behavioral_baselines do
    Accounts.list_orgs(status: "active")
    |> Enum.flat_map(fn org ->
      Accounts.org_workspace_breakdown(org.id)
      |> Enum.map(fn ws ->
        baseline = BaselineAnalyzer.get_baseline(ws.workspace_id)

        %{
          workspace_id: ws.workspace_id,
          workspace_name: ws.workspace_name,
          org_name: org.name,
          computed_at: baseline && baseline.computed_at,
          sample_sessions: baseline && baseline.sample_sessions,
          tool_count: baseline_tool_count(baseline)
        }
      end)
    end)
  end

  defp baseline_tool_count(nil), do: 0

  defp baseline_tool_count(baseline) do
    baseline
    |> Baseline.decode()
    |> map_size()
  end

  defp load_fallback_chain do
    case ProviderConfig.read() do
      {:ok, config} -> Map.get(config, "fallback_chain", [])
      _ -> []
    end
  end

  defp load_nhi_summaries do
    Accounts.list_orgs(status: "active")
    |> Enum.flat_map(fn org ->
      Accounts.org_workspace_breakdown(org.id)
      |> Enum.map(fn ws ->
        summary = Platform.nhi_lifecycle_summary(ws.workspace_id)
        Map.merge(summary, %{workspace_name: ws.workspace_name, org_name: org.name})
      end)
    end)
    |> Enum.reject(&(&1.total == 0))
  end
end
