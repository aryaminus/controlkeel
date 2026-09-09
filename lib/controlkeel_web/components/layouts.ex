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

  @doc """
  The dashboard sidebar: logo, primary nav, and external links.

  Renders a sign-out button at the bottom when a user is signed in and
  the app is running in cloud mode (not local).
  """
  attr :current_user, :any, default: nil
  attr :current_path, :string, default: nil
  attr :org, :any, default: nil
  attr :workspace, :any, default: nil
  attr :session, :any, default: nil
  attr :can_manage, :any, default: nil
  attr :local_mode, :boolean, default: false

  def sidebar(assigns) do
    assigns = assign_new(assigns, :mode, fn -> ControlKeel.Runtime.Mode.current() end)

    ~H"""
    <aside
      id="app-sidebar"
      class="hidden h-screen w-64 flex-col border-r bg-sidebar shadow-2xl shadow-black/30 lg:flex"
    >
      <.org_switcher current_user={@current_user} org={@org} />

      <.session_switcher
        :if={@session}
        org={@org}
        workspace={@workspace}
        session={@session}
        current_path={@current_path}
      />
      <.workspace_switcher
        :if={!@session && @workspace}
        org={@org}
        workspace={@workspace}
        current_path={@current_path}
      />

      <nav
        id="sidebar-nav"
        phx-hook="SidebarNav"
        class="mt-2 flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto px-3 overscroll-contain text-sm"
      >
        <%= for item <- sidebar_nav_items(assigns) do %>
          <% active =
            if item[:href],
              do: nav_active?(@current_path, item.href, Map.get(item, :exact, false)),
              else: false %>
          <% label_id = Phoenix.Naming.underscore(item.label) %>
          <%= cond do %>
            <% item[:children] -> %>
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
            <% item[:event] -> %>
              <button
                type="button"
                phx-click={item.event}
                class={sidebar_link_class(active)}
              >
                <.icon name={item.icon} class={sidebar_icon_class(active)} /> {item.label}
              </button>
            <% true -> %>
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

  @doc """
  Split context switchers sharing one trigger/popover shell:

  * `org_switcher/1` — dashboard header, org scope only.
  * `workspace_switcher/1` — sidebar on workspace pages.
  * `session_switcher/1` — sidebar on session pages.

  Popover open/close is pure client-side JS (toggle/click-away). The
  `ContextSwitcher` hook flies the popover out to the right when viewport
  space allows, otherwise it drops down below the button.
  """

  # Shared org lookup for the switchers: all active orgs in local mode,
  # the user's orgs in cloud mode.
  defp switcher_orgs(current_user) do
    user_id = if is_map(current_user), do: Map.get(current_user, :id), else: nil

    cond do
      ControlKeel.Runtime.Mode.current() == :local ->
        ControlKeel.Accounts.list_orgs(status: "active")

      not is_nil(user_id) ->
        ControlKeel.Accounts.list_orgs_for_user(user_id) |> Enum.map(& &1.org)

      true ->
        []
    end
  end

  @doc """
  Organization switcher merged into the sidebar branding block: the
  ControlKeel logo with the current org name as subtitle. Clicking
  toggles the flat org list popover. Without orgs it renders as a
  plain dashboard link.
  """
  attr :current_user, :any, default: nil
  attr :org, :any, default: nil

  def org_switcher(assigns) do
    assigns =
      assigns
      |> assign_new(:orgs, fn assigns -> switcher_orgs(assigns[:current_user]) end)
      |> assign(:switcher_title, switcher_title(assigns))

    ~H"""
    <div id="sidebar-org-switcher" phx-hook="ContextSwitcher" class="relative px-3 py-3">
      <div class="flex w-full items-center gap-3 text-left">
        <span class="flex size-8 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-lg shadow-primary/20">
          <.icon name="hero-bolt-solid" class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <span class="block text-sm font-semibold tracking-wide text-foreground">ControlKeel</span>
          <span :if={@org} class="block truncate text-xs text-muted-foreground">
            {@switcher_title}
          </span>
        </div>
        <button
          type="button"
          phx-click={
            JS.toggle(to: "#sidebar-org-switcher-popover")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          aria-haspopup="menu"
          aria-expanded="false"
        >
          <.icon name="hero-chevron-up-down" class="size-4 shrink-0" />
        </button>
      </div>
      <div
        id="sidebar-org-switcher-popover"
        data-context-switcher-popover
        phx-click-away={JS.hide(to: "#sidebar-org-switcher-popover")}
        class="hidden absolute left-3 top-full z-50 max-h-[28rem] w-72 overflow-y-auto rounded-xl border bg-card p-2 shadow-2xl shadow-black/50 backdrop-blur-md context-switcher-popover"
      >
        <%= for org <- @orgs do %>
          <% current? = is_map(@org) and Map.get(@org, :id) == org.id %>
          <.link
            navigate={~p"/organizations/#{org.slug}"}
            class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground transition hover:bg-muted"
          >
            <span class="min-w-0 flex-1 truncate">{org.name}</span>
            <.icon :if={current?} name="hero-check" class="size-4 shrink-0" />
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Workspace switcher for the sidebar on workspace pages: the current
  workspace name with a parent org back-row and a flat list of the
  org's workspaces.
  """
  attr :org, :any, default: nil
  attr :workspace, :any, default: nil
  attr :current_path, :string, default: nil

  def workspace_switcher(assigns) do
    assigns =
      assigns
      |> assign_new(:scope_workspaces, fn assigns ->
        case assigns[:org] do
          %{id: id} when not is_nil(id) ->
            ControlKeel.Mission.list_workspaces_for_org(id)

          _ ->
            []
        end
      end)
      |> assign(:switcher_title, switcher_title(assigns))
      |> assign(:switcher_parent, switcher_parent(assigns))
      |> assign(:org_slug, switcher_org_slug(assigns))

    ~H"""
    <.switcher_shell
      :if={@workspace != nil}
      id="sidebar-workspace-switcher"
      popover_id="sidebar-workspace-switcher-popover"
      container_class="relative px-3"
      inner_class="py-2"
      popover_class="left-3 top-full"
      title={@switcher_title}
      parent={@switcher_parent}
    >
      <%= if @scope_workspaces == [] or is_nil(@org_slug) do %>
        <p class="px-2 py-1.5 text-xs text-muted-foreground">No workspaces.</p>
      <% else %>
        <%= for ws <- @scope_workspaces do %>
          <% current? = is_map(@workspace) and Map.get(@workspace, :id) == ws.id %>
          <.link
            navigate={~p"/organizations/#{@org_slug}/workspaces/#{ws.id}"}
            class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-muted"
          >
            <span class="min-w-0 flex-1 truncate">{ws.name}</span>
            <.icon :if={current?} name="hero-check" class="size-4 shrink-0" />
          </.link>
        <% end %>
      <% end %>
    </.switcher_shell>
    """
  end

  @doc """
  Session switcher for the sidebar on session pages: the current session
  title with a parent workspace back-row and a flat list of the
  workspace's sessions, newest first.
  """
  attr :org, :any, default: nil
  attr :workspace, :any, default: nil
  attr :session, :any, default: nil
  attr :current_path, :string, default: nil

  def session_switcher(assigns) do
    assigns =
      assigns
      |> assign_new(:scope_workspace, &switcher_workspace/1)
      |> assign_new(:scope_sessions, fn assigns ->
        case assigns.scope_workspace do
          %{id: id} when not is_nil(id) ->
            ControlKeel.Mission.list_sessions_for_workspace(id)
            |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

          _ ->
            []
        end
      end)
      |> assign(:switcher_title, switcher_title(assigns))
      |> assign(:switcher_parent, switcher_parent(assigns))

    ~H"""
    <.switcher_shell
      :if={@session != nil}
      id="sidebar-session-switcher"
      popover_id="sidebar-session-switcher-popover"
      container_class="relative px-3"
      inner_class="py-2"
      popover_class="left-3 top-full"
      title={@switcher_title}
      parent={@switcher_parent}
    >
      <%= if @scope_sessions == [] do %>
        <p class="px-2 py-1.5 text-xs text-muted-foreground">No sessions.</p>
      <% else %>
        <%= for s <- @scope_sessions do %>
          <% current? = @current_path == "/sessions/#{s.id}" %>
          <.link
            navigate={~p"/sessions/#{s.id}"}
            class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-muted"
          >
            <span class="min-w-0 flex-1 truncate">{s.title}</span>
            <.icon :if={current?} name="hero-check" class="size-4 shrink-0" />
          </.link>
        <% end %>
      <% end %>
    </.switcher_shell>
    """
  end

  # Org slug for workspace overview links, nil-safe for partial assigns.
  defp switcher_org_slug(%{org: org}) when is_map(org), do: Map.get(org, :slug)
  defp switcher_org_slug(_), do: nil

  # Workspace in scope for the session switcher: the assigned workspace
  # when present, otherwise the session's own workspace.
  defp switcher_workspace(%{workspace: workspace}) when is_map(workspace), do: workspace

  defp switcher_workspace(%{session: session}) when is_map(session) do
    workspace = Map.get(session, :workspace)
    if is_map(workspace), do: workspace, else: nil
  end

  defp switcher_workspace(_), do: nil

  # Shared trigger + popover shell for the three switchers. The
  # `ContextSwitcher` hook flies the popover out to the right when viewport
  # space allows, otherwise it drops down below the button.
  attr :id, :string, required: true
  attr :popover_id, :string, required: true
  attr :container_class, :string, required: true
  attr :inner_class, :string, default: ""
  attr :popover_class, :string, required: true
  attr :title, :string, required: true
  attr :parent, :map, default: nil
  slot :inner_block, required: true

  defp switcher_shell(assigns) do
    ~H"""
    <div id={@id} phx-hook="ContextSwitcher" class={@container_class}>
      <div class={@inner_class}>
        <.link
          :if={@parent}
          navigate={@parent.path}
          aria-label={"Back to #{@parent.name}"}
          class="text-xs cursor-pointer flex items-center gap-3 px-3 py-2.5 font-medium text-muted-foreground transition hover:bg-muted rounded-xl"
        >
          <.icon name="hero-arrow-left" class="size-3 shrink-0" />
          <span class="truncate">{@parent.name}</span>
        </.link>
        <button
          type="button"
          data-context-switcher-toggle
          phx-click={
            JS.toggle(to: "##{@popover_id}")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          aria-haspopup="menu"
          aria-expanded="false"
          class="w-full text-left text-sm cursor-pointer flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-foreground ring-border transition hover:bg-muted"
        >
          <.icon name="hero-building-office-2" class={sidebar_icon_class(true)} />
          <span class="flex-1">{@title}</span>
          <span class="inline-flex shrink-0 text-muted-foreground">
            <.icon name="hero-chevron-up-down" class="size-4 shrink-0" />
          </span>
        </button>
      </div>
      <div
        id={@popover_id}
        data-context-switcher-popover
        phx-click-away={JS.hide(to: "##{@popover_id}")}
        class={[
          "hidden absolute z-50 max-h-[28rem] w-72 overflow-y-auto rounded-xl border bg-card p-2 shadow-2xl shadow-black/50 backdrop-blur-md context-switcher-popover",
          @popover_class
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Switcher button shows the deepest current context only:
  # session title > workspace name > org name, falling back to the
  # generic label (with org count) when no context is set.
  defp switcher_title(%{session: %{title: title}}) when is_binary(title) and title != "",
    do: title

  defp switcher_title(%{workspace: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp switcher_title(%{org: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp switcher_title(_), do: "Organizations"

  # Immediate parent scope for the trigger back-row: session scope shows
  # the workspace, workspace scope shows the org. Returns
  # %{name:, path:} or nil when the parent cannot be resolved.
  defp switcher_parent(assigns) do
    session_parent(assigns) || scope_parent(assigns)
  end

  defp session_parent(%{session: session}) when is_map(session) do
    workspace = Map.get(session, :workspace)

    if is_map(workspace) and is_binary(Map.get(workspace, :name)) and
         Map.get(workspace, :name) != "" do
      org = Map.get(workspace, :org)
      slug = if is_map(org), do: Map.get(org, :slug), else: nil

      if is_binary(slug) and slug != "" and not is_nil(Map.get(workspace, :id)) do
        %{
          name: Map.get(workspace, :name),
          path: "/organizations/#{slug}/workspaces/#{Map.get(workspace, :id)}"
        }
      end
    end
  end

  defp session_parent(_), do: nil

  defp scope_parent(%{workspace: workspace, org: org})
       when is_map(workspace) and is_map(org) do
    name = Map.get(org, :name)
    slug = Map.get(org, :slug)

    if is_binary(name) and name != "" and is_binary(slug) and slug != "" do
      %{name: name, path: "/organizations/#{slug}"}
    end
  end

  defp scope_parent(_), do: nil

  # Session pages (/sessions/:id*) set :session; MissionControl also sets
  # :workspace and :org for the context switcher, so the session branch must
  # match before the org/workspace branches.
  defp sidebar_nav_items(%{session: %{} = session} = assigns) do
    session_nav_items(session, assigns)
  end

  # Workspace pages set both :org and :workspace (WorkspaceDetail/Settings).
  defp sidebar_nav_items(%{org: %{}, workspace: %{} = ws} = assigns) do
    workspace_nav_items(ws, assigns)
  end

  defp sidebar_nav_items(%{org: %{} = org} = assigns) do
    org_nav_items(org, assigns)
  end

  defp sidebar_nav_items(_assigns), do: nav_items()

  # Session nav is intentionally minimal for now: Overview links back to
  # mission control. Sub-page items land as the session sidebar grows.
  defp session_nav_items(session, _assigns) do
    [
      %{
        label: "Overview",
        href: ~p"/sessions/#{session.id}",
        icon: "hero-squares-2x2",
        exact: true
      }
    ]
  end

  defp workspace_nav_items(workspace, _assigns) do
    org = workspace.org
    slug = org && org.slug

    if slug do
      [
        %{
          label: "Overview",
          href: ~p"/organizations/#{slug}/workspaces/#{workspace.id}",
          icon: "hero-squares-2x2",
          exact: true
        },
        %{
          label: "Settings",
          href: ~p"/organizations/#{slug}/workspaces/#{workspace.id}/settings",
          icon: "hero-cog-6-tooth",
          exact: true
        }
      ]
    else
      [
        %{label: "Overview", href: ~p"/organizations", icon: "hero-squares-2x2", exact: true}
      ]
    end
  end

  defp org_nav_items(org, _assigns) do
    [
      %{
        label: "Overview",
        href: ~p"/organizations/#{org.slug}",
        icon: "hero-squares-2x2",
        exact: true
      }
    ]
  end

  defp nav_items do
    [
      %{label: "Dashboard", href: ~p"/dashboard", icon: "hero-squares-2x2"},
      %{label: "Sessions", href: ~p"/sessions", icon: "hero-rocket-launch"},
      %{label: "Organizations", href: ~p"/organizations", icon: "hero-building-office-2"},
      %{label: "Skills", href: ~p"/skills", icon: "hero-puzzle-piece"},
      %{label: "Proofs", href: ~p"/proofs", icon: "hero-shield-check"},
      %{label: "Policy Studio", href: ~p"/policies", icon: "hero-adjustments-horizontal"},
      %{label: "Benchmarks", href: ~p"/benchmarks", icon: "hero-chart-bar-square"},
      %{label: "Findings", href: ~p"/findings", icon: "hero-exclamation-triangle"},
      %{
        label: "Observability",
        href: ~p"/observability",
        icon: "hero-signal",
        children: [
          %{group: "Workspace signals"},
          %{label: "Overview", href: ~p"/observability", icon: "hero-signal"},
          %{label: "Learning loop", href: ~p"/observability/loop", icon: "hero-arrow-path"},
          %{
            label: "Memory quality",
            href: ~p"/observability/memory-quality",
            icon: "hero-cpu-chip"
          },
          %{label: "Trends", href: ~p"/observability/trends", icon: "hero-arrow-trending-up"},
          %{
            label: "Problems",
            href: ~p"/observability/problems",
            icon: "hero-exclamation-triangle"
          },
          %{
            label: "Recommendations",
            href: ~p"/observability/recommendations",
            icon: "hero-light-bulb"
          },
          %{label: "Evals", href: ~p"/observability/evals", icon: "hero-chart-pie"},
          %{group: "Benchmarks"},
          %{
            label: "Drafts",
            href: ~p"/observability/benchmarks/drafts",
            icon: "hero-pencil-square"
          },
          %{
            label: "Scenarios",
            href: ~p"/observability/benchmarks/scenarios",
            icon: "hero-beaker"
          },
          %{label: "History", href: ~p"/observability/benchmarks/history", icon: "hero-clock"},
          %{
            label: "Regressions",
            href: ~p"/observability/regressions",
            icon: "hero-arrow-trending-down"
          },
          %{group: "Delivery & data"},
          %{label: "Costs", href: ~p"/observability/costs", icon: "hero-currency-dollar"},
          %{label: "Imports", href: ~p"/observability/imports", icon: "hero-arrow-down-tray"},
          %{label: "Compare", href: ~p"/observability/compare", icon: "hero-scale"},
          %{label: "Promotions", href: ~p"/observability/promotions", icon: "hero-trophy"}
        ]
      }
    ]
  end

  defp nav_active?(current_path, path, true) when is_binary(current_path) and is_binary(path) do
    current_path == path
  end

  defp nav_active?(current_path, path, false) when is_binary(current_path) and is_binary(path) do
    current_path == path or String.starts_with?(current_path, path <> "/")
  end

  defp nav_active?(_current_path, _path, _exact), do: false

  defp sidebar_link_class(true) do
    "group flex items-center gap-3 rounded-xl bg-muted px-3 py-2.5 font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted"
  end

  defp sidebar_link_class(false) do
    "group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
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
    "group flex items-center gap-2.5 rounded-lg bg-muted px-2.5 py-1.5 text-sm font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted"
  end

  defp subnav_link_class(false) do
    "group flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
  end

  defp subnav_icon_class(true), do: "size-3.5 shrink-0 text-primary"

  defp subnav_icon_class(false),
    do: "size-3.5 shrink-0 text-muted-foreground/70 group-hover:text-primary"

  attr :id, :string, required: true
  attr :current_user, :any, required: true
  attr :compact, :boolean, default: false
  attr :show_dashboard, :boolean, default: false
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
          "transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded",
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
        <%= if @show_dashboard do %>
          <a
            href={~p"/dashboard"}
            phx-click={
              JS.hide(to: "##{@id}-popover")
              |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} button")
            }
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
          </a>
        <% end %>
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

  @doc """
  Renders a breadcrumb trail derived from the current path.

  Automatically maps URL segments to human-readable labels.
  The root always shows a home icon linking to `/dashboard`.
  Intermediate segments are clickable links; the final segment is plain text.

  ## Examples

      <.dashboard_header
        current_path={@current_path}
        page_action={[
          %{to: "/sessions/start", label: "New session", icon: "hero-plus"}
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
              navigate={~p"/dashboard"}
              aria-label="Dashboard home"
              class="flex items-center gap-1 text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-sm"
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

  # Tab styling for the observability session layout (Overview / Timeline /
  # Memory / Export JSON).
  defp tab_class(path, current_path) do
    if path == current_path do
      "#{tab_base_class()} text-primary bg-[rgba(190,242,100,0.1)] border-primary"
    else
      tab_inactive_class()
    end
  end

  defp tab_inactive_class do
    "#{tab_base_class()} hover:text-primary bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)]"
  end

  defp tab_base_class do
    "text-sm font-medium transition-colors px-3 py-1.5 rounded-lg border"
  end
end
