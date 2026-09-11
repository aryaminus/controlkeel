defmodule ControlKeelWeb.OrganizationLayouts do
  @moduledoc """
  Framework layouts for organization-scoped pages.
  """

  use ControlKeelWeb, :html

  alias ControlKeel.Accounts

  embed_templates "organization_layouts/*"

  attr :current_user, :any, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: nil
  attr :nav_org, :map, required: true

  def organization_sidebar(assigns) do
    mode = ControlKeel.Runtime.Mode.current()

    assigns =
      assigns
      |> assign_new(:mode, fn -> mode end)
      |> assign(:nav_items, organization_nav_items(assigns.nav_org))
      |> assign_new(:user_orgs, fn ->
        case assigns[:current_user] do
          %{id: user_id} when is_integer(user_id) and mode != :local ->
            orgs =
              Accounts.list_orgs_for_user(user_id)
              |> Enum.map(& &1.org)

            if assigns[:nav_org] && not Enum.any?(orgs, &(&1.id == assigns.nav_org.id)) do
              [assigns.nav_org | orgs]
            else
              orgs
            end

          _ ->
            if assigns[:nav_org], do: [assigns.nav_org], else: []
        end
      end)

    ~H"""
    <aside
      id="app-sidebar"
      class="hidden h-screen w-64 flex-col border-r bg-sidebar shadow-2xl shadow-black/30 lg:flex"
    >
      <div class="p-3">
        <div
          id="sidebar-org-switcher"
          class={[
            "relative flex items-center gap-3 rounded-xl p-1.5",
            (@current_user != nil and @mode != :local) && "justify-between"
          ]}
          phx-click-away={
            JS.hide(to: "#sidebar-org-switcher-popover")
            |> JS.set_attribute({"aria-expanded", "false"}, to: "#org-switcher-button")
          }
        >
          <.link
            navigate={~p"/#{@nav_org.slug}"}
            aria-label={"#{@nav_org.name} home"}
            class="flex min-w-0 flex-1 items-center gap-3 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-lg shadow-primary/20">
              <.icon name="hero-bolt-solid" class="size-5" />
            </span>
            <div class="flex min-w-0 flex-col gap-0.5">
              <span class="block text-sm font-semibold tracking-wide text-foreground">
                ControlKeel
              </span>
              <span class="block truncate text-xs font-medium text-muted-foreground">
                {@nav_org.name}
              </span>
            </div>
          </.link>

          <button
            :if={@current_user != nil and @mode != :local}
            type="button"
            id="org-switcher-button"
            aria-label="Switch organization"
            aria-haspopup="menu"
            aria-expanded="false"
            aria-controls="sidebar-org-switcher-popover"
            phx-click={
              JS.toggle(to: "#sidebar-org-switcher-popover")
              |> JS.toggle_attribute({"aria-expanded", "true", "false"})
            }
            class="group rounded-lg p-1 transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <.icon
              name="hero-chevron-up-down"
              class="size-4 shrink-0 text-muted-foreground transition group-hover:text-foreground"
            />
          </button>

          <div
            :if={@current_user != nil and @mode != :local}
            id="sidebar-org-switcher-popover"
            class="hidden absolute left-0 right-0 top-full z-50 mt-1.5 rounded-xl border bg-card p-1.5 shadow-2xl shadow-black/50 backdrop-blur-md"
          >
            <div class="px-2.5 py-1.5 text-xs font-semibold text-muted-foreground">
              Organizations
            </div>
            <div class="max-h-60 space-y-0.5 overflow-y-auto">
              <%= for org <- @user_orgs do %>
                <% active = org.id == @nav_org.id %>
                <.link
                  navigate={~p"/#{org.slug}"}
                  phx-click={
                    JS.hide(to: "#sidebar-org-switcher-popover")
                    |> JS.set_attribute({"aria-expanded", "false"}, to: "#org-switcher-button")
                  }
                  class={[
                    "flex items-center justify-between gap-2 rounded-lg px-2.5 py-2 text-sm transition",
                    active && "bg-muted font-medium text-foreground",
                    !active && "text-muted-foreground hover:bg-muted hover:text-foreground"
                  ]}
                >
                  <div class="flex min-w-0 items-center gap-2">
                    <.icon
                      name="hero-building-office-2"
                      class="size-4 shrink-0 text-muted-foreground"
                    />
                    <span class="truncate">{org.name}</span>
                  </div>
                  <.icon :if={active} name="hero-check" class="size-4 shrink-0 text-primary" />
                </.link>
              <% end %>
            </div>

            <div class="my-1 border-t"></div>

            <.link
              navigate={~p"/organizations"}
              phx-click={
                JS.hide(to: "#sidebar-org-switcher-popover")
                |> JS.set_attribute({"aria-expanded", "false"}, to: "#org-switcher-button")
              }
              class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
            >
              <.icon name="hero-squares-2x2" class="size-3.5" /> All organizations
            </.link>
          </div>
        </div>
      </div>

      <nav id="sidebar-org-nav" class="mt-4 flex flex-1 flex-col gap-1 px-3 text-sm">
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

      <div
        :if={@mode == :local or @current_user == nil}
        class="flex flex-col justify-end border-t mt-2 px-3 py-2"
      >
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
      </div>

      <.user_menu
        :if={@current_user != nil and @mode != :local}
        id="sidebar-user-menu"
        current_user={@current_user}
        class="border-t p-3"
        popover_class="bottom-20 right-4"
      />
    </aside>
    """
  end

  attr :current_path, :string, default: nil
  attr :page_action, :any, default: nil

  attr :breadcrumbs, :list,
    default: nil,
    doc: """
    Explicit crumbs (`%{label: ..., to: ...}`, `to: nil` renders plain text).
    Overrides the path-derived trail — use when path segments are opaque ids
    or have no route.
    """

  def breadcrumbs_header(assigns) do
    actions =
      cond do
        is_nil(assigns.page_action) -> []
        is_list(assigns.page_action) -> assigns.page_action
        true -> [assigns.page_action]
      end

    assigns =
      assigns
      |> assign(:actions, actions)
      |> assign(:trail, breadcrumb_items(assigns))

    ~H"""
    <div class="flex w-full items-center justify-between border-b p-4">
      <nav :if={@current_path && @current_path != "/"} aria-label="Breadcrumb">
        <ol class="flex items-center gap-1.5 text-sm">
          <%= for {{label, path}, idx} <- Enum.with_index(@trail) do %>
            <li class="flex items-center gap-1.5">
              <.icon :if={idx > 0} name="hero-chevron-right" class="size-3 text-muted-foreground" />
              <%= if path do %>
                <.link
                  navigate={path}
                  class="text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-sm"
                >
                  {label}
                </.link>
              <% else %>
                <span class="font-medium text-muted-foreground">{label}</span>
              <% end %>
            </li>
          <% end %>
        </ol>
      </nav>
      <div :if={@actions != []} class="flex items-center gap-2" id="dashboard-page-action">
        <%= for action <- @actions do %>
          <a
            :if={action[:to]}
            href={action.to}
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </a>

          <button
            :if={action[:form]}
            type="submit"
            form={action.form}
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </button>

          <button
            :if={action[:event]}
            type="button"
            phx-click={action.event}
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  def breadcums_header(assigns), do: breadcrumbs_header(assigns)

  @label_map %{
    "dashboard" => "Dashboard",
    "sessions" => "Sessions",
    "findings" => "Findings",
    "benchmarks" => "Benchmarks",
    "proofs" => "Proofs",
    "reviews" => "Reviews",
    "organizations" => "Organizations",
    "workspaces" => "Workspaces",
    "policies" => "Policy Studio",
    "skills" => "Skills",
    "cloud" => "Cloud",
    "observability" => "Observability",
    "repos" => "Repos",
    "service-accounts" => "Service Accounts",
    "webhooks" => "Webhooks",
    "tool-policy" => "Tool Policy",
    "start" => "New Session",
    "runs" => "Runs",
    "telemetry" => "Telemetry",
    "projects" => "Projects",
    "settings" => "Settings"
  }

  defp breadcrumb_items(%{breadcrumbs: [_ | _] = crumbs}) do
    Enum.map(crumbs, fn
      %{label: label, to: to} -> {label, to}
      %{label: label} -> {label, nil}
    end)
  end

  defp breadcrumb_items(assigns) do
    Enum.map(breadcrumb_trail(assigns.current_path), fn
      {label, _path, true} -> {label, nil}
      {label, path, false} -> {label, path}
    end)
  end

  defp breadcrumb_trail(nil), do: []

  defp breadcrumb_trail(current_path) do
    segments = String.split(current_path, "/", trim: true)

    segments
    |> Enum.with_index()
    |> Enum.map(fn {segment, idx} ->
      path = "/" <> Enum.join(Enum.take(segments, idx + 1), "/")
      label = Map.get(@label_map, segment, segment_name(segment))
      is_final = idx == length(segments) - 1
      {label, path, is_final}
    end)
  end

  defp segment_name(segment) do
    segment
    |> String.replace("-", " ")
    |> title_case()
  end

  defp title_case(string) do
    string
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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

  # NOTE: `user_menu/1` and `flash_group/1` are intentionally duplicated here
  # (forked from `ControlKeelWeb.Layouts` on 2026-09-11) so organization pages
  # stay self-contained with no import from `Layouts`. Apply future fixes in
  # both modules.
  attr :id, :string, required: true
  attr :current_user, :any, required: true
  attr :compact, :boolean, default: false
  attr :show_dashboard, :boolean, default: false
  attr :class, :string, default: ""
  attr :popover_class, :string, default: "right-0 top-full mt-2"
  attr :rest, :global

  def user_menu(assigns) do
    ~H"""
    <div
      {@rest}
      class={"relative #{@class}"}
      id={@id}
      phx-click-away={
        JS.hide(to: "##{@id}-popover")
        |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} button")
      }
    >
      <%= if @compact do %>
        <button
          type="button"
          aria-label="User menu"
          aria-haspopup="menu"
          aria-expanded="false"
          aria-controls={"#{@id}-popover"}
          phx-click={
            JS.toggle(to: "##{@id}-popover")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{@id} button")
          }
          class="flex cursor-pointer size-9 shrink-0 items-center justify-center rounded-full bg-primary/20 px-1 py-1 text-sm font-semibold text-primary ring-1 ring-primary/30 transition hover:bg-primary/30 hover:ring-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
        >
          {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
        </button>
      <% else %>
        <div class="flex items-center gap-2 rounded-xl px-2 py-1.5">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/20 text-sm font-semibold text-primary ring-1 ring-primary/30">
            {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
          </span>

          <span class="min-w-0 flex-1 leading-tight">
            <span class="block truncate text-sm font-semibold text-foreground">
              {@current_user.name || @current_user.email}
            </span>
          </span>
          <button
            type="button"
            aria-label="User menu"
            aria-haspopup="menu"
            aria-expanded="false"
            aria-controls={"#{@id}-popover"}
            phx-click={
              JS.toggle(to: "##{@id}-popover")
              |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{@id} button")
            }
            class="flex size-8 shrink-0 cursor-pointer items-center justify-center rounded-lg text-muted-foreground transition hover:bg-background hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
          >
            <.icon name="hero-ellipsis-horizontal" class="size-4" />
          </button>
        </div>
      <% end %>

      <div
        id={"#{@id}-popover"}
        class={"hidden absolute #{@popover_class} z-50 w-56 rounded-xl border bg-card p-3 shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <p class="text-sm font-semibold text-foreground">
          {@current_user.name || @current_user.email}
        </p>
        <p class="mt-0.5 text-xs text-muted-foreground">{@current_user.email}</p>
        <div class="my-2 border-t"></div>
        <%= if @show_dashboard do %>
          <.link
            navigate={~p"/"}
            phx-click={
              JS.hide(to: "##{@id}-popover")
              |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} button")
            }
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-home" class="size-4" /> Home
          </.link>
        <% end %>

        <a
          href={~p"/getting-started"}
          target="_blank"
          rel="noopener"
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-book-open" class="size-4" /> Docs
        </a>

        <a
          href="https://github.com/aryaminus/controlkeel"
          target="_blank"
          rel="noopener"
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-code-bracket" class="size-4" /> GitHub
        </a>

        <div class="my-2 border-t"></div>

        <%!-- TODO: Settings button disabled — it was a no-op that only closed the
             popover. Re-enable and wire to a user settings modal/dialog when functional.
        <button
          type="button"
          phx-click={JS.hide(to: "##{@id}-popover")}
          class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
        </button>
         <hr class="my-2 border-t" />
        --%>
        <a
          href={~p"/auth/logout"}
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-[var(--ck-danger)]"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
