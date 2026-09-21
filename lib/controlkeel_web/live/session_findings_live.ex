defmodule ControlKeelWeb.SessionFindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.FindingComponents

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(session) ->
        cond do
          not ControlKeel.Accounts.session_accessible?(session, current_user) ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          check_session_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()

            {:ok,
             socket
             |> assign(:selected_finding, nil)
             |> assign(:selected_fix, nil)
             |> assign_session(session)}
        end
    end
  end

  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} -> Enum.find(session.findings || [], &(&1.id == id))
        _ -> nil
      end

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(:breadcrumbs, [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      },
      %{label: "Findings", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Findings")
    |> assign(:session, session)
    |> assign(:selected_finding, selected_finding)
    |> assign(:selected_fix, maybe_regenerate_fix(selected_finding))
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
    end
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <-
           Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error -> {:noreply, put_flash(socket, :error, "ControlKeel could not load that fix.")}
    end
  end

  @impl true
  def handle_event("copy_fix_prompt", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.selected_finding,
         %{"agent_prompt" => prompt} = fix <- socket.assigns.selected_fix,
         true <- is_binary(prompt) and prompt != "" do
      emit_autofix_event(:copied, finding, fix)

      {:noreply,
       socket
       |> push_event("copy-to-clipboard", %{text: prompt})
       |> put_flash(:info, "Fix prompt copied to the clipboard.")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_fix", _params, socket) do
    {:noreply, socket |> assign(:selected_finding, nil) |> assign(:selected_fix, nil)}
  end

  @impl true
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply, socket |> put_flash(:info, "Finding approved.") |> assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", params, socket) do
    id = params["id"]

    reason =
      params["reason"]
      |> then(&if is_binary(&1) and String.trim(&1) != "", do: String.trim(&1), else: nil)

    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.reject_finding(finding, reason, actor_opts(socket)) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply, socket |> put_flash(:info, "Finding rejected.") |> assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  @impl true
  def handle_event("escalate_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.escalate_finding(finding, actor_opts(socket)) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply, socket |> put_flash(:info, "Finding escalated.") |> assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not escalate finding.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title title="Findings" />

      <div class="bg-card border rounded-2xl shadow-card overflow-visible">
        <table class="min-w-full divide-y divide-border text-left text-sm border-separate border-spacing-0">
          <thead class="text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="bg-muted px-5 py-3 font-semibold first:rounded-tl-2xl">Finding</th>
              <th class="bg-muted px-5 py-3 font-semibold">Severity</th>
              <th class="bg-muted px-5 py-3 font-semibold">Status</th>
              <th class="bg-muted px-5 py-3 font-semibold">Category</th>
              <th class="bg-muted px-5 py-3 font-semibold">Updated</th>
              <th class="bg-muted px-5 py-3 font-semibold w-px whitespace-nowrap last:rounded-tr-2xl"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= for finding <- @session.findings do %>
              <tr id={"finding-row-#{finding.id}"} class="transition hover:bg-muted/30">
                <td class="px-5 py-4">
                  <div class="font-medium text-foreground">{finding.title}</div>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    finding.severity in ["critical", "high"] &&
                      "bg-destructive/10 text-destructive ring-destructive/20",
                    finding.severity in ["medium", "moderate"] &&
                      "bg-[var(--ck-warning)]/10 text-[var(--ck-warning)] ring-[var(--ck-warning)]/20",
                    finding.severity in ["low"] &&
                      "bg-[var(--ck-success)]/10 text-[var(--ck-success)] ring-[var(--ck-success)]/20",
                    finding.severity not in ["critical", "high", "medium", "moderate", "low"] &&
                      "bg-muted text-muted-foreground ring-border"
                  ]}>
                    {finding.severity}
                  </span>
                </td>
                <td class="px-5 py-4 whitespace-nowrap">
                  <span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-muted text-muted-foreground ring-border">
                    {finding.status}
                  </span>
                </td>
                <td class="px-5 py-4 text-muted-foreground whitespace-nowrap">{finding.category}</td>
                <td class="px-5 py-4 text-muted-foreground whitespace-nowrap w-px font-mono tabular-nums tracking-tight text-xs">
                  {event_timestamp(finding.inserted_at)}
                </td>
                <td class="px-4 text-right whitespace-nowrap w-px">
                  <div id={"finding-actions-wrapper-#{finding.id}"} class="relative inline-flex">
                    <button
                      id={"finding-actions-#{finding.id}"}
                      type="button"
                      aria-label={"Actions for #{finding.title}"}
                      aria-haspopup="menu"
                      aria-expanded="false"
                      phx-click={
                        JS.toggle(to: "#finding-menu-#{finding.id}")
                        |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                        |> JS.toggle_class("z-50", to: "#finding-actions-wrapper-#{finding.id}")
                      }
                      class="inline-flex size-8 shrink-0 items-center justify-center rounded-lg border border-border bg-card text-foreground shadow-sm transition hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    >
                      <.icon name="hero-ellipsis-horizontal" class="size-5 shrink-0" />
                    </button>
                    <div
                      id={"finding-menu-#{finding.id}"}
                      class={[
                        "hidden absolute right-0 z-50 w-48 rounded-xl border bg-card p-1.5 shadow-2xl shadow-black/20",
                        if finding == List.last(@session.findings) do "bottom-full mb-1" else "top-full mt-1" end
                      ]}
                      phx-click-away={
                        JS.hide(to: "#finding-menu-#{finding.id}")
                        |> JS.remove_class("z-50", to: "#finding-actions-wrapper-#{finding.id}")
                        |> JS.set_attribute({"aria-expanded", "false"}, to: "#finding-actions-#{finding.id}")
                      }
                    >
                      <button
                        type="button"
                        class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                        phx-click={
                          JS.hide(to: "#finding-menu-#{finding.id}")
                          |> JS.remove_class("z-50", to: "#finding-actions-wrapper-#{finding.id}")
                          |> JS.set_attribute({"aria-expanded", "false"}, to: "#finding-actions-#{finding.id}")
                          |> JS.push("view_fix", value: %{id: finding.id})
                        }
                      >
                        View fix
                      </button>
                      <%= if finding.status in ["open", "blocked"] do %>
                        <button
                          type="button"
                          class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                          phx-click={
                            JS.hide(to: "#finding-menu-#{finding.id}")
                            |> JS.push("approve_finding", value: %{id: finding.id})
                          }
                        >
                          Approve
                        </button>
                        <button
                          type="button"
                          class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                          phx-click={
                            JS.hide(to: "#finding-menu-#{finding.id}")
                            |> JS.push("reject_finding", value: %{id: finding.id})
                          }
                        >
                          Reject
                        </button>
                        <button
                          type="button"
                          class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-foreground transition hover:bg-muted"
                          phx-click={
                            JS.hide(to: "#finding-menu-#{finding.id}")
                            |> JS.push("escalate_finding", value: %{id: finding.id})
                          }
                        >
                          Escalate
                        </button>
                      <% end %>
                    </div>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if @session.findings == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No findings yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    ControlKeel is monitoring every agent action.
                  </p>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <.modal
        :if={@selected_finding && @selected_fix}
        id="finding-fix-modal"
        title={"Guided fix: #{@selected_finding.title}"}
        on_close="close_fix"
      >
        <FindingComponents.autofix_panel
          finding={@selected_finding}
          fix={@selected_fix}
          copy_event="copy_fix_prompt"
          close_event="close_fix"
        />
      </.modal>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d")

  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

  defp emit_autofix_event(action, finding, fix) do
    :telemetry.execute(
      [:controlkeel, :autofix, action],
      %{count: 1},
      %{
        finding_id: finding.id,
        session_id: finding.session_id,
        rule_id: finding.rule_id,
        supported: fix["supported"],
        fix_kind: fix["fix_kind"]
      }
    )
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> [actor_source: "web", actor_identifier: "web"]
      user -> [actor_source: "web", actor_user_id: user.id, actor_identifier: user.email]
    end
  end
end
