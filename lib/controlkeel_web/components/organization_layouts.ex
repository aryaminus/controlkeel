defmodule ControlKeelWeb.OrganizationLayouts do
  @moduledoc """
  Framework layouts for organization-scoped pages.
  """

  use ControlKeelWeb, :html

  import ControlKeelWeb.Layouts, only: [dashboard_header: 1, flash_group: 1, user_menu: 1]

  embed_templates "organization_layouts/*"

  attr :current_user, :any, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: nil
  attr :nav_org, :map, required: true

  def organization_sidebar(assigns) do
    assigns =
      assigns
      |> assign_new(:mode, fn -> ControlKeel.Runtime.Mode.current() end)
      |> assign(:nav_items, organization_nav_items(assigns.nav_org))

    ~H"""
    <aside
      id="app-sidebar"
      class="hidden h-screen w-64 flex-col border-r bg-sidebar shadow-2xl shadow-black/30 lg:flex"
    >
      <.link navigate={~p"/dashboard"} class="flex items-center gap-3 px-3 pt-3 pb-2">
        <span class="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-lg shadow-primary/20">
          <.icon name="hero-bolt-solid" class="size-5" />
        </span>
        <span class="block text-sm font-semibold tracking-wide text-foreground">ControlKeel</span>
      </.link>

      <nav id="sidebar-org-nav" class="mt-2 flex flex-1 flex-col gap-1 px-3 text-sm">
        <div class="flex items-center gap-3 px-3 py-4 text-foreground">
          <.icon name="hero-building-office-2" class={organization_nav_icon_class(true)} />
          <span class="min-w-0 truncate text-sm text-foreground">
            {@nav_org.name}
          </span>
        </div>

        <%= for item <- @nav_items do %>
          <% active = organization_nav_active?(@current_path, @current_query, item) %>
          <.link
            navigate={item.href}
            aria-current={active && "page"}
            class={organization_nav_link_class(active)}
          >
            <.icon name={item.icon} class={organization_nav_icon_class(active)} /> {item.label}
          </.link>
        <% end %>
      </nav>

      <div class="flex flex-col justify-end border-t mt-2 px-3 py-2">
        <a
          href={~p"/getting-started"}
          target="_blank"
          rel="noopener"
          class="flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-book-open" class="size-4" /> Docs
        </a>
        <a
          href="https://github.com/aryaminus/controlkeel"
          target="_blank"
          rel="noopener"
          class="flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-code-bracket" class="size-4" /> GitHub
        </a>

        <.user_menu
          :if={@current_user != nil and @mode != :local}
          id="sidebar-user-menu"
          current_user={@current_user}
          class="mt-3 border-t pt-3"
          popover_class="bottom-20 right-4"
        />
      </div>
    </aside>
    """
  end

  defp organization_nav_items(org) do
    [
      %{
        label: "Overview",
        href: ~p"/#{org.slug}",
        tab: nil,
        icon: "hero-squares-2x2"
      },
      %{
        label: "Settings",
        href: ~p"/#{org.slug}/settings",
        tab: "settings",
        icon: "hero-cog-6-tooth"
      }
    ]
  end

  defp organization_nav_active?(current_path, current_query, item) do
    query_tab = current_query && URI.decode_query(current_query)["tab"]

    cond do
      item.tab == "settings" ->
        is_binary(current_path) && current_path == item.href

      item.tab == nil ->
        is_binary(current_path) && current_path == item.href && query_tab in [nil, "workspaces"]

      true ->
        query_tab == item.tab
    end
  end

  defp organization_nav_link_class(true) do
    "group flex items-center gap-3 rounded-xl bg-muted px-3 py-2.5 font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted"
  end

  defp organization_nav_link_class(false) do
    "group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
  end

  defp organization_nav_icon_class(true), do: "size-4 text-primary"

  defp organization_nav_icon_class(false),
    do: "size-4 text-muted-foreground group-hover:text-primary"
end
