defmodule ControlKeelWeb.OrganizationDetailLive do
  @moduledoc """
  Organization overview at `/:org_slug` — the org's dashboard.

  Any active member (viewer+) may view. Renders the organization header,
  scope metadata, the org-scoped metrics band (`Analytics.funnel_summary/1`
  with `:org_id`, per docs/retire-dashboard-issue.md), and the workspace
  grid with workspace creation (admin+ gated by `can_manage?`).

  Member management (roster, invites, roles, revocation) lives on the
  settings page's Members tab (`ControlKeelWeb.OrganizationSettingsLive`,
  admin+ by the settings page gate). This page keeps only the member *count*
  metric in the stats band.

  ## Access

  Resolved per-URL via `ControlKeelWeb.OrgAccess.resolve/3`, which checks
  existence before authorization (default `"viewer"` role; NOT the session's
  pinned `current_membership`). Local mode has no membership table and is
  unrestricted. Cloud/self_hosted requires the signed-in user to hold an
  active membership for this specific org. An org that does not exist, or that
  the visitor cannot access, renders the shared in-place not-found panel at the
  requested URL instead of bouncing to a global page.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Analytics
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode
  alias ControlKeelWeb.OrgAccess

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        mount_ok(socket, org, membership)

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  defp mount_ok(socket, org, membership) do
    local_mode = Mode.current() == :local
    budget_cents = Accounts.org_budget_cents(org) || 0
    memberships = if(local_mode, do: [], else: load_memberships(org.id))

    {:ok,
     socket
     |> assign(:page_title, "Organization Detail — #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:budget_cents, budget_cents)
     |> assign(:ship_summary, Analytics.funnel_summary(org_id: org.id))
     |> assign(:current_membership, membership)
     |> assign(:memberships, memberships)
     |> assign(:workspaces, load_workspaces(org.id))
     |> assign(:show_new_workspace, false)
     |> assign(
       :new_workspace_form,
       to_form(
         %{
           "name" => "",
           "slug" => "",
           "industry" => "",
           "budget_cents" => "0"
         },
         as: :workspace
       )
     )
     |> assign(:new_workspace_error, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = maybe_refresh_org(socket, params["org_slug"])

    {:noreply, socket}
  end

  defp maybe_refresh_org(%{assigns: %{org: %{slug: slug}}} = socket, slug), do: socket

  defp maybe_refresh_org(socket, slug) when is_binary(slug) do
    case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        {:ok, socket} = mount_ok(socket, org, membership)
        assign(socket, :scope_error, nil)

      {:error, error} ->
        assign(socket, :scope_error, error)
    end
  end

  defp maybe_refresh_org(socket, _slug), do: socket

  def handle_event("new_workspace", _params, socket) do
    {:noreply, assign(socket, :show_new_workspace, true)}
  end

  def handle_event("close_new_workspace", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_workspace, false)
     |> assign(:new_workspace_error, nil)}
  end

  def handle_event("validate_workspace", %{"workspace" => params}, socket) do
    {:noreply, assign(socket, :new_workspace_form, to_form(params, as: :workspace))}
  end

  def handle_event("save_workspace", %{"workspace" => params}, socket) do
    if socket.assigns.local_mode do
      {:noreply,
       socket
       |> assign(:show_new_workspace, false)
       |> put_flash(
         :error,
         "Only the default workspace is available in local mode. Upgrade to cloud mode to create additional workspaces."
       )}
    else
      if can_manage?(socket.assigns) do
        org = socket.assigns.org

        params =
          params |> Map.put("slug", resolve_workspace_slug(params)) |> Map.put("org_id", org.id)

        case create_workspace(params) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:show_new_workspace, false)
             |> assign(:new_workspace_error, nil)
             |> assign(:workspaces, load_workspaces(org.id))
             |> put_flash(:info, "Workspace #{workspace.name} created.")}

          {:error, %Ecto.Changeset{} = cs} ->
            msg =
              cs.errors
              |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

            {:noreply, assign(socket, :new_workspace_error, msg)}

          {:error, reason} ->
            {:noreply, assign(socket, :new_workspace_error, inspect(reason))}
        end
      else
        {:noreply, put_flash(socket, :error, "You don't have permission to create workspaces.")}
      end
    end
  end

  # An unresolved org scope renders the shared not-found panel from the org
  # layout (see `ControlKeelWeb.OrgAccess`); this page body stays empty. The
  # assign is always present (defaulted to nil by the layout hook), so the
  # clause must match only a real error map.
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <div class="space-y-2">
        <div class="flex flex-wrap items-center gap-3">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            {@org.name}
          </h1>

          <span class={[
            "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
            @org.status == "active" && "bg-success/10 text-success ring-success/20",
            @org.status != "active" && "bg-muted text-muted-foreground ring-border"
          ]}>
            {@org.status}
          </span>
        </div>

        <p class="text-sm text-muted-foreground">
          Browse workspaces and track delivery across this organization.
        </p>
      </div>

      <%!-- Identity metadata as plain text — no box; the numbers live in the
           metrics band below. --%>
      <p class="text-xs text-muted-foreground">
        <span class="font-mono">{@org.slug}</span>
        <span class="mx-2">·</span>
        Budget {if @budget_cents > 0, do: "$#{Float.round(@budget_cents / 100, 2)}", else: "—"}
        <span class="mx-2">·</span>
        Created {Calendar.strftime(@org.inserted_at, "%b %d, %Y")}
      </p>

      <%!-- Org-scoped dashboard stats (Analytics.funnel_summary/1 with :org_id),
           rendered as one compact band instead of per-metric cards. --%>
      <div class="grid grid-cols-2 gap-x-6 gap-y-4 rounded-2xl border bg-card px-5 py-4 shadow-card sm:grid-cols-3 xl:grid-cols-5">
        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
            Proof Coverage
          </span>
          <span class="text-lg font-semibold text-foreground/90">
            {format_percent(@ship_summary.outcome_metrics.proof_backed_task_coverage_percent)}
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
            Deploy Ready
          </span>
          <span class="text-lg font-semibold text-foreground/90">
            {format_percent(@ship_summary.outcome_metrics.deploy_ready_task_rate_percent)}
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
            Finding Density
          </span>
          <span class="text-lg font-semibold text-foreground/90">
            {format_number(@ship_summary.average_findings_per_session)}
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
            Sessions
          </span>
          <span class="text-lg font-semibold text-foreground/90">
            {@ship_summary.recent_session_count}
          </span>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
            Members
          </span>
          <span class="text-lg font-semibold text-foreground/90">
            {if @local_mode, do: "—", else: length(@memberships)}
          </span>
        </div>
      </div>

      <div class="flex items-center justify-between gap-3">
          <p class="text-sm text-muted-foreground">
            Workspaces group sessions, findings, and budgets under this organization.
          </p>
          <.button
            variant="outline"
            phx-click="new_workspace"
            class="shrink-0 rounded-full px-4 py-2 text-sm font-medium"
          >
            <.icon name="hero-plus" class="size-4" /> New Workspace
          </.button>
        </div>

        <%= if @workspaces == [] do %>
          <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
            <.icon name="hero-squares-2x2" class="mx-auto size-10 text-muted-foreground" />
            <p class="mt-4 text-base font-medium text-foreground">No workspaces yet.</p>
            <p class="mt-1 text-sm text-muted-foreground">
              Workspaces group sessions, findings, and budgets under this organization.
            </p>
          </section>
        <% else %>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <%= for ws <- @workspaces do %>
              <.link
                href={~p"/#{@org.slug}/workspaces/#{ws.slug}"}
                class="group block rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:shadow-card"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="flex min-w-0 items-center gap-2">
                    <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-info/10 text-info">
                      <.icon name="hero-squares-2x2" class="size-4" />
                    </span>
                    <h3 class="truncate text-base font-semibold text-foreground transition group-hover:text-primary">
                      {ws.name}
                    </h3>
                  </div>
                  <span class={[
                    "shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    ws.status == "active" && "bg-success/10 text-success ring-success/20",
                    ws.status != "active" && "bg-muted text-muted-foreground ring-border"
                  ]}>
                    {ws.status}
                  </span>
                </div>
                <p class="mt-1 truncate font-mono text-xs text-muted-foreground">{ws.slug}</p>
                <dl class="mt-4 grid grid-cols-2 gap-3 border-t pt-4">
                  <div>
                    <dt class="text-xs font-medium text-muted-foreground">Sessions</dt>
                    <dd class="mt-1 text-lg font-semibold text-foreground/90">
                      {length(ws.sessions)}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs font-medium text-muted-foreground">Budget</dt>
                    <dd class="mt-1 text-lg font-semibold text-foreground/90">
                      {format_cents(ws.budget_cents)}
                    </dd>
                  </div>
                </dl>
              </.link>
            <% end %>
          </div>
        <% end %>
      <.new_workspace_modal
        :if={@show_new_workspace}
        local_mode={@local_mode}
        form={@new_workspace_form}
        error={@new_workspace_error}
      />
    </section>
    """
  end

  attr :local_mode, :boolean, default: false
  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp new_workspace_modal(assigns) do
    ~H"""
    <div
      id="new-workspace-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#new-workspace-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#new-workspace-modal")}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="close_new_workspace"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">New Workspace</h2>
            <button
              type="button"
              phx-click="close_new_workspace"
              class="rounded-md text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%= if @local_mode do %>
            <div class="rounded-xl border border-warning/30 bg-warning/10 p-4">
              <div class="flex items-center gap-2">
                <.icon name="hero-lock-closed" class="size-4 text-warning" />
                <p class="text-sm font-semibold text-warning">Local mode</p>
              </div>
              <p class="mt-2 text-sm text-foreground/80">
                Only the default workspace is available in local mode.
              </p>
              <p class="mt-1 text-sm text-muted-foreground">
                Upgrade to cloud mode to create additional workspaces.
              </p>
            </div>
          <% else %>
            <.form
              for={@form}
              phx-submit="save_workspace"
              phx-change="validate_workspace"
              id="new-workspace-form"
              class="space-y-4"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Workspace name"
                required
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:slug]}
                type="text"
                label="Slug"
                placeholder="Auto-generated from name"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:industry]}
                type="select"
                label="Industry"
                options={industry_options()}
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:budget_cents]}
                type="number"
                label="Monthly budget (cents)"
                min="0"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <%= if @error do %>
                <p class="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {@error}
                </p>
              <% end %>

              <div class="flex items-center justify-end gap-3 pt-4">
                <button
                  type="button"
                  phx-click="close_new_workspace"
                  class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
                >
                  Create
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  # Stat formatting ported from the retired DashboardLive (docs/retire-dashboard-issue.md).
  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_percent(value), do: "#{value}%"

  defp format_number(nil), do: "Not recorded"
  defp format_number(value) when is_float(value), do: Float.round(value, 1)
  defp format_number(value), do: value

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id)
    |> Repo.preload(:user)
  end

  defp load_workspaces(org_id) do
    Mission.list_workspaces_for_org(org_id)
    |> Repo.preload(:sessions)
  end

  defp create_workspace(attrs) do
    attrs
    |> Map.put_new("agent", "claude")
    |> Map.put_new("compliance_profile", "general")
    |> Map.put_new("status", "active")
    |> Mission.create_workspace()
  end

  defp resolve_workspace_slug(params) do
    case Map.get(params, "slug", "") do
      slug when is_binary(slug) and slug != "" -> slug
      _ -> slugify(Map.get(params, "name", ""))
    end
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: ""

  defp industry_options do
    [
      {"General", "general"},
      {"Web", "web"},
      {"Security", "security"},
      {"Finance", "finance"}
    ]
  end

  defp current_role(%{current_membership: %{role: role}}), do: role
  defp current_role(_assigns), do: nil

  defp can_manage?(assigns), do: Accounts.role_at_least?(current_role(assigns) || "", "admin")

  defp format_cents(nil), do: "—"
  defp format_cents(0), do: "—"
  defp format_cents(cents) when is_integer(cents), do: "$#{Float.round(cents / 100, 2)}"
end
