defmodule ControlKeelWeb.Layouts do
  @moduledoc """
  App layout templates, embedded via `embed_templates "layouts/*"`.

  - `:root` — the HTML skeleton (doctype/head/body), set via `put_root_layout`
    in the browser pipeline.
  - `:public` — marketing chrome (header/footer) for public pages, set per
    controller via `plug :put_layout` (see `PageController`).

  Framework layouts share the page's render context, so assigns like
  `@current_user`, `@flash`, and `@inner_content` are available here without
  any forwarding from callers.
  """

  use ControlKeelWeb, :html

  embed_templates "layouts/*"

  # Keyboard focus visibility for sidebar controls. The toggle buttons also
  # carry `aria-label="Toggle <label> menu"` so the icon-only chevrons
  # announce distinctly inside the nav loop.
  @focus_ring "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"

  @doc """
  The dashboard sidebar: logo, primary nav, and external links.

  Renders a sign-out button at the bottom when a user is signed in and
  the app is running in cloud mode (not local).
  """
  attr :current_user, :any, default: nil
  attr :current_path, :string, default: nil

  def sidebar(assigns) do
    assigns = assign_new(assigns, :mode, fn -> ControlKeel.Runtime.Mode.current() end)

    ~H"""
    <aside
      id="app-sidebar"
      class="hidden h-screen w-64 flex-col border-r bg-sidebar shadow-2xl shadow-black/30 lg:flex"
    >
      <.link navigate={~p"/"} class="flex items-center gap-3 px-3 py-4">
        <span class="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-lg shadow-primary/20">
          <.icon name="hero-bolt-solid" class="size-5" />
        </span>
        <span>
          <span class="block text-sm font-semibold tracking-wide text-foreground">ControlKeel</span>
          <span class="block text-xs text-muted-foreground">Governance memory</span>
        </span>
      </.link>

      <nav
        id="sidebar-nav"
        phx-hook="SidebarNav"
        class="mt-2 flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto px-3 overscroll-contain text-sm"
      >
        <%= for item <- nav_items() do %>
          <% active = nav_active?(@current_path, item.href) %>
          <% label_id = Phoenix.Naming.underscore(item.label) %>
          <%= if item[:children] do %>
            <% opened = active %>
            <% collapse_id = "sidebar-collapse-#{label_id}" %>
            <% chevron_id = "sidebar-chevron-#{label_id}" %>
            <div class="flex flex-col gap-1">
              <button
                type="button"
                id={"sidebar-toggle-#{label_id}"}
                data-sidebar-toggle
                aria-expanded={(opened && "true") || "false"}
                aria-controls={collapse_id}
                aria-label={"Toggle #{item.label} menu"}
                class={["w-full text-left cursor-pointer", sidebar_link_class(active)]}
              >
                <.icon name={item.icon} class={sidebar_icon_class(active)} />
                <span class="flex-1">{item.label}</span>
                <span
                  id={chevron_id}
                  class={[
                    "inline-flex shrink-0 transition-transform duration-200 text-muted-foreground",
                    opened && "rotate-90"
                  ]}
                >
                  <.icon name="hero-chevron-right" class="size-4 shrink-0" />
                </span>
              </button>
              <div id={collapse_id} class={unless opened, do: "hidden"}>
                <.sidebar_children
                  children={item.children}
                  current_path={@current_path}
                  parent_href={item.href}
                />
              </div>
            </div>
          <% else %>
            <.link
              navigate={item.href}
              aria-current={active && "page"}
              class={sidebar_link_class(active)}
            >
              <.icon name={item.icon} class={sidebar_icon_class(active)} /> {item.label}
            </.link>
          <% end %>
        <% end %>
      </nav>

      <div class="flex flex-col gap-1 border-t mt-2 px-3 py-2">
        <a
          href={~p"/docs"}
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

  # Intentionally empty: the last global surface (Benchmarks) moved to the
  # workspace scope (/:org_slug/workspaces/:ws_slug/benchmarks). Kept as a
  # seam in case a global page ever returns; the nav element still renders
  # (Docs/GitHub/user menu live below it).
  defp nav_items, do: []

  defp nav_active?(current_path, path, exact \\ false)

  defp nav_active?(current_path, path, true) when is_binary(current_path) and is_binary(path) do
    current_path == path
  end

  defp nav_active?(current_path, path, false) when is_binary(current_path) and is_binary(path) do
    current_path == path or String.starts_with?(current_path, path <> "/")
  end

  defp nav_active?(_current_path, _path, _exact), do: false

  defp sidebar_link_class(true) do
    "group flex items-center gap-3 rounded-xl bg-muted px-3 py-2.5 font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted #{@focus_ring}"
  end

  defp sidebar_link_class(false) do
    "group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground #{@focus_ring}"
  end

  defp sidebar_icon_class(true), do: "size-4 text-primary"
  defp sidebar_icon_class(false), do: "size-4 text-muted-foreground group-hover:text-primary"

  attr :children, :list, required: true
  attr :current_path, :string, default: nil
  attr :parent_href, :string, required: true

  def sidebar_children(assigns) do
    ~H"""
    <div data-sidebar-subnav class="mt-1 flex flex-col gap-0.5 pl-4 border-l border-border ml-4">
      <%= for child <- @children do %>
        <%= if child[:group] do %>
          <p class="px-2 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
            {child.group}
          </p>
        <% else %>
          <% active = nav_active?(@current_path, child.href, child.href == @parent_href) %>
          <.link
            navigate={child.href}
            aria-current={active && "page"}
            class={subnav_link_class(active)}
          >
            <.icon name={child.icon} class={subnav_icon_class(active)} /> {child.label}
          </.link>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp subnav_link_class(true) do
    "group flex items-center gap-2.5 rounded-lg bg-muted px-2.5 py-1.5 text-sm font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted #{@focus_ring}"
  end

  defp subnav_link_class(false) do
    "group flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground #{@focus_ring}"
  end

  defp subnav_icon_class(true), do: "size-3.5 shrink-0 text-primary"

  defp subnav_icon_class(false),
    do: "size-3.5 shrink-0 text-muted-foreground/70 group-hover:text-primary"

  attr :id, :string, required: true
  attr :current_user, :any, required: true
  attr :compact, :boolean, default: false
  attr :class, :string, default: ""
  attr :popover_class, :string, default: "right-0 top-full mt-2"
  attr :rest, :global

  def user_menu(assigns) do
    ~H"""
    <div {@rest} class={"relative #{@class}"} id={@id}>
      <button
        type="button"
        phx-click={
          JS.toggle(to: "##{@id}-popover")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-haspopup="menu"
        aria-expanded="false"
        aria-label="User menu"
        class={[
          "transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded",
          if(@compact,
            do:
              "flex items-center gap-2 rounded-full px-1 py-1 text-sm font-semibold text-muted-foreground hover:text-foreground",
            else: "flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left"
          )
        ]}
      >
        <span class={[
          "flex shrink-0 items-center justify-center rounded-full bg-primary/20 font-semibold text-primary",
          if(@compact, do: "size-8", else: "size-8 text-sm ring-1 ring-primary/30")
        ]}>
          {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
        </span>
        <%= unless @compact do %>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-foreground">
              {@current_user.name || @current_user.email}
            </span>
          </span>
          <.icon name="hero-chevron-down" class="size-4 shrink-0 text-muted-foreground" />
        <% end %>
      </button>
      <div
        id={"#{@id}-popover"}
        phx-click-away={
          JS.hide(to: "##{@id}-popover")
          |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} button")
        }
        class={"hidden absolute #{@popover_class} z-50 w-56 rounded-xl border bg-card p-3 shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <p class="text-sm font-semibold text-foreground">
          {@current_user.name || @current_user.email}
        </p>
        <p class="mt-0.5 text-xs text-muted-foreground">{@current_user.email}</p>
        <div class="my-2 border-t"></div>
        <%!-- Settings opens the account dialog (Art.15 export + Art.17 erasure,
             docs/dsar-erasure-plan.md Slice 3). Cloud UI only — the menu is
             hidden in local mode. --%>
        <button
          type="button"
          phx-click={
            JS.hide(to: "##{@id}-popover")
            |> JS.show(to: "##{@id}-account-dialog", display: "block")
          }
          class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
        </button>
        <hr class="my-2 border-t" />
        <a
          href={~p"/auth/logout"}
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-[var(--ck-danger)]"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
        </a>
      </div>

      <.account_dialog id={"#{@id}-account-dialog"} user={@current_user} />
    </div>
    """
  end

  @doc """
  Account settings dialog (docs/dsar-erasure-plan.md, Slice 3): Art.15 data
  export + Art.17 erasure, opened from the user menu's Settings entry.

  Sidebar-over-content layout (mirrors the org settings tabs) so more
  sections can slot in later. Section switching is pure client-side
  `JS.show`/`JS.hide` — no LiveView events, so it works over any page's
  layout. Erasure posts to `AccountController.erase/2`; export links to
  `AccountController.export_data/2`. Rendered only in cloud mode (the user
  menu is hidden locally); the controller and `RequireCloudMode` enforce
  cloud-onlyness server-side.

  Adding a section: append a nav button (unique `*-nav-*` id) and a panel
  (unique `*-panel-*` id), and extend each button's toggle chain to show
  its own panel and hide the others.
  """
  attr :id, :string, required: true
  attr :user, :any, required: true

  def account_dialog(assigns) do
    assigns = assign(assigns, :erase_form, to_form(%{"confirm_email" => ""}, as: :erase))

    ~H"""
    <div
      id={@id}
      class="hidden relative z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click={JS.hide(to: "##{@id}")}
        aria-label="Close account settings dialog"
      />

      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="w-full max-w-2xl overflow-hidden rounded-2xl border bg-card/95 shadow-card">
            <div class="flex items-start justify-between gap-4 border-b border-border/60 px-6 py-4">
              <div>
                <h2 id={"#{@id}-title"} class="text-lg font-semibold text-foreground">
                  Account settings
                </h2>
                <p class="mt-1 text-sm text-muted-foreground">
                  Signed in as <strong class="text-foreground">{@user.email}</strong>
                </p>
              </div>
              <button
                type="button"
                phx-click={JS.hide(to: "##{@id}")}
                aria-label="Close"
                class="rounded-lg p-1.5 text-muted-foreground transition hover:bg-muted hover:text-foreground"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="grid sm:grid-cols-[190px_minmax(0,1fr)]">
              <nav
                aria-label="Account settings sections"
                class="flex gap-1 overflow-x-auto border-b border-border/60 p-2 sm:flex-col sm:border-b-0 sm:border-r sm:p-3"
              >
                <button
                  id={"#{@id}-nav-data"}
                  type="button"
                  aria-current="true"
                  phx-click={
                    JS.set_attribute({"aria-current", "true"}, to: "##{@id}-nav-data")
                    |> JS.remove_attribute("aria-current", to: "##{@id}-nav-danger")
                    |> JS.show(to: "##{@id}-panel-data")
                    |> JS.hide(to: "##{@id}-panel-danger")
                  }
                  class="flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground aria-[current=true]:bg-primary/10 aria-[current=true]:font-semibold aria-[current=true]:text-primary"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> My data
                </button>
                <button
                  id={"#{@id}-nav-danger"}
                  type="button"
                  phx-click={
                    JS.set_attribute({"aria-current", "true"}, to: "##{@id}-nav-danger")
                    |> JS.remove_attribute("aria-current", to: "##{@id}-nav-data")
                    |> JS.show(to: "##{@id}-panel-danger")
                    |> JS.hide(to: "##{@id}-panel-data")
                  }
                  class="flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground aria-[current=true]:bg-[var(--ck-danger)]/10 aria-[current=true]:font-semibold aria-[current=true]:text-[var(--ck-danger)]"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4" /> Danger zone
                </button>
              </nav>

              <div class="p-6">
                <div id={"#{@id}-panel-data"} role="tabpanel" aria-labelledby={"#{@id}-nav-data"}>
                  <.card_title>Download my data</.card_title>
                  <p class="mt-2 text-sm text-muted-foreground">
                    A JSON export of everything ControlKeel holds about your
                    account: your profile, your organization memberships, and
                    the audit trail that references you.
                  </p>
                  <a
                    href={~p"/me/export.json"}
                    class="mt-4 inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-4" /> Download JSON
                  </a>
                </div>

                <div
                  id={"#{@id}-panel-danger"}
                  role="tabpanel"
                  aria-labelledby={"#{@id}-nav-danger"}
                  class="hidden"
                >
                  <div class="rounded-xl border border-[var(--ck-danger)]/30 bg-[var(--ck-danger)]/5 p-4">
                    <p class="text-sm text-foreground">
                      <strong>Erasing your account is permanent.</strong> Your
                      account and memberships are deleted immediately. Audit
                      records survive with your identity replaced by a
                      non-reversible marker, and your organizations'
                      governance data is untouched. Service accounts you
                      created are revoked.
                    </p>
                    <p class="mt-2 text-sm text-muted-foreground">
                      If you are the last active owner of an organization,
                      erasure is refused — promote another owner or delete the
                      organization first.
                    </p>
                  </div>

                  <.form
                    id={"#{@id}-erase-form"}
                    for={@erase_form}
                    action={~p"/me/erase"}
                    method="post"
                    class="mt-4"
                  >
                    <.input
                      field={@erase_form[:confirm_email]}
                      label="Type your email to confirm erasure"
                      autocomplete="off"
                    />
                    <div class="mt-3">
                      <button
                        type="submit"
                        id={"#{@id}-erase-button"}
                        class="rounded-full bg-[var(--ck-danger)] px-4 py-2 text-sm font-medium text-white transition hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ck-danger)]"
                      >
                        Erase my account
                      </button>
                    </div>
                  </.form>
                </div>
              </div>
            </div>
          </div>
        </div>
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

  @doc """
  Renders a breadcrumb trail derived from the current path.

  Automatically maps URL segments to human-readable labels.
  The root always shows a home icon linking to `/`.
  Intermediate segments are clickable links; the final segment is plain text.

  ## Examples

      <.dashboard_header
        current_path={@current_path}
        page_action={[
          %{to: "/new/session", label: "New session", icon: "hero-plus"}
        ]}
      />
  """
  attr :current_path, :string, default: nil
  attr :page_action, :any, default: nil

  attr :breadcrumbs, :list,
    default: nil,
    doc: """
    Explicit crumbs (`%{label: ..., to: ...}`, `to: nil` renders plain text).
    Overrides the path-derived trail — use when path segments are opaque ids
    or have no route.
    """

  def dashboard_header(assigns) do
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
          <li>
            <.link
              navigate={~p"/"}
              aria-label="Home"
              class="flex items-center gap-1 text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm"
            >
              <.icon name="hero-home" class="size-3.5" />
            </.link>
          </li>
          <%= for {label, path} <- @trail do %>
            <li class="flex items-center gap-1.5">
              <.icon name="hero-chevron-right" class="size-3 text-muted-foreground" />
              <%= if path do %>
                <.link
                  navigate={path}
                  class="text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm"
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
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </a>

          <button
            :if={action[:form]}
            type="submit"
            form={action.form}
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </button>

          <button
            :if={action[:event]}
            type="button"
            phx-click={action.event}
            class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <.icon :if={action[:icon]} name={action.icon} class="size-4" /> {action.label}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @label_map %{
    "sessions" => "Sessions",
    "findings" => "Findings",
    "benchmarks" => "Benchmarks",
    "proofs" => "Proofs",
    "reviews" => "Reviews",
    "organizations" => "Organizations",
    "workspaces" => "Workspaces",
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
    "projects" => "Projects"
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
end
