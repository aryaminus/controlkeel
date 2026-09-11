defmodule ControlKeelWeb.WorkspaceSettingsLive do
  @moduledoc """
  Workspace settings at `/:org_slug/workspaces/:ws_slug/settings`.

  Secondary navigation over setting groups. Two groups today: Policies
  (rule-set assignments, parity with `controlkeel policy-set apply`) and
  Tool policy (the MCP gate editor also available standalone at
  `/:org_slug/workspaces/:ws_slug/tool-policy`).
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

  @tabs ["policies", "agent_tools"]

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      tool_policy = Accounts.get_workspace_tool_policy(workspace.id)
      tools = WorkspaceToolPolicy.decode_tools(tool_policy)

      {:ok,
       socket
       |> assign(:page_title, "Settings — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/#{workspace.org.slug}/workspaces/#{workspace.slug}"
           },
           %{label: "Settings", to: nil}
         ]
       )
       |> assign(:active_tab, "policies")
       |> assign(:tabs, @tabs)
       |> assign(:modes, WorkspaceToolPolicy.modes())
       |> assign(:selected_tools, tools)
       |> assign(:unknown_tools, tools -- ToolGroups.all_tools())
       |> assign(:tool_options, ToolGroups.all_tools())
       |> assign(:live_mode, tool_policy.mode)
       |> assign(
         :apply_form,
         to_form(%{"policy_set_id" => "", "precedence" => "100"}, as: :assignment)
       )
       |> refresh_policy_assigns()}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :active_tab, normalize_tab(params["tab"]))}
  end

  defp normalize_tab("agent_tools"), do: "agent_tools"
  defp normalize_tab(_tab), do: "policies"

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/#{socket.assigns.workspace.org.slug}/workspaces/#{socket.assigns.workspace.slug}/settings?tab=#{tab}"
     )}
  end

  def handle_event("set_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("apply_policy_set", %{"assignment" => params}, socket) do
    with {:ok, set_id} <- parse_int(params["policy_set_id"]),
         {:ok, precedence} <- parse_precedence(params["precedence"]) do
      case Platform.apply_policy_set(socket.assigns.workspace.id, set_id, %{
             "precedence" => precedence,
             "enabled" => true
           }) do
        {:ok, _assignment} ->
          {:noreply,
           socket
           |> put_flash(:info, "Policy set applied.")
           |> refresh_policy_assigns()}

        {:error, %Ecto.Changeset{} = changeset} ->
          msg = Enum.map_join(changeset.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
          {:noreply, put_flash(socket, :error, msg)}
      end
    else
      :error ->
        {:noreply,
         put_flash(socket, :error, "Choose a policy set and a non-negative precedence.")}
    end
  end

  @impl true
  def handle_event("remove_policy_set", %{"policy-set-id" => id}, socket) do
    case parse_int(id) do
      {:ok, set_id} ->
        case Platform.remove_workspace_policy_set(socket.assigns.workspace.id, set_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Policy set removed.")
             |> refresh_policy_assigns()}

          _ ->
            {:noreply, put_flash(socket, :error, "Policy set assignment not found.")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid policy set id.")}
    end
  end

  @impl true
  def handle_event("toggle_assignment", %{"policy-set-id" => id}, socket) do
    with {:ok, set_id} <- parse_int(id),
         %{} = assignment <- find_assignment(socket.assigns.policy_assignments, set_id) do
      # Re-apply flips the enabled flag via the upsert while keeping precedence.
      case Platform.apply_policy_set(socket.assigns.workspace.id, set_id, %{
             "precedence" => assignment.precedence,
             "enabled" => not assignment.enabled
           }) do
        {:ok, assignment} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Policy set #{if assignment.enabled, do: "enabled", else: "disabled"}."
           )
           |> refresh_policy_assigns()}

        {:error, %Ecto.Changeset{} = changeset} ->
          msg = Enum.map_join(changeset.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
          {:noreply, put_flash(socket, :error, msg)}
      end
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid policy set id.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Policy set assignment not found.")}
    end
  end

  @impl true
  def handle_event("mode_changed", %{"policy" => %{"mode" => mode}}, socket) do
    {:noreply, assign(socket, :live_mode, mode)}
  end

  @impl true
  def handle_event("pick_tool", %{"tool_picker" => tool}, socket) when tool != "" do
    selected = socket.assigns.selected_tools
    updated = if tool in selected, do: selected, else: selected ++ [tool]
    {:noreply, assign(socket, :selected_tools, updated)}
  end

  def handle_event("pick_tool", _params, socket), do: {:noreply, socket}

  def handle_event("remove_tool", %{"tool" => tool}, socket) do
    {:noreply, assign(socket, :selected_tools, List.delete(socket.assigns.selected_tools, tool))}
  end

  @impl true
  def handle_event("submit", %{"policy" => %{"mode" => mode}}, socket) do
    tools = socket.assigns.selected_tools

    case Accounts.set_workspace_tool_policy(socket.assigns.workspace.id, mode, tools) do
      {:ok, policy} ->
        saved_tools = WorkspaceToolPolicy.decode_tools(policy)

        {:noreply,
         socket
         |> assign(:selected_tools, saved_tools)
         |> assign(:unknown_tools, saved_tools -- ToolGroups.all_tools())
         |> assign(:live_mode, policy.mode)
         |> put_flash(:info, "Agent tools policy saved (#{policy.mode}).")}

      {:error, %Ecto.Changeset{} = cs} ->
        msg = Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Workspace settings
          </h1>
        </div>
      </div>

      <div class="grid gap-6 lg:grid-cols-[200px_minmax(0,1fr)]">
        <nav
          class="rounded-2xl border bg-card shadow-card lg:self-start lg:p-3"
          aria-label="Workspace settings sections"
        >
          <ul class="flex gap-1 list-none m-0 overflow-x-auto p-2 lg:flex-col lg:gap-1 lg:p-0">
            <%= for tab <- @tabs do %>
              <li class="shrink-0">
                <button
                  type="button"
                  phx-click="set_tab"
                  phx-value-tab={tab}
                  aria-current={@active_tab == tab && "page"}
                  class={[
                    "w-full whitespace-nowrap rounded-lg px-3 py-2 text-left text-sm transition",
                    @active_tab == tab &&
                      "bg-primary/10 font-semibold text-primary",
                    @active_tab != tab && "text-muted-foreground hover:bg-muted hover:text-foreground"
                  ]}
                >
                  {tab_label(tab)}
                </button>
              </li>
            <% end %>
          </ul>
        </nav>

        <%= case @active_tab do %>
          <% "agent_tools" -> %>
            <.tool_policy_panel
              workspace={@workspace}
              modes={@modes}
              tool_options={@tool_options}
              selected_tools={@selected_tools}
              unknown_tools={@unknown_tools}
              live_mode={@live_mode}
            />
          <% _ -> %>
            <.policy_sets_panel
              policy_assignments={@policy_assignments}
              available_sets={@available_sets}
              apply_form={@apply_form}
            />
        <% end %>
      </div>
    </section>
    """
  end

  attr :policy_assignments, :list, required: true
  attr :available_sets, :list, required: true
  attr :apply_form, :map, required: true

  defp policy_sets_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border bg-card p-5 shadow-card">
      <.section_title>Policy sets</.section_title>
      <p class="mt-1 text-xs text-muted-foreground">
        Rules from applied sets run for every validation mapped to this workspace.
        Lower precedence evaluates earlier.
      </p>

      <%= if @policy_assignments == [] do %>
        <p class="mt-4 text-sm text-muted-foreground">No policy sets applied yet.</p>
      <% else %>
        <ul class="mt-4 divide-y divide-border">
          <%= for a <- @policy_assignments do %>
            <li class="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0">
              <div>
                <p class="text-sm font-semibold text-foreground">
                  {a.policy_set.name}
                </p>
                <p class="mt-0.5 text-xs text-muted-foreground">
                  precedence {a.precedence}
                  <%= unless a.enabled do %>
                    , disabled
                  <% end %>
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <button
                  type="button"
                  phx-click="toggle_assignment"
                  phx-value-policy-set-id={a.policy_set_id}
                  class="inline-flex items-center rounded-lg px-3 py-1.5 text-xs font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
                >
                  <%= if a.enabled do %>
                    Disable
                  <% else %>
                    Enable
                  <% end %>
                </button>
                <button
                  type="button"
                  phx-click="remove_policy_set"
                  phx-value-policy-set-id={a.policy_set_id}
                  class="inline-flex items-center rounded-lg px-3 py-1.5 text-xs font-medium text-destructive transition hover:bg-destructive/10"
                >
                  Remove
                </button>
              </div>
            </li>
          <% end %>
        </ul>
      <% end %>

      <.form
        for={@apply_form}
        phx-submit="apply_policy_set"
        id="workspace-policy-apply-form"
        class={[
          "mt-4 flex flex-wrap items-end gap-3 border-t pt-4",
          @available_sets == [] && "opacity-60"
        ]}
      >
        <div class="min-w-[220px] flex-1">
          <label
            for="policy-set-select"
            class="mb-1.5 flex items-center text-sm font-medium text-foreground/90"
          >
            Policy set
          </label>
          <select
            id="policy-set-select"
            name="assignment[policy_set_id]"
            disabled={@available_sets == [] || nil}
            class={[
              "h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-base outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm",
              @available_sets == [] && "cursor-not-allowed opacity-60"
            ]}
          >
            <%= for s <- @available_sets do %>
              <option value={s.id}>#{s.id} {s.name}</option>
            <% end %>
          </select>
        </div>
        <div class="w-28">
          <.input_component
            type="number"
            id="policy-set-precedence"
            name="assignment[precedence]"
            value="100"
            label="Precedence"
            min="0"
            disabled={@available_sets == [] || nil}
          />
        </div>
        <.button type="submit" disabled={@available_sets == [] || nil}>Apply</.button>
      </.form>

      <%= if @available_sets == [] do %>
        <p class="mt-4 text-xs text-muted-foreground">
          All policy sets are applied. Go to
          <.link navigate={~p"/policies"} class="font-medium text-primary hover:underline">
            Policy Studio
          </.link>
          to create new policies.
        </p>
      <% end %>
    </section>
    """
  end

  attr :workspace, :map, required: true
  attr :modes, :list, required: true
  attr :tool_options, :list, required: true
  attr :selected_tools, :list, required: true
  attr :unknown_tools, :list, required: true
  attr :live_mode, :string, required: true

  defp tool_policy_panel(assigns) do
    ~H"""
    <section class="rounded-2xl border bg-card p-5 shadow-card">
      <.section_title>Agent tools</.section_title>
      <p class="mt-1 text-xs text-muted-foreground">
        Restrict which MCP tools agents in this workspace may invoke. <code>inherit</code>
        falls back to the global allowlist; <code>allowlist</code>
        and <code>denylist</code>
        override it.
      </p>

      <form id="workspace-tool-policy-form" phx-submit="submit" class="mt-4 space-y-4">
        <div>
          <label
            for="tool-policy-mode"
            class="mb-1.5 flex items-center text-sm font-medium text-foreground/90"
          >
            Mode
          </label>
          <select
            id="tool-policy-mode"
            name="policy[mode]"
            phx-change="mode_changed"
            class="w-full rounded-lg border border-input bg-transparent px-2.5 py-2 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm"
          >
            <%= for m <- @modes do %>
              <option value={m} selected={@live_mode == m}>{m}</option>
            <% end %>
          </select>
        </div>

        <.button type="submit">Save policy</.button>
      </form>

      <div>
        <%= if @selected_tools == [] do %>
          <p class="text-xs text-muted-foreground">No tools selected.</p>
        <% else %>
          <ul class="flex list-none flex-wrap gap-1.5 m-0 p-0">
            <%= for tool <- @selected_tools do %>
              <li class={[
                "inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium ring-1",
                tool in @tool_options &&
                  "bg-primary/10 text-primary ring-primary/20",
                tool not in @tool_options && "bg-warning/10 text-warning ring-warning/20",
                @live_mode == "inherit" && "opacity-50"
              ]}>
                {tool}
                <button
                  type="button"
                  phx-click="remove_tool"
                  phx-value-tool={tool}
                  disabled={@live_mode == "inherit" || nil}
                  aria-label={"Remove #{tool}"}
                  class={[
                    "transition",
                    @live_mode == "inherit" &&
                      "cursor-not-allowed opacity-60 hover:text-current",
                    @live_mode != "inherit" && "cursor-pointer hover:text-destructive"
                  ]}
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>

        <select
          id="tool-policy-picker"
          name="tool_picker"
          phx-change="pick_tool"
          disabled={@live_mode == "inherit" || nil}
          class={[
            "mt-2 w-full rounded-lg border border-input bg-transparent px-2.5 py-2 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm",
            @live_mode == "inherit" && "cursor-not-allowed opacity-50"
          ]}
        >
          <option value="">Add a tool…</option>
          <%= for tool <- @tool_options do %>
            <%= unless tool in @selected_tools do %>
              <option value={tool}>{tool}</option>
            <% end %>
          <% end %>
        </select>

        <p class="mt-1.5 text-xs text-muted-foreground">
          Used by <code>allowlist</code>
          and <code>denylist</code>
          modes. Ignored under <code>inherit</code>.
        </p>
      </div>
    </section>
    """
  end

  defp refresh_policy_assigns(socket) do
    # Display list includes disabled assignments; the dropdown excludes any
    # set with an assignment row so re-applying never silently flips a
    # disabled assignment back to enabled via the upsert.
    assignments = Platform.list_workspace_policy_assignments(socket.assigns.workspace.id)
    assigned_ids = Enum.map(assignments, & &1.policy_set_id)

    available_sets =
      Platform.list_policy_sets()
      |> Enum.reject(&(&1.id in assigned_ids))

    socket
    |> assign(:policy_assignments, assignments)
    |> assign(:available_sets, available_sets)
  end

  defp tab_label("policies"), do: "Policies"
  defp tab_label("agent_tools"), do: "Agent tools"

  defp find_assignment(assignments, set_id) do
    Enum.find(assignments, &(&1.policy_set_id == set_id)) || {:error, :not_found}
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp parse_precedence(value) do
    case parse_int(value || "") do
      {:ok, n} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  # TODO(auth): the workspace lookup + access checks below are duplicated
  # across workspace LiveViews. Extract into a shared on_mount hook when
  # centralized auth lands (CLI/web parity PR).
  defp check_workspace_access(workspace, assigns) do
    if Mode.current() == :local do
      :ok
    else
      check_cloud_workspace_access(workspace, assigns)
    end
  end

  defp check_cloud_workspace_access(%Workspace{org_id: nil}, _),
    do: {:error, "Workspace is not bound to an org."}

  defp check_cloud_workspace_access(%Workspace{org_id: ws_org}, %{
         current_org_id: org_id,
         current_membership: m
       })
       when is_integer(ws_org) and ws_org == org_id do
    if m && Accounts.role_at_least?(m.role, "admin"),
      do: :ok,
      else: {:error, "Admin or owner role required."}
  end

  defp check_cloud_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
