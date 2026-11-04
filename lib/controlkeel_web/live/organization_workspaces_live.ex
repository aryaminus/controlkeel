defmodule ControlKeelWeb.OrganizationWorkspacesLive do
  @moduledoc """
  Organization workspace index at `/:org_slug/workspaces`.
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
        {:ok,
         socket
         |> assign(:page_title, "Workspaces — #{org.name}")
         |> assign(:org, org)
         |> assign(:nav_org, org)
         |> assign(:current_membership, membership)
         |> assign(:workspaces, load_workspaces(org.id))
         |> assign(:local_mode, Mode.current() == :local)
         |> assign(:show_new_workspace, false)
         |> assign(:new_workspace_error, nil)
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
         )}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page_title, error.title)
         |> assign(:scope_error, error)}
    end
  end

  @impl true
  def handle_params(%{"org_slug" => slug}, _uri, socket) do
    socket =
      case socket.assigns[:org] do
        %{slug: ^slug} ->
          socket

        _ ->
          case OrgAccess.resolve(slug, socket.assigns[:current_user]) do
            {:ok, org, membership} ->
              {:ok, socket} =
                {:ok,
                 socket
                 |> assign(:org, org)
                 |> assign(:nav_org, org)
                 |> assign(:current_membership, membership)
                 |> assign(:workspaces, load_workspaces(org.id))
                 |> assign(:local_mode, Mode.current() == :local)
                 |> assign(:show_new_workspace, false)
                 |> assign(:new_workspace_error, nil)
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
                 )}

              assign(socket, :scope_error, nil)

            {:error, error} ->
              assign(socket, :scope_error, error)
          end
      end

    {:noreply, socket}
  end

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
    cond do
      socket.assigns.local_mode ->
        {:noreply,
         socket
         |> assign(:show_new_workspace, false)
         |> put_flash(
           :error,
           "Only the default workspace is available in local mode. Upgrade to cloud mode to create additional workspaces."
         )}

      not can_manage?(socket.assigns) ->
        {:noreply, put_flash(socket, :error, "You don't have permission to create workspaces.")}

      true ->
        org = socket.assigns.org

        params =
          params
          |> Map.put("slug", resolve_workspace_slug(params))
          |> Map.put("org_id", org.id)

        case create_workspace(params) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:show_new_workspace, false)
             |> assign(:new_workspace_error, nil)
             |> assign(:workspaces, load_workspaces(org.id))
             |> put_flash(:info, "Workspace #{workspace.name} created.")}

          {:error, %Ecto.Changeset{} = changeset} ->
            message =
              changeset.errors
              |> Enum.map_join(", ", fn {field, {error, _}} -> "#{field}: #{error}" end)

            {:noreply, assign(socket, :new_workspace_error, message)}

          {:error, reason} ->
            {:noreply, assign(socket, :new_workspace_error, inspect(reason))}
        end
    end
  end

  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <div class="flex items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Workspaces
          </h1>
          <p class="mt-2 text-sm text-muted-foreground">
            Workspaces group sessions, findings, and budgets under {@org.name}.
          </p>
        </div>
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
            Workspaces created for this organization will appear here.
          </p>
        </section>
      <% else %>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <%= for workspace <- @workspaces do %>
            <.link
              navigate={~p"/#{@org.slug}/workspace/#{workspace.slug}"}
              class="group block rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:shadow-card"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="flex min-w-0 items-center gap-2">
                  <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-info/10 text-info">
                    <.icon name="hero-squares-2x2" class="size-4" />
                  </span>
                  <h2 class="truncate text-base font-semibold text-foreground transition group-hover:text-primary">
                    {workspace.name}
                  </h2>
                </div>
                <span class={[
                  "shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                  workspace.status == "active" && "bg-success/10 text-success ring-success/20",
                  workspace.status != "active" && "bg-muted text-muted-foreground ring-border"
                ]}>
                  {workspace.status}
                </span>
              </div>
              <p class="mt-1 truncate font-mono text-xs text-muted-foreground">
                {workspace.slug}
              </p>
              <dl class="mt-4 grid grid-cols-2 gap-3 border-t pt-4">
                <div>
                  <dt class="text-xs font-medium text-muted-foreground">Sessions</dt>
                  <dd class="mt-1 text-lg font-semibold text-foreground/90">
                    {length(workspace.sessions)}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-medium text-muted-foreground">Budget</dt>
                  <dd class="mt-1 text-lg font-semibold text-foreground/90">
                    {format_budget(workspace.budget_cents)}
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
              <.input field={@form[:name]} type="text" label="Workspace name" required />
              <.input
                field={@form[:slug]}
                type="text"
                label="Slug"
                placeholder="Auto-generated from name"
              />
              <.input
                field={@form[:industry]}
                type="select"
                label="Industry"
                options={industry_options()}
              />
              <.input
                field={@form[:budget_cents]}
                type="number"
                label="Monthly budget (cents)"
                min="0"
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
    org_id
    |> Mission.list_workspaces_for_org()
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

  defp can_manage?(assigns) do
    case assigns.current_membership do
      %{role: role} -> Accounts.role_at_least?(role || "", "admin")
      _ -> false
    end
  end

  defp format_budget(cents) when is_integer(cents) and cents > 0 do
    "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end

  defp format_budget(_cents), do: "No budget"
end
