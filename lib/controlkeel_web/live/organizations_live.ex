defmodule ControlKeelWeb.OrganizationsLive do
  @moduledoc """
  `/organizations` — nested accordion of organizations → workspaces → sessions.
  Replaces previous grid view; content moved from `/home`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    orgs = list_orgs(socket)
    local_mode = Mode.current() == :local

    workspaces_by_org =
      Map.new(orgs, fn org -> {org.id, load_workspaces(org.id)} end)

    sessions_by_workspace =
      workspaces_by_org
      |> Map.values()
      |> List.flatten()
      |> Map.new(fn ws -> {ws.id, load_sessions(ws.id)} end)

    changeset = Org.changeset(%Org{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:current_path, "/organizations")
     |> assign(:local_mode, local_mode)
     |> assign(:show_create_modal, false)
     |> assign(:changeset, changeset)
     |> assign_form(changeset)
     |> assign(:orgs, orgs)
     |> assign(:workspaces_by_org, workspaces_by_org)
     |> assign(:sessions_by_workspace, sessions_by_workspace)
     |> assign(:expanded_orgs, MapSet.new())
     |> assign(:expanded_workspaces, MapSet.new())}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :org))
  end

  @impl true
  def handle_event("toggle_org", %{"org_id" => org_id}, socket) do
    org_id = parse_id(org_id)
    expanded_orgs = socket.assigns.expanded_orgs
    workspaces_by_org = socket.assigns.workspaces_by_org

    {expanded_orgs, workspaces_by_org} =
      if MapSet.member?(expanded_orgs, org_id) do
        {MapSet.delete(expanded_orgs, org_id), workspaces_by_org}
      else
        expanded = MapSet.put(expanded_orgs, org_id)

        workspaces_by_org =
          if Map.has_key?(workspaces_by_org, org_id) do
            workspaces_by_org
          else
            Map.put(workspaces_by_org, org_id, load_workspaces(org_id))
          end

        {expanded, workspaces_by_org}
      end

    {:noreply,
     socket
     |> assign(:expanded_orgs, expanded_orgs)
     |> assign(:workspaces_by_org, workspaces_by_org)}
  end

  def handle_event("toggle_workspace", %{"workspace_id" => ws_id}, socket) do
    ws_id = parse_id(ws_id)
    expanded_workspaces = socket.assigns.expanded_workspaces
    sessions_by_workspace = socket.assigns.sessions_by_workspace

    {expanded_workspaces, sessions_by_workspace} =
      if MapSet.member?(expanded_workspaces, ws_id) do
        {MapSet.delete(expanded_workspaces, ws_id), sessions_by_workspace}
      else
        expanded = MapSet.put(expanded_workspaces, ws_id)

        sessions_by_workspace =
          if Map.has_key?(sessions_by_workspace, ws_id) do
            sessions_by_workspace
          else
            Map.put(sessions_by_workspace, ws_id, load_sessions(ws_id))
          end

        {expanded, sessions_by_workspace}
      end

    {:noreply,
     socket
     |> assign(:expanded_workspaces, expanded_workspaces)
     |> assign(:sessions_by_workspace, sessions_by_workspace)}
  end

  @impl true
  def handle_event("new_org", _params, socket) do
    changeset = Org.changeset(%Org{}, %{})

    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:changeset, changeset)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    changeset = Org.changeset(%Org{}, %{})

    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:changeset, changeset)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    changeset =
      %Org{}
      |> Org.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset) |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{local_mode: true}} = socket) do
    {:noreply, local_mode_org_creation_denied(socket)}
  end

  def handle_event("save", %{"org" => params}, socket) do
    create_default_workspace? = Map.get(params, "create_default_workspace") == "true"

    case create_org_for_current_mode(socket, params, create_default_workspace?) do
      {:ok, _org, true} ->
        orgs = list_orgs(socket)

        {:noreply,
         socket
         |> put_flash(:info, "Organization created with a default workspace.")
         |> assign(:show_create_modal, false)
         |> assign(:orgs, orgs)
         |> assign(
           :workspaces_by_org,
           Map.new(orgs, fn org -> {org.id, load_workspaces(org.id)} end)
         )
         |> assign(
           :sessions_by_workspace,
           Map.new(
             List.flatten(
               Map.values(Map.new(orgs, fn org -> {org.id, load_workspaces(org.id)} end))
             ),
             fn ws ->
               {ws.id, load_sessions(ws.id)}
             end
           )
         )}

      {:ok, _org, false} ->
        orgs = list_orgs(socket)

        {:noreply,
         socket
         |> put_flash(:info, "Organization created.")
         |> assign(:show_create_modal, false)
         |> assign(:orgs, orgs)
         |> assign(
           :workspaces_by_org,
           Map.new(orgs, fn org -> {org.id, load_workspaces(org.id)} end)
         )
         |> assign(
           :sessions_by_workspace,
           Map.new(
             List.flatten(
               Map.values(Map.new(orgs, fn org -> {org.id, load_workspaces(org.id)} end))
             ),
             fn ws ->
               {ws.id, load_sessions(ws.id)}
             end
           )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset) |> assign_form(changeset)}

      {:error, :signed_out} ->
        {:noreply, put_flash(socket, :error, "Sign in to create an organization.")}

      {:error, :local_mode} ->
        {:noreply, local_mode_org_creation_denied(socket)}
    end
  end

  defp create_org_for_current_mode(socket, params, create_default_workspace?) do
    cond do
      Mode.current() == :local ->
        {:error, :local_mode}

      user = socket.assigns[:current_user] ->
        with {:ok, org} <- Accounts.create_org_with_owner(user.id, params) do
          if create_default_workspace? do
            {:ok, org, create_default_workspace_for_org(org)}
          else
            {:ok, org, false}
          end
        end

      true ->
        {:error, :signed_out}
    end
  end

  defp create_default_workspace_for_org(org) do
    attrs = %{
      name: "Default Workspace",
      slug: generate_default_workspace_slug(),
      industry: "general",
      agent: "claude",
      budget_cents: 0,
      compliance_profile: "general",
      status: "active",
      org_id: org.id
    }

    case Mission.create_workspace(attrs) do
      {:ok, _workspace} ->
        true

      {:error, _changeset} ->
        case Mission.create_workspace(Map.put(attrs, :slug, generate_default_workspace_slug())) do
          {:ok, _workspace} -> true
          {:error, _changeset} -> false
        end
    end
  end

  defp generate_default_workspace_slug do
    "default-ws-" <> random_alnum(5)
  end

  defp random_alnum(n) do
    "abcdefghijklmnopqrstuvwxyz0123456789"
    |> String.graphemes()
    |> Enum.take_random(n)
    |> Enum.join()
  end

  defp local_mode_org_creation_denied(socket) do
    socket
    |> put_flash(
      :error,
      "Organizations are not created in local mode — only the default organization is available. Upgrade to cloud mode to create organizations."
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-8">
      <div class="px-1">
        <p class="text-sm leading-6 text-muted-foreground">
          Welcome to your ControlKeel home. Browse all organizations in one place — expand any organization to reveal its workspaces, and expand a workspace to explore its sessions.
        </p>
      </div>

      <div class="flex items-center justify-between px-1">
        <h2 class="text-sm font-semibold text-foreground">Organizations</h2>
        <button
          type="button"
          phx-click="new_org"
          class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
        >
          <.icon name="hero-plus" class="size-4" /> New Organization
        </button>
      </div>

      <section class="rounded-2xl border bg-card shadow-card overflow-hidden">
        <div class="divide-y">
          <%= if @orgs == [] do %>
            <p class="px-5 py-10 text-center text-sm text-muted-foreground sm:px-6">
              No organizations yet.
            </p>
          <% else %>
            <%= for org <- @orgs do %>
              <% expanded_org? = MapSet.member?(@expanded_orgs, org.id) %>
              <% workspaces = Map.get(@workspaces_by_org, org.id) %>
              <div class="bg-card">
                <button
                  type="button"
                  phx-click="toggle_org"
                  phx-value-org_id={org.id}
                  class="flex w-full items-center justify-between px-5 py-4 text-left transition hover:bg-muted/40 sm:px-6"
                >
                  <span class="min-w-0 text-left">
                    <span class="block truncate text-sm font-semibold text-foreground">
                      {org.name}
                    </span>
                    <span class="mt-1 inline-flex rounded-full border bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                      {length(workspaces || [])} {if length(workspaces || []) == 1,
                        do: "workspace",
                        else: "workspaces"}
                    </span>
                  </span>
                  <span class="ml-3 flex shrink-0 items-center gap-2">
                    <.link
                      navigate={~p"/organizations/#{org.slug}"}
                      class="inline-flex items-center rounded-full border bg-card px-3 py-1 text-xs font-medium text-foreground transition hover:bg-muted"
                      onclick="event.stopPropagation()"
                    >
                      Open
                    </.link>
                    <.icon
                      name="hero-chevron-down"
                      class={[
                        "size-4 shrink-0 text-muted-foreground transition-transform",
                        expanded_org? && "rotate-180"
                      ]}
                    />
                  </span>
                </button>

                <div :if={expanded_org?} class="border-t bg-muted/10">
                  <div class="px-5 py-3 sm:px-6">
                    <%= cond do %>
                      <% is_nil(workspaces) -> %>
                        <p class="py-4 text-center text-sm text-muted-foreground">
                          Loading workspaces…
                        </p>
                      <% workspaces == [] -> %>
                        <p class="rounded-xl border border-dashed bg-card px-4 py-6 text-center text-sm text-muted-foreground">
                          No workspaces in this organization.
                        </p>
                      <% true -> %>
                        <div class="space-y-2">
                          <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                            Workspaces
                          </p>
                          <%= for ws <- workspaces do %>
                            <% expanded_ws? = MapSet.member?(@expanded_workspaces, ws.id) %>
                            <% sessions = Map.get(@sessions_by_workspace, ws.id) %>
                            <div>
                              <button
                                type="button"
                                phx-click="toggle_workspace"
                                phx-value-workspace_id={ws.id}
                                class="flex w-full items-center justify-between px-4 py-3 text-left transition hover:bg-muted/40"
                              >
                                <span class="flex min-w-0 items-center gap-2.5">
                                  <span class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-info/10 text-info">
                                    <.icon name="hero-squares-2x2" class="size-4" />
                                  </span>
                                  <span class="min-w-0 text-left">
                                    <span class="block truncate text-sm font-medium text-foreground">
                                      {ws.name}
                                    </span>
                                    <span
                                      :if={sessions && length(sessions) > 0}
                                      class="mt-1 inline-flex rounded-full border bg-muted px-2 py-0.5 text-xs text-muted-foreground"
                                    >
                                      {length(sessions)} sessions
                                    </span>
                                  </span>
                                </span>
                                <span class="ml-3 flex shrink-0 items-center gap-2">
                                  <.icon
                                    name="hero-chevron-down"
                                    class={[
                                      "size-4 text-muted-foreground transition-transform",
                                      expanded_ws? && "rotate-180"
                                    ]}
                                  />
                                </span>
                              </button>

                              <div :if={expanded_ws?} class="px-3 py-3">
                                <%= cond do %>
                                  <% is_nil(sessions) -> %>
                                    <p class="py-3 text-center text-sm text-muted-foreground">
                                      Loading sessions…
                                    </p>
                                  <% sessions == [] -> %>
                                    <p class="rounded-lg border border-dashed bg-card px-3 py-4 text-center text-sm text-muted-foreground">
                                      No sessions in this workspace.
                                    </p>
                                  <% true -> %>
                                    <div class="space-y-1.5">
                                      <p class="px-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                                        Sessions
                                      </p>
                                      <%= for s <- sessions do %>
                                        <.link
                                          navigate={~p"/sessions/#{s.id}"}
                                          class="flex items-center justify-between px-3 py-2.5 transition hover:bg-muted/40 border-b border-border last:border-none"
                                        >
                                          <p class="truncate text-sm font-medium text-foreground">
                                            {s.title}
                                          </p>
                                        </.link>
                                      <% end %>
                                    </div>
                                <% end %>
                              </div>
                            </div>
                          <% end %>
                        </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>

      <.create_modal :if={@show_create_modal} form={@form} local_mode={@local_mode} />
    </div>
    """
  end

  attr :form, :map, required: true
  attr :local_mode, :boolean, default: false

  defp create_modal(assigns) do
    ~H"""
    <div
      id="organization-create-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#organization-create-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#organization-create-modal")}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="cancel_new"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">New organization</h2>
            <button
              type="button"
              phx-click="cancel_new"
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
                Only the default organization is available in local mode.
              </p>
              <p class="mt-1 text-sm text-muted-foreground">
                Upgrade to cloud mode to create additional organizations.
              </p>
            </div>
          <% else %>
            <.form
              for={@form}
              phx-change="validate"
              phx-submit="save"
              id="organization-form"
              class="space-y-4"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Name"
                placeholder="Acme Inc"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <.input
                field={@form[:slug]}
                type="text"
                label="Slug"
                placeholder="acme-inc"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />

              <p class="text-xs text-muted-foreground">
                Lowercase letters, numbers, and hyphens. Used in URLs.
              </p>

              <label class="flex items-start gap-3 rounded-xl border border-input bg-background p-3 cursor-pointer">
                <input
                  type="checkbox"
                  name="org[create_default_workspace]"
                  value="true"
                  checked
                  class="mt-0.5 size-4 rounded border-input text-primary focus:ring-primary"
                />
                <span>
                  <span class="block text-sm font-medium text-foreground">
                    Create a default workspace
                  </span>
                  <span class="block text-xs text-muted-foreground">
                    A starter workspace with a unique auto-generated slug will be created in this organization.
                  </span>
                </span>
              </label>

              <div class="flex items-center justify-end gap-3 border-t pt-4">
                <button
                  type="button"
                  phx-click="cancel_new"
                  class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
                >
                  Create organization
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp list_orgs(socket) do
    cond do
      Mode.current() == :local ->
        Accounts.list_orgs(status: "active")

      user = socket.assigns[:current_user] ->
        Accounts.list_orgs_for_user(user.id)
        |> Enum.map(& &1.org)

      true ->
        []
    end
  end

  defp load_workspaces(org_id) do
    Mission.list_workspaces_for_org(org_id)
  end

  defp load_sessions(workspace_id) do
    Mission.list_sessions_for_workspace(workspace_id)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp parse_id(id), do: id
end
