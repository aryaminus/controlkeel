defmodule ControlKeelWeb.OrganizationDetailLive do
  @moduledoc """
  Organization overview at `/organizations/:slug`.

  Shows org identity and aggregate stats only. Workspaces live at
  `/organizations/:slug/workspaces` (`OrganizationWorkspacesLive`) and
  member management at `/organizations/:slug/members`
  (`OrganizationMembersLive`).
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
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
     |> assign(:page_title, "Organization Detail — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, Mode.current() == :local)
     |> assign(:budget_cents, Accounts.org_budget_cents(org) || 0)
     |> assign(:member_count, Accounts.count_memberships_for_org(org.id))
     |> assign(:can_manage, membership && Accounts.role_at_least?(membership.role, "admin"))
     |> assign(:active_tab, :overview)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Legacy ?tab= URLs redirect to their canonical scoped routes.
    case params["tab"] do
      "members" ->
        {:noreply, push_patch(socket, to: ~p"/organizations/#{socket.assigns.org.slug}/members")}

      "workspaces" ->
        {:noreply,
         push_patch(socket, to: ~p"/organizations/#{socket.assigns.org.slug}/workspaces")}

      _ ->
        {:noreply, assign(socket, :active_tab, :overview)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-6">
      <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
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

          <%= if @local_mode do %>
            <p class="text-sm text-muted-foreground">
              View organization details below. Member management is unavailable in local mode.
            </p>
          <% else %>
            <p class="text-sm text-muted-foreground">
              Invite teammates, adjust roles, and keep ownership boundaries clear.
            </p>
          <% end %>
        </div>

        <div class="flex flex-wrap gap-x-8 gap-y-3">
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Slug
            </span>
            <span class="font-mono text-sm text-foreground">{@org.slug}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Members
            </span>
            <span class="text-sm font-semibold text-foreground">{@member_count}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Monthly budget
            </span>
            <span class="text-sm font-semibold text-foreground">
              <%= if @budget_cents > 0 do %>
                {"$#{Float.round(@budget_cents / 100, 2)}"}
              <% else %>
                <span class="text-muted-foreground">—</span>
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Created
            </span>
            <span class="text-sm text-foreground">
              {Calendar.strftime(@org.inserted_at, "%b %d, %Y")}
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp redirect_with_flash(socket, kind, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, message)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
