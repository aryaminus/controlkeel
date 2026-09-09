defmodule ControlKeelWeb.OrganizationWorkspacesLive do
  @moduledoc """
  Workspaces of an org at `/organizations/:slug/workspaces`.

  Lists the org's workspaces and hosts the New Workspace modal.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Organization not found.", ~p"/organizations")}

      org ->
        mode = Mode.current()
        user = socket.assigns[:current_user]

        cond do
          mode == :local ->
            mount_ok(socket, org, nil)

          is_nil(user) ->
            {:ok,
             redirect_with_flash(
               socket,
               :error,
               "Sign in to view this organization.",
               ~p"/auth/login"
             )}

          true ->
            case Accounts.get_active_membership(user.id, org.id) do
              nil ->
                {:ok,
                 redirect_with_flash(
                   socket,
                   :error,
                   "You're not a member of that organization.",
                   ~p"/organizations"
                 )}

              membership ->
                mount_ok(socket, org, membership)
            end
        end
    end
  end

  defp mount_ok(socket, org, membership) do
    {:ok,
     socket
     |> assign(:page_title, "Workspaces — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, Mode.current() == :local)
     |> assign(:can_manage, membership && Accounts.role_at_least?(membership.role, "admin"))
     |> assign(:active_tab, :workspaces)
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
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
        Workspaces
      </h1>

      <div class="flex items-center justify-between gap-3">
        <p class="text-sm text-muted-foreground">
          Workspaces group sessions, findings, and budgets under this organization.
        </p>
        <button
          type="button"
          phx-click="new_workspace"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="size-4" /> New Workspace
        </button>
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
              href={~p"/organizations/#{@org.slug}/workspaces/#{ws.id}"}
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
              class="rounded-md text-muted-foreground transition hover:text-foreground"
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

  defp format_cents(nil), do: "—"
  defp format_cents(0), do: "—"
  defp format_cents(cents) when is_integer(cents), do: "$#{Float.round(cents / 100, 2)}"

  defp redirect_with_flash(socket, kind, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, message)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
