defmodule ControlKeelWeb.SessionFindingsLive do
  @moduledoc """
  Findings table for a session with per-row actions behind a kebab menu.
  Row names link to the finding detail page at `/sessions/:id/findings/:finding_id`.
  Routed at `/sessions/:id/findings`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if Accounts.session_accessible?(session, org_id) do
          if connected?(socket), do: schedule_refresh()
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        if connected?(socket), do: schedule_refresh()
        {:ok, mount_session(socket, session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply, assign(socket, :session, session)}
    end
  end

  @impl true
  def handle_event("open_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      {:noreply,
       push_navigate(socket, to: ~p"/sessions/#{socket.assigns.session.id}/findings/#{finding_id}")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_finding_menu", %{"id" => id}, socket) do
    menu_finding_id =
      if socket.assigns[:menu_finding_id] && "#{socket.assigns.menu_finding_id}" == id,
        do: nil,
        else: id

    {:noreply, assign(socket, :menu_finding_id, menu_finding_id)}
  end

  @impl true
  def handle_event("close_finding_menu", _params, socket) do
    {:noreply, assign(socket, :menu_finding_id, nil)}
  end

  @impl true
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      refresh_findings(socket, "Finding approved.")
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.reject_finding(finding, nil, actor_opts(socket)) do
      refresh_findings(socket, "Finding rejected.")
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  defp refresh_findings(socket, message) do
    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(:menu_finding_id, nil)
         |> assign(:session, session)}
    end
  end

  defp mount_session(socket, session) do
    socket
    |> assign(:page_title, "#{session.title} — Findings")
    |> assign(:menu_finding_id, nil)
    |> assign(:session, session)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _error -> {:error, :invalid_id}
    end
  end

  defp parse_id(_id), do: {:error, :invalid_id}

  defp actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> [actor_source: "web", actor_identifier: "web"]
      user -> [actor_source: "web", actor_user_id: user.id, actor_identifier: user.email]
    end
  end

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d")

  defp severity_class(severity) when severity in ["critical", "high"],
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp severity_class(severity) when severity in ["medium", "moderate"],
    do: "bg-warning/10 text-warning ring-warning/20"

  defp severity_class("low"),
    do: "bg-success/10 text-success ring-success/20"

  defp severity_class(_severity), do: "bg-muted text-muted-foreground ring-border"

  defp menu_open?(nil, _finding_id), do: false

  defp menu_open?(menu_finding_id, finding_id),
    do: to_string(menu_finding_id) == to_string(finding_id)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-card border rounded-2xl shadow-card" id="session-findings-table">
      <table class="min-w-full divide-y divide-border text-left text-sm">
        <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground [&>tr>th:first-child]:rounded-tl-2xl [&>tr>th:last-child]:rounded-tr-2xl">
          <tr>
            <th class="px-5 py-3 font-semibold">Finding</th>
            <th class="px-5 py-3 font-semibold">Severity</th>
            <th class="px-5 py-3 font-semibold">Status</th>
            <th class="px-5 py-3 font-semibold">Category</th>
            <th class="px-5 py-3 font-semibold">Recorded</th>
            <th class="px-5 py-3 font-semibold w-px whitespace-nowrap">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-border [&>tr:last-child>td:first-child]:rounded-bl-2xl [&>tr:last-child>td:last-child]:rounded-br-2xl">
          <tr :if={@session.findings == []}>
            <td colspan="6" class="px-5 py-12 text-center">
              <p class="text-base font-medium text-foreground">No findings yet.</p>
              <p class="mt-1 text-sm text-muted-foreground">
                ControlKeel is monitoring every agent action.
              </p>
            </td>
          </tr>
          <tr
            :for={finding <- @session.findings}
            id={"finding-row-#{finding.id}"}
            class="transition hover:bg-muted/30"
          >
            <td
              id={"finding-title-cell-#{finding.id}"}
              class="px-5 py-4 hover:cursor-pointer font-semibold text-foreground break-words"
              phx-click="open_finding"
              phx-value-id={finding.id}
            >
              {finding.title}
            </td>
            <td
              class="px-5 py-4 whitespace-nowrap hover:cursor-pointer"
              phx-click="open_finding"
              phx-value-id={finding.id}
            >
              <span class={[
                "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                severity_class(finding.severity)
              ]}>
                {finding.severity}
              </span>
            </td>
            <td
              class="px-5 py-4 whitespace-nowrap hover:cursor-pointer"
              phx-click="open_finding"
              phx-value-id={finding.id}
            >
              <span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-muted text-muted-foreground ring-border">
                {finding.status}
              </span>
            </td>
            <td
              class="px-5 py-4 text-muted-foreground whitespace-nowrap hover:cursor-pointer"
              phx-click="open_finding"
              phx-value-id={finding.id}
            >
              {finding.category}
            </td>
            <td
              class="px-5 py-4 text-muted-foreground whitespace-nowrap hover:cursor-pointer"
              phx-click="open_finding"
              phx-value-id={finding.id}
            >
              <span class="font-mono tabular-nums tracking-tight">
                {event_timestamp(finding.inserted_at)}
              </span>
            </td>
            <td class="px-5 py-4 text-right whitespace-nowrap w-px">
              <div class="relative inline-block text-left" phx-click-away="close_finding_menu">
                <button
                  type="button"
                  id={"finding-menu-button-#{finding.id}"}
                  class="inline-flex items-center justify-center rounded-md p-1.5 text-muted-foreground transition hover:bg-muted hover:text-foreground cursor-pointer"
                  phx-click="toggle_finding_menu"
                  phx-value-id={finding.id}
                  aria-label={"Actions for #{finding.title}"}
                  aria-haspopup="menu"
                  aria-expanded={menu_open?(@menu_finding_id, finding.id)}
                >
                  <.icon name="hero-ellipsis-vertical" class="size-5" />
                </button>
                <div
                  :if={menu_open?(@menu_finding_id, finding.id)}
                  id={"finding-menu-#{finding.id}"}
                  role="menu"
                  class="absolute right-0 z-20 mt-1 w-48 rounded-md border bg-card shadow-card py-1"
                >
                  <.link
                    navigate={~p"/sessions/#{@session.id}/findings/#{finding.id}"}
                    role="menuitem"
                    class="block px-4 py-2 text-sm text-foreground transition hover:bg-muted"
                  >
                    View details
                  </.link>
                  <button
                    :if={finding.status in ["open", "blocked"]}
                    type="button"
                    role="menuitem"
                    class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                    phx-click="approve_finding"
                    phx-value-id={finding.id}
                  >
                    Approve
                  </button>
                  <button
                    :if={finding.status in ["open", "blocked"]}
                    type="button"
                    role="menuitem"
                    class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                    phx-click="reject_finding"
                    phx-value-id={finding.id}
                  >
                    Reject
                  </button>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
