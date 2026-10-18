defmodule ControlKeelWeb.NewOrgLive do
  @moduledoc """
  `/new/org` — standalone create-organization page.

  Mounted in the `:onboarding` live_session with the headless
  `SessionStartLayouts.session_start` layout (top bar + centered column). It
  mirrors the create form from the `/organizations` modal so the org switcher
  can send membered and memberless users straight here to create an
  additional organization. Save creates the org plus an owner membership for
  the current user (optionally with a starter workspace) and navigates to the
  new org.

  Local mode has no membership concept, so only the default organization
  exists there — the page shows an info panel instead of the form and save is
  denied.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create an organization")
     |> assign(:local_mode, Mode.current() == :local)
     |> assign(:show_back, has_org?(socket))
     |> assign_form(Org.changeset(%Org{}, %{}))}
  end

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    changeset =
      %Org{}
      |> Org.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{local_mode: true}} = socket) do
    {:noreply, local_mode_org_creation_denied(socket)}
  end

  def handle_event("save", %{"org" => params}, socket) do
    create_default_workspace? = Map.get(params, "create_default_workspace") == "true"

    case create_org(socket, params, create_default_workspace?) do
      {:ok, org, _created_workspace?} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization \"#{org.name}\" created.")
         |> push_navigate(to: ~p"/#{org.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :signed_out} ->
        {:noreply, put_flash(socket, :error, "Sign in to create an organization.")}

      {:error, :local_mode} ->
        {:noreply, local_mode_org_creation_denied(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto w-full max-w-lg space-y-6">
      <.page_title
        title="Create an organization"
        subtitle="Organizations group workspaces, members, budgets, and policies."
      />

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
          id="new-org-form"
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

          <div class="flex items-center justify-end pt-2">
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
    """
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :org))
  end

  # Back is only meaningful once the viewer belongs to an org: a memberless
  # first-run user has nowhere to go back to (the `/` handoff falls straight
  # back here), so the top bar renders it disabled. Local mode always has the
  # seeded default org.
  defp has_org?(socket) do
    if Mode.current() == :local do
      true
    else
      case socket.assigns[:current_user] do
        %{id: id} when is_integer(id) -> Accounts.any_active_membership?(id)
        _ -> false
      end
    end
  end

  defp create_org(socket, params, create_default_workspace?) do
    cond do
      Mode.current() == :local ->
        {:error, :local_mode}

      user = socket.assigns[:current_user] ->
        with {:ok, org} <- Accounts.create_org_with_owner(user.id, params) do
          {:ok, org, create_default_workspace? and create_default_workspace_for_org(org)}
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
    put_flash(
      socket,
      :error,
      "Organizations are not created in local mode — only the default organization is available. Upgrade to cloud mode to create organizations."
    )
  end
end
