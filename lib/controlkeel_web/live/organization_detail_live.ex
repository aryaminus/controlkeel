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
    local_mode = Mode.current() == :local
    workspaces = load_workspaces(org.id)

    recent_sessions =
      workspaces
      |> Enum.flat_map(fn ws -> Enum.map(ws.sessions, &%{session: &1, workspace: ws}) end)
      |> Enum.sort_by(& &1.session.inserted_at, {:desc, DateTime})
      |> Enum.take(5)

    pending_count =
      if local_mode do
        0
      else
        Accounts.list_memberships_for_org(org.id)
        |> Enum.count(&(&1.status == "pending"))
      end

    {:ok,
     socket
     |> assign(:page_title, "Organization Detail — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:budget_cents, Accounts.org_budget_cents(org) || 0)
     |> assign(:member_count, Accounts.count_memberships_for_org(org.id))
     |> assign(:pending_count, pending_count)
     |> assign(:can_manage, membership && Accounts.role_at_least?(membership.role, "admin"))
     |> assign(:active_tab, :overview)
     |> assign(:workspaces, workspaces)
     |> assign(
       :sessions_total,
       Enum.reduce(workspaces, 0, fn ws, acc -> acc + length(ws.sessions) end)
     )
     |> assign(:recent_sessions, recent_sessions)}
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
      <div class="flex gap-3">
        <div class="space-y-3">
          <div class="flex items-center gap-4">
            <.page_title title={@org.name} />
            <span class={[
              "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              @org.status == "active" && "bg-success/10 text-success ring-success/20",
              @org.status != "active" && "bg-muted text-muted-foreground ring-border"
            ]}>
              {@org.status}
            </span>
          </div>

          <p class="text-sm text-muted-foreground">
            Created {Calendar.strftime(@org.inserted_at, "%b %d, %Y")}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Workspaces</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{length(@workspaces)}</p>
          <p class="mt-1 text-xs text-muted-foreground">in this organization</p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Sessions</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@sessions_total}</p>
          <p class="mt-1 text-xs text-muted-foreground">across all workspaces</p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Members</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@member_count}</p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@pending_count} {if @pending_count == 1, do: "invite", else: "invites"} pending
          </p>
        </article>
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Monthly budget</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            <%= if @budget_cents > 0 do %>
              {"$#{Float.round(@budget_cents / 100, 2)}"}
            <% else %>
              <span class="text-muted-foreground">—</span>
            <% end %>
          </p>
          <p class="mt-1 font-mono text-xs text-muted-foreground">{@org.slug}</p>
        </article>
      </div>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="mb-3 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-foreground">Recent sessions</h2>
          </div>
          <%= if @recent_sessions == [] do %>
            <p class="py-6 text-center text-sm text-muted-foreground">No sessions yet.</p>
          <% else %>
            <ul class="divide-y divide-border">
              <%= for %{session: s, workspace: ws} <- @recent_sessions do %>
                <li>
                  <.link
                    navigate={~p"/sessions/#{s.id}"}
                    class="flex items-center justify-between gap-3 py-2.5 transition hover:bg-muted/40"
                  >
                    <p class="truncate text-sm font-medium text-foreground">{s.title}</p>
                    <p class="shrink-0 text-xs text-muted-foreground">{ws.name}</p>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section class="rounded-2xl border bg-card p-5 shadow-card">
          <div class="mb-3 flex items-center justify-between">
            <h2 class="text-sm font-semibold text-foreground">Top workspaces</h2>
            <.link
              navigate={~p"/organizations/#{@org.slug}/workspaces"}
              class="text-xs font-medium text-muted-foreground transition hover:text-foreground"
            >
              View all
            </.link>
          </div>
          <%= if @workspaces == [] do %>
            <p class="py-6 text-center text-sm text-muted-foreground">No workspaces yet.</p>
          <% else %>
            <ul class="divide-y divide-border">
              <%= for ws <- Enum.take(@workspaces, 5) do %>
                <li>
                  <.link
                    navigate={~p"/organizations/#{@org.slug}/workspaces/#{ws.id}"}
                    class="flex items-center justify-between gap-3 py-2.5 transition hover:bg-muted/40"
                  >
                    <p class="truncate text-sm font-medium text-foreground">{ws.name}</p>
                    <p class="shrink-0 text-xs text-muted-foreground">
                      {length(ws.sessions)} {if length(ws.sessions) == 1,
                        do: "session",
                        else: "sessions"}
                    </p>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>
      </div>

      <section class="flex flex-col gap-3 rounded-2xl border bg-card p-5 shadow-card sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 class="text-sm font-semibold text-foreground">Members</h2>
          <p class="mt-1 text-xs text-muted-foreground">
            {@member_count} {if @member_count == 1, do: "member", else: "members"} · {@pending_count} pending
          </p>
        </div>
        <.link
          navigate={~p"/organizations/#{@org.slug}/members"}
          class="inline-flex shrink-0 items-center gap-1.5 rounded-full border px-4 py-2 text-sm font-medium text-foreground transition hover:bg-muted"
        >
          Manage members
        </.link>
      </section>
    </section>
    """
  end

  defp load_workspaces(org_id) do
    Mission.list_workspaces_for_org(org_id)
    |> Repo.preload(:sessions)
  end

  defp redirect_with_flash(socket, kind, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, message)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
