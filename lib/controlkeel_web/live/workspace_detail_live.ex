defmodule ControlKeelWeb.WorkspaceDetailLive do
  @moduledoc """
  Workspace detail page at `/:org_slug/workspaces/:ws_slug`.

  Shows the workspace's default information (name, slug, industry, agent,
  compliance profile, monthly budget, status) and the sessions that belong to
  it. Works in local mode (no membership required) and in cloud mode scoped to
  the visitor's organization. The org slug and the workspace id must agree.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.MCP.ToolGroups
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      sessions = Mission.list_all_sessions(workspace.id)
      tool_policy = Accounts.get_workspace_tool_policy(workspace.id)

      {:ok,
       socket
       |> assign(:page_title, workspace.name)
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{label: workspace.name, to: nil}
         ]
       )
       |> assign(:sessions, sessions)
       |> assign(:policy_assignments, Platform.list_workspace_policy_assignments(workspace.id))
       |> assign(:tool_policy_mode, tool_policy.mode)
       |> assign(:tool_policy_tools, WorkspaceToolPolicy.decode_tools(tool_policy))}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-10">
      <div class="flex flex-col md:flex-row justify-between gap-6">
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-3">
            <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              {@workspace.name}
            </h1>

            <span class={[
              "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              @workspace.status == "active" && "bg-success/10 text-success ring-success/20",
              @workspace.status != "active" && "bg-muted text-muted-foreground ring-border"
            ]}>
              {@workspace.status}
            </span>
          </div>

          <p class="flex flex-wrap items-center gap-x-2 gap-y-1 pt-1 text-xs text-muted-foreground">
            <span class="font-mono">{@workspace.slug}</span>

            <button
              type="button"
              aria-label="Copy workspace slug"
              title="Copy slug"
              phx-click={JS.dispatch("phx:copy-to-clipboard", detail: %{text: @workspace.slug})}
              class="inline-flex items-center rounded p-0.5 text-muted-foreground transition hover:text-primary"
            >
              <.icon name="hero-clipboard" class="size-3.5" />
            </button>

            <span aria-hidden="true">·</span>
            <span>
              <%= if @workspace.budget_cents > 0 do %>
                {"$#{Float.round(@workspace.budget_cents / 100, 2)}/mo budget"}
              <% else %>
                No monthly budget
              <% end %>
            </span>
          </p>
        </div>

        <div>
          <.link
            navigate={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/settings"}
            class="inline-flex shrink-0 items-center gap-2 rounded-full border px-4 py-2 text-sm font-medium text-muted-foreground transition hover:border-primary/40 hover:text-primary"
          >
            <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
          </.link>

          <.link
            navigate={~p"/sessions/start"}
            class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
          >
            <.icon name="hero-plus" class="size-4" /> New Session
          </.link>
        </div>
      </div>

      <div class="space-y-4">
        <div class="space-y-1">
          <.section_title>Governance</.section_title>
          <p class="text-sm text-muted-foreground">
            Controls currently applied to this workspace
          </p>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <section class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-semibold text-muted-foreground">Applied policies</p>
              <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                {length(@policy_assignments)} applied
              </span>
            </div>

            <%= if @policy_assignments == [] do %>
              <p class="mt-4 text-sm text-muted-foreground">
                No policy sets applied to this workspace. Go to settings to apply policy sets to
                this workspace.
              </p>
            <% else %>
              <ul class="mt-4 max-h-96 divide-y divide-border overflow-y-auto">
                <%= for a <- @policy_assignments do %>
                  <% entries =
                    a.policy_set
                    |> Platform.PolicySet.rule_entries()
                    |> Enum.filter(&is_binary(&1["id"])) %>
                  <li class="py-3 first:pt-0 last:pb-0">
                    <div class="flex flex-wrap items-center justify-between gap-2">
                      <p class="text-sm font-semibold text-foreground">
                        {a.policy_set.name}
                      </p>
                      <span class="rounded-full bg-muted px-2 py-0.5 text-[10px] font-medium text-muted-foreground ring-1 ring-border">
                        precedence {a.precedence}
                        <%= unless a.enabled do %>
                          , disabled
                        <% end %>
                      </span>
                    </div>

                    <%= if a.policy_set.description not in [nil, ""] do %>
                      <p class="mt-0.5 text-xs text-muted-foreground">{a.policy_set.description}</p>
                    <% end %>

                    <%= if entries != [] do %>
                      <div class="mt-2 space-y-1.5">
                        <%= for rule <- entries do %>
                          <div class="flex flex-wrap items-center gap-2">
                            <.rule_tag
                              action={rule["action"]}
                              title={rule["action"]}
                              class="px-2 py-0.5 text-[10px] font-semibold uppercase"
                            >
                              {rule["action"]}
                            </.rule_tag>
                            <span class="font-mono text-xs text-foreground">{rule["id"]}</span>
                            <span class="text-xs text-muted-foreground">{rule["plain_message"]}</span>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <p class="mt-1 text-xs text-muted-foreground">No rules in this set.</p>
                    <% end %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </section>

          <section class="rounded-2xl border bg-card p-5 shadow-card">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-semibold text-muted-foreground">Agent tools</p>
              <div class="flex items-center gap-3">
                <span class={[
                  "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                  @tool_policy_mode == "allowlist" && "bg-info/10 text-info ring-info/20",
                  @tool_policy_mode == "denylist" &&
                    "bg-destructive/10 text-destructive ring-destructive/20",
                  @tool_policy_mode == "inherit" && "bg-muted text-muted-foreground ring-border"
                ]}>
                  {@tool_policy_mode}
                </span>

                <.link
                  navigate={
                    ~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/settings?tab=agent_tools"
                  }
                  class="text-xs font-medium text-primary transition hover:text-primary/80"
                >
                  Manage tools
                </.link>
              </div>
            </div>

            <%= cond do %>
              <% @tool_policy_mode == "inherit" -> %>
                <p class="mt-4 text-sm text-muted-foreground">
                  Falls back to the global allowlist — no workspace override is set.
                </p>
              <% @tool_policy_tools == [] -> %>
                <p class="mt-4 text-sm font-medium text-warning">
                  No tools listed — every call is rejected.
                </p>
              <% true -> %>
                <p class="mt-4 text-xs text-muted-foreground">
                  {length(@tool_policy_tools)} tools governed by this workspace's gate.
                </p>

                <ul class="mt-2 max-h-96 divide-y divide-border overflow-y-auto">
                  <%= for tool <- @tool_policy_tools do %>
                    <li class="flex items-center justify-between gap-3 py-2 first:pt-0 last:pb-0">
                      <span class="font-mono text-xs text-foreground">{tool}</span>
                      <%= if tool not in ToolGroups.all_tools() do %>
                        <span class="rounded-full bg-warning/10 px-2 py-0.5 text-[10px] font-medium text-warning ring-1 ring-warning/20">
                          not in catalog
                        </span>
                      <% end %>
                    </li>
                  <% end %>
                </ul>
            <% end %>
          </section>
        </div>
      </div>

      <div>
        <div class="flex items-center gap-2 mb-4">
          <.section_title>Sessions</.section_title>
          <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
            {length(@sessions)} total
          </span>
        </div>

        <div class="bg-card border rounded-2xl shadow-card max-h-[32rem] overflow-y-auto">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
              <tr>
                <th class="px-5 py-3 font-semibold">Session</th>
                <th class="px-5 py-3 font-semibold">Risk</th>
                <th class="px-5 py-3 font-semibold">Workload</th>
                <th class="px-5 py-3 font-semibold">Findings</th>
                <th class="px-5 py-3 font-semibold">Budget</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= if @sessions == [] do %>
                <tr>
                  <td colspan="5" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-foreground">No sessions yet.</p>
                    <p class="mt-1 text-sm text-muted-foreground">
                      Sessions launched under this workspace will appear here.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for session <- @sessions do %>
                  <tr class="transition hover:bg-muted/30">
                    <td class="max-w-sm px-5 py-4">
                      <.link
                        navigate={~p"/sessions/#{session.id}"}
                        class="font-medium text-foreground hover:underline"
                      >
                        {session.title}
                      </.link>
                      <p class="mt-1 line-clamp-1 text-xs text-muted-foreground">
                        {session.objective}
                      </p>
                    </td>
                    <td class="px-5 py-4">
                      <span class={[
                        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                        session.risk_tier in ["critical", "high"] &&
                          "bg-destructive/10 text-destructive ring-destructive/20",
                        session.risk_tier in ["medium", "moderate"] &&
                          "bg-warning/10 text-warning ring-warning/20",
                        session.risk_tier in ["low"] &&
                          "bg-success/10 text-success ring-success/20",
                        session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-muted text-muted-foreground ring-border"
                      ]}>
                        {session.risk_tier}
                      </span>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                        {Enum.count(session.tasks)} tasks
                      </div>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-exclamation-circle" class="size-4 text-muted-foreground" />
                        {Enum.count(session.findings)}
                      </div>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      ${session.budget_cents |> Kernel./(100) |> trunc()}
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  # TODO(auth): the workspace lookup + access checks below are duplicated
  # across workspace LiveViews. Extract into a shared on_mount hook when
  # centralized auth lands (CLI/web parity PR).
  # View access: local mode is open; cloud mode requires membership of the
  # workspace's org (no role requirement — role gates live on write surfaces).
  defp check_workspace_access(workspace, assigns) do
    if Mode.current() == :local do
      :ok
    else
      check_cloud_workspace_access(workspace, assigns)
    end
  end

  defp check_cloud_workspace_access(%Workspace{org_id: nil}, _),
    do: {:error, "Workspace is not bound to an org."}

  defp check_cloud_workspace_access(%Workspace{org_id: ws_org}, %{current_org_id: org_id})
       when is_integer(ws_org) and ws_org == org_id,
       do: :ok

  defp check_cloud_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> put_flash(kind, msg)
    |> push_navigate(to: path)
  end
end
