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
  attr :nav_workspace, :any, default: nil
  attr :nav_session, :any, default: nil

  def organization_sidebar(assigns) do
    mode = ControlKeel.Runtime.Mode.current()

    assigns =
      assigns
      |> assign_new(:mode, fn -> mode end)
      |> assign(:nav_items, sidebar_nav_items(assigns))
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
          </div>
        </div>
      </div>

      <nav id="sidebar-org-nav" class="mt-4 flex flex-1 flex-col gap-1 px-3 text-sm">
        <%= for item <- @nav_items do %>
          <% active = sidebar_item_active?(@current_path, @current_query, item) %>
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

  attr :nav_org_admin?, :boolean,
    default: false,
    doc: """
    Whether the viewer is admin/owner of nav_org (memoized by
    OrganizationLayoutDefaults). Gates org/workspace slug params on the
    layout-level "New Session" action (issue #183).
    """

  attr :breadcrumbs, :list,
    default: nil,
    doc: """
    Explicit crumbs (`%{label: ..., to: ...}`, `to: nil` renders plain text).
    Overrides the path-derived trail — use when path segments are opaque ids
    or have no route.
    """

  attr :nav_org, :any, default: nil
  attr :nav_workspace, :any, default: nil
  attr :nav_session, :any, default: nil
  attr :sibling_workspaces, :list, default: []
  attr :sibling_sessions, :list, default: []
  attr :current_query, :any, default: nil

  def breadcrumbs_header(assigns) do
    trail = breadcrumb_items(assigns)
    workspace_root = workspace_root_path(assigns[:nav_org], assigns[:nav_workspace])
    workspace_idx = workspace_crumb_index(trail, workspace_root, assigns[:current_path])
    siblings = assigns[:sibling_workspaces] || []

    session_root =
      session_root_path(assigns[:nav_org], assigns[:nav_workspace], assigns[:nav_session])

    session_idx = session_crumb_index(trail, session_root, assigns[:current_path])
    session_siblings = assigns[:sibling_sessions] || []

    show_ws_switcher = !is_nil(workspace_idx) and length(siblings) > 1
    show_session_switcher = !is_nil(session_idx) and length(session_siblings) > 1

    current_path = assigns[:current_path]
    current_query = assigns[:current_query]
    org_slug = assigns[:nav_org] && assigns.nav_org.slug
    ws_slug = assigns[:nav_workspace] && assigns.nav_workspace.slug

    ws_items =
      if show_ws_switcher do
        Enum.map(siblings, fn ws ->
          %{
            label: ws.name,
            href: sibling_workspace_path(current_path, current_query, org_slug, ws.slug),
            active: ws.slug == ws_slug
          }
        end)
      else
        []
      end

    session_items =
      if show_session_switcher do
        Enum.map(session_siblings, fn sess ->
          %{
            label: sess.title,
            href: sibling_session_path(current_path, current_query, org_slug, ws_slug, sess.id),
            active: sess.id == assigns.nav_session.id
          }
        end)
      else
        []
      end

    assigns =
      assigns
      |> assign(:trail, trail)
      |> assign(:workspace_idx, workspace_idx)
      |> assign(:show_ws_switcher, show_ws_switcher)
      |> assign(:ws_items, ws_items)
      |> assign(:session_idx, session_idx)
      |> assign(:show_session_switcher, show_session_switcher)
      |> assign(:session_items, session_items)

    ~H"""
    <div class="flex min-h-[68px] w-full items-center justify-between border-b p-4">
      <nav :if={@current_path && @current_path != "/"} aria-label="Breadcrumb">
        <ol class="flex items-center gap-1.5 text-sm">
          <li>
            <.link
              href={~p"/"}
              aria-label="Home"
              class="flex items-center gap-1 text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-sm"
            >
              <.icon name="hero-home" class="size-3.5" />
            </.link>
          </li>
          <%= for {{label, path}, idx} <- Enum.with_index(@trail) do %>
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
                <span class="font-medium text-foreground">{label}</span>
              <% end %>
              <.breadcrumb_switcher
                :if={@show_ws_switcher and idx == @workspace_idx}
                id="breadcrumb-ws-switcher"
                label="Switch workspace"
                title="Workspaces"
                items={@ws_items}
              />
              <.breadcrumb_switcher
                :if={@show_session_switcher and idx == @session_idx}
                id="breadcrumb-session-switcher"
                label="Switch session"
                title="Sessions"
                items={@session_items}
                popover_width="w-64"
              />
            </li>
          <% end %>
        </ol>
      </nav>
      <div class="flex items-center gap-2" id="organization-page-action">
        <.link
          href={new_session_path(assigns)}
          class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90 cursor-pointer"
        >
          <.icon name="hero-plus" class="size-4" /> New Session
        </.link>
      </div>
    </div>
    """
  end

  # Slug params are attached only when the viewer is admin/owner of nav_org
  # (issue #183); OnboardingLive re-validates anything it receives. Local
  # mode and lower roles get the bare launcher URL.
  defp new_session_path(
         %{nav_org: %{slug: org_slug}, nav_workspace: %{slug: ws_slug}, nav_org_admin?: true} =
           _assigns
       ),
       do: ~p"/sessions/start?#{%{org_slug: org_slug, ws_slug: ws_slug}}"

  defp new_session_path(%{nav_org: %{slug: org_slug}, nav_org_admin?: true} = _assigns),
    do: ~p"/sessions/start?#{%{org_slug: org_slug}}"

  defp new_session_path(_assigns), do: ~p"/sessions/start"

  attr :id, :string, required: true, doc: "base id; button/popover derive from it"
  attr :label, :string, required: true, doc: "aria-label for the toggle button"
  attr :title, :string, required: true, doc: "popover heading"
  attr :items, :list, required: true, doc: "prebuilt [%{label, href, active}] entries"
  attr :popover_width, :string, default: "w-56"

  defp breadcrumb_switcher(assigns) do
    ~H"""
    <div
      class="relative flex items-center"
      phx-click-away={
        JS.hide(to: "##{@id}-popover")
        |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id}-button")
      }
    >
      <button
        type="button"
        id={"#{@id}-button"}
        aria-label={@label}
        aria-haspopup="menu"
        aria-expanded="false"
        phx-click={
          JS.toggle(to: "##{@id}-popover")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        class="rounded p-0.5 text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name="hero-chevron-up-down" class="size-3.5" />
      </button>
      <div
        id={"#{@id}-popover"}
        class={"hidden absolute left-0 top-full z-50 mt-1.5 #{@popover_width} rounded-xl border bg-card p-1.5 shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <div class="px-2.5 py-1.5 text-xs font-semibold text-muted-foreground">
          {@title}
        </div>
        <div class="max-h-60 space-y-0.5 overflow-y-auto">
          <%= for item <- @items do %>
            <.link
              href={item.href}
              phx-click={
                JS.hide(to: "##{@id}-popover")
                |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id}-button")
              }
              class={[
                "flex items-center justify-between gap-2 rounded-lg px-2.5 py-2 text-sm transition",
                item.active && "bg-muted font-medium text-foreground",
                !item.active && "text-muted-foreground hover:bg-muted hover:text-foreground"
              ]}
            >
              <span class="truncate">{item.label}</span>
              <.icon
                :if={item.active}
                name="hero-check"
                class="size-4 shrink-0 text-primary"
              />
            </.link>
          <% end %>
        </div>
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

  defp workspace_root_path(%{slug: org_slug}, %{slug: ws_slug}),
    do: "/#{org_slug}/workspaces/#{ws_slug}"

  defp workspace_root_path(_, _), do: nil

  # The workspace crumb is the linked workspace root on subpages. On the
  # workspace overview page the trail ends with the workspace name as
  # plain text, so fall back to the final crumb — but only while standing
  # on the workspace root. A trailing plain-text crumb on any other path
  # is a subpage label and must never capture the switcher.
  defp workspace_crumb_index(_trail, nil, _current_path), do: nil

  defp workspace_crumb_index(trail, root, current_path) do
    Enum.find_index(trail, fn {_label, path} -> path == root end) ||
      overview_index(trail, root, current_path)
  end

  defp session_root_path(%{slug: org_slug}, %{slug: ws_slug}, %{id: session_id}),
    do: "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}"

  defp session_root_path(_, _, _), do: nil

  # Same shape as the workspace crumb: the linked session root on subpages
  # (reviews, deploy-review, review detail), falling back to the final
  # plain-text crumb on the session overview page. Reuses `overview_index/3`
  # so a trailing subpage label never captures the switcher.
  defp session_crumb_index(_trail, nil, _current_path), do: nil

  defp session_crumb_index(trail, root, current_path) do
    Enum.find_index(trail, fn {_label, path} -> path == root end) ||
      overview_index(trail, root, current_path)
  end

  defp overview_index(trail, root, root) do
    case List.last(trail) do
      {_label, nil} -> length(trail) - 1
      _ -> nil
    end
  end

  defp overview_index(_trail, _root, _current_path), do: nil

  # Workspace URL replacer: swaps the workspace slug segment, keeping the
  # subpage and query string, so e.g. repos stays on repos. Falls back to
  # the workspace overview when the current path is outside
  # `:org_slug/workspaces/:ws_slug/*`. Session ids are workspace-scoped, so
  # a session path never carries over: switching workspace from a session
  # page lands on the target workspace overview instead of a dead id.
  # Subpage shapes are dynamic, so this builds a plain string (no `~p`
  # verification); only the ws segment is ever rewritten.
  defp sibling_workspace_path(current_path, current_query, org_slug, ws_slug) do
    {base, from_session?} =
      case String.split(current_path || "", "/", trim: true) do
        [^org_slug, "workspaces", _current_ws | rest] ->
          if "sessions" in rest do
            {"/#{org_slug}/workspaces/#{ws_slug}", true}
          else
            {"/" <> Enum.join([org_slug, "workspaces", ws_slug | rest], "/"), false}
          end

        _ ->
          {"/#{org_slug}/workspaces/#{ws_slug}", false}
      end

    query = if from_session?, do: strip_launched(current_query), else: current_query

    if query && query != "" do
      base <> "?" <> query
    else
      base
    end
  end

  # Session URL replacer: swaps the session id segment, keeping the
  # subpage and query string, so e.g. reviews stays on reviews. Falls back
  # to the session overview when the current path is outside
  # `:org_slug/workspaces/:ws_slug/sessions/:id/*`. Like its workspace
  # counterpart this builds a plain string (no `~p` verification); only the
  # id segment is ever rewritten.
  defp sibling_session_path(current_path, current_query, org_slug, ws_slug, session_id) do
    {base, switching?} =
      case String.split(current_path || "", "/", trim: true) do
        [^org_slug, "workspaces", ^ws_slug, "sessions", current_id | rest] ->
          {"/" <>
             Enum.join(
               [org_slug, "workspaces", ws_slug, "sessions", to_string(session_id) | rest],
               "/"
             ), to_string(session_id) != current_id}

        _ ->
          {"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}", true}
      end

    # `?launched=1` celebrates a fresh launch — it must not follow the user
    # across to a different session.
    query = if switching?, do: strip_launched(current_query), else: current_query

    if query && query != "" do
      base <> "?" <> query
    else
      base
    end
  end

  defp strip_launched(query) when is_binary(query) and query != "" do
    query |> URI.decode_query() |> Map.delete("launched") |> URI.encode_query()
  rescue
    _ -> query
  end

  defp strip_launched(query), do: query

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

  defp sidebar_nav_items(%{nav_session: %{id: _id}} = assigns),
    do:
      session_nav_items(
        assigns.nav_org.slug,
        assigns.nav_workspace.slug,
        assigns.nav_session.id
      )

  defp sidebar_nav_items(%{nav_workspace: nil} = assigns),
    do: organization_nav_items(assigns.nav_org)

  defp sidebar_nav_items(%{nav_workspace: workspace} = assigns),
    do: workspace_nav_items(assigns.nav_org.slug, workspace.slug)

  defp workspace_nav_items(org_slug, ws_slug) do
    [
      %{
        label: "Overview",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}",
        scope: :workspace,
        icon: "hero-squares-2x2"
      },
      %{
        label: "Settings",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/settings",
        scope: :workspace,
        icon: "hero-cog-6-tooth"
      },
      %{
        label: "Repositories",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/repos",
        scope: :workspace,
        icon: "hero-code-bracket"
      },
      %{
        label: "Service accounts",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/service-accounts",
        scope: :workspace,
        icon: "hero-key"
      },
      %{
        label: "Webhooks",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/webhooks",
        scope: :workspace,
        icon: "hero-bolt"
      },
      %{
        label: "Tool policy",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/tool-policy",
        scope: :workspace,
        icon: "hero-shield-check"
      }
    ]
  end

  defp session_nav_items(org_slug, ws_slug, session_id) do
    [
      %{
        label: "Overview",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}",
        scope: :session_overview,
        icon: "hero-squares-2x2"
      },
      %{
        label: "Tasks",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/tasks",
        scope: :session_section,
        icon: "hero-list-bullet"
      },
      %{
        label: "Findings",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/findings",
        scope: :session_section,
        icon: "hero-exclamation-triangle"
      },
      %{
        label: "Reviews",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/reviews",
        scope: :session_section,
        icon: "hero-document-check"
      },
      %{
        label: "Deploy review",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/deploy-review",
        scope: :session_section,
        icon: "hero-cloud-arrow-up"
      },
      %{
        label: "Transcript",
        href: ~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/transcript",
        scope: :session_section,
        icon: "hero-clock"
      }
    ]
  end

  defp sidebar_item_active?(current_path, _current_query, %{scope: :session_overview} = item) do
    is_binary(current_path) && current_path == item.href
  end

  defp sidebar_item_active?(current_path, _current_query, %{scope: :session_section} = item) do
    is_binary(current_path) &&
      (current_path == item.href or String.starts_with?(current_path, item.href <> "/"))
  end

  defp sidebar_item_active?(current_path, _current_query, %{scope: :workspace} = item) do
    is_binary(current_path) && current_path == item.href
  end

  defp sidebar_item_active?(current_path, current_query, item) do
    organization_nav_active?(current_path, current_query, item)
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
