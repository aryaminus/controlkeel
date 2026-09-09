defmodule ControlKeelWeb.OrganizationsLive do
  @moduledoc """
  `/organizations` — list and create organizations.

  Local mode (no user) shows every org in the DB and creates bare Org rows.
  Cloud/self_hosted mode shows only orgs where the signed-in user has an
  active membership, and creates an org plus an owner membership in one
  transaction. Create happens in an inline modal — no separate route.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    local_mode = Mode.current() == :local

    socket =
      socket
      |> assign(:page_title, "Organizations")
      |> assign(:local_mode, local_mode)
      |> assign(:page_action, %{label: "New Organization", event: "new_org", icon: "hero-plus"})
      |> assign(:show_create_modal, false)
      |> assign(:changeset, Org.changeset(%Org{}, %{}))
      |> assign_form(Org.changeset(%Org{}, %{}))

    {:ok, assign(socket, :orgs, list_orgs_for_socket(socket))}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :org))
  end

  defp list_orgs_for_socket(socket) do
    cond do
      Mode.current() == :local ->
        # Local mode has no membership concept — every row gets role: nil.
        Accounts.list_orgs(status: "active")
        |> Enum.map(fn org ->
          %{org: org, role: nil, member_count: Accounts.count_memberships_for_org(org.id)}
        end)

      user = socket.assigns[:current_user] ->
        Accounts.list_orgs_for_user(user.id)
        |> Enum.map(fn row ->
          Map.put(row, :member_count, Accounts.count_memberships_for_org(row.org.id))
        end)

      true ->
        []
    end
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
        {:noreply,
         socket
         |> put_flash(:info, "Organization created with a default workspace.")
         |> assign(:show_create_modal, false)
         |> assign(:orgs, list_orgs_for_socket(socket))}

      {:ok, _org, false} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created.")
         |> assign(:show_create_modal, false)
         |> assign(:orgs, list_orgs_for_socket(socket))}

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
    <section class="w-full">
      <%= if @orgs == [] do %>
        <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
          <.icon name="hero-building-office-2" class="mx-auto size-10 text-muted-foreground" />
          <p class="mt-4 text-base font-medium text-foreground">No organizations yet.</p>
          <p class="mt-1 text-sm text-muted-foreground">
            <%= if @local_mode do %>
              In local mode only the default organization is available.
            <% else %>
              Create an organization to group workspaces, members, and budgets.
            <% end %>
          </p>
        </section>
      <% else %>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <%= for row <- @orgs do %>
            <.link
              navigate={~p"/organizations/#{row.org.slug}"}
              class="group block rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:shadow-card"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="flex min-w-0 items-center gap-2">
                  <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                    <.icon name="hero-building-office-2" class="size-4" />
                  </span>
                  <h3 class="truncate text-base font-semibold text-foreground transition group-hover:text-primary">
                    {row.org.name}
                  </h3>
                </div>
                <span class={[
                  "shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                  row.org.status == "active" && "bg-success/10 text-success ring-success/20",
                  row.org.status != "active" && "bg-muted text-muted-foreground ring-border"
                ]}>
                  {row.org.status}
                </span>
              </div>

              <p class="mt-3 font-mono text-xs text-muted-foreground">{row.org.slug}</p>

              <div class="mt-4 flex items-center justify-between border-t pt-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <.icon name="hero-users" class="size-3.5" />
                  <span>{row.member_count} {(row.member_count == 1 && "member") || "members"}</span>
                </div>
                <.role_badge role={row.role} />
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>

      <.create_modal :if={@show_create_modal} form={@form} local_mode={@local_mode} />
    </section>
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

  attr :role, :string, default: nil

  defp role_badge(%{role: nil} = assigns), do: ~H""

  defp role_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
      @role == "owner" && "bg-primary/10 text-primary ring-primary/20",
      @role == "admin" && "bg-info/10 text-info ring-info/20",
      @role in ["member", "viewer"] && "bg-muted text-muted-foreground ring-border"
    ]}>
      {@role}
    </span>
    """
  end
end
