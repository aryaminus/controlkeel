defmodule ControlKeelWeb.WorkspaceIndexLive do
  @moduledoc """
  Organization workspaces index at `/:org_slug/workspaces`.

  The workspace grid (creation + cards) moved here from the org overview
  page: workspaces group sessions, findings, and budgets under this
  organization, so they get their own section in the org sidebar instead
  of living at the bottom of the dashboard. The overview keeps the
  metrics band and delivery funnel.

  Any active member (viewer+) may view. Workspace creation is admin+
  gated by `can_manage?` (server-side), with the same local-mode refusal
  as before (only the default workspace exists locally).

  Access resolves per-URL via `ControlKeelWeb.OrgAccess.resolve/3`
  (default `"viewer"` role), exactly like the org overview page.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
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
    {:ok,
     socket
     |> assign(:page_title, "Workspaces — #{org.name}")
     |> assign(:org, org)
     |> assign(:nav_org, org)
     |> assign(:local_mode, Mode.current() == :local)
     |> assign(:current_membership, membership)
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

  # An unresolved org scope renders the shared not-found panel from the org
  # layout (see `ControlKeelWeb.OrgAccess`); this page body stays empty. The
  # assign is always present (defaulted to nil by the layout hook), so the
  # clause must match only a real error map.
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <div class="flex items-center justify-between gap-4">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
          Workspaces
        </h1>
        <p class="text-sm text-muted-foreground">
          Workspaces group sessions, findings, and budgets under this organization.
        </p>
      </div>

      <div class="flex items-center justify-end gap-3">
        <.button
          variant="outline"
          phx-click="new_workspace"
          class="shrink-0 rounded-full px-4 py-2 text-sm font-medium"
        >
          <.icon name="hero-plus" class="size-4" /> New Workspace
        </.button>
      </div>

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

  # ── Workspace creation (moved from the org overview page) ──────────────

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

  @impl true
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
