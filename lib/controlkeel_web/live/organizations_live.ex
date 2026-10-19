defmodule ControlKeelWeb.OrganizationsLive do
  @moduledoc """
  `/organizations` — list organizations.

  Local mode (no user) shows every org in the DB. Cloud/self_hosted mode
  shows only orgs where the signed-in user has an active membership, with a
  role badge per row. Organization creation moved to `/new/org`
  (issue #277) — this page no longer hosts a create form.

  Switching orgs is URL-driven (`/:org_slug`) and happens through the org
  sidebar switcher; this page only highlights the derived default org.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Organizations")
      |> assign(:local_mode, Mode.current() == :local)

    {:ok, assign(socket, :orgs, list_orgs_for_socket(socket))}
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
  def render(assigns) do
    ~H"""
    <section class="w-full">
      <%= if @orgs == [] do %>
        <section class="rounded-2xl border bg-card p-12 text-center shadow-card">
          <.icon name="hero-building-office-2" class="mx-auto size-10 text-muted-foreground" />
          <p class="mt-4 text-base font-medium text-foreground">No organizations yet.</p>
          <%= if @local_mode do %>
            <p class="mt-1 text-sm text-muted-foreground">
              In local mode only the default organization is available.
            </p>
          <% else %>
            <p class="mt-1 text-sm text-muted-foreground">
              Organizations group workspaces, members, and budgets.
            </p>
            <.link
              navigate={~p"/new/org"}
              class="mt-4 inline-flex items-center rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
            >
              Create an organization
            </.link>
          <% end %>
        </section>
      <% else %>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <%= for row <- @orgs do %>
            <div class="group rounded-2xl border bg-card p-5 shadow-card transition hover:border-primary/40 hover:shadow-card">
              <div class="flex items-start justify-between gap-3">
                <.link
                  navigate={~p"/#{row.org.slug}"}
                  class="flex min-w-0 items-center gap-2"
                >
                  <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                    <.icon name="hero-building-office-2" class="size-4" />
                  </span>
                  <h3 class="truncate text-base font-semibold text-foreground transition group-hover:text-primary">
                    {row.org.name}
                  </h3>
                </.link>
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
                <div class="flex items-center gap-2">
                  <.role_badge role={row.role} />
                  <span
                    :if={not @local_mode and @current_org_id == row.org.id}
                    id={"org-active-#{row.org.id}"}
                    class="rounded-full bg-primary/15 px-2.5 py-1 text-xs font-semibold text-primary ring-1 ring-primary/30"
                  >
                    Active
                  </span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </section>
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
