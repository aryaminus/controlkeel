defmodule ControlKeelWeb.SessionActivityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope
  alias ControlKeel.Platform

  @refresh_interval_ms 2_000
  @initial_event_limit 50
  @load_more_step 50

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    case SessionScope.fetch_session(id) do
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

          SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
            {:ok,
             socket
             |> put_flash(:error, "Session not found.")
             |> push_navigate(to: ~p"/")}

          true ->
            if connected?(socket), do: schedule_refresh()

            {:ok,
             socket
             |> assign(:event_limit, @initial_event_limit)
             |> assign(:expanded_events, MapSet.new())
             |> assign_session(session)}
        end
    end
  end

  defp assign_session(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

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
      %{label: "Activity", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Activity")
    |> assign(:session, session)
    |> assign_transcript()
  end

  defp assign_transcript(socket) do
    session_id = socket.assigns.session.id
    limit = socket.assigns.event_limit

    socket
    |> assign(:transcript_summary, Mission.transcript_summary(session_id))
    |> assign(:recent_events, Mission.list_session_events(session_id, limit))
    |> assign(
      :latest_audit_export,
      Platform.list_audit_exports(session_id, 1) |> List.first()
    )
  end

  @impl true
  def handle_info(:refresh, socket) do
    case Mission.get_session_nav(socket.assigns.session.id) do
      nil ->
        {:noreply, SessionScope.session_not_found(socket)}

      session ->
        case SessionScope.reauthorize(socket, session) do
          {:ok, session} ->
            if connected?(socket), do: schedule_refresh()
            {:noreply, assign_session(socket, session)}

          {:error, :not_found} ->
            {:noreply, SessionScope.session_not_found(socket)}
        end
    end
  end

  @impl true
  def handle_event("toggle_event", %{"id" => id}, socket)
      when is_binary(id) or is_integer(id) or is_atom(id) do
    event_id = to_string(id)

    expanded_events =
      if MapSet.member?(socket.assigns.expanded_events, event_id) do
        MapSet.delete(socket.assigns.expanded_events, event_id)
      else
        MapSet.put(socket.assigns.expanded_events, event_id)
      end

    {:noreply, assign(socket, :expanded_events, expanded_events)}
  end

  def handle_event("toggle_event", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> assign(:event_limit, socket.assigns.event_limit + @load_more_step)
     |> assign_transcript()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title
        title="Activity"
        subtitle="Event feed and audit exports for this governed run."
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Total events</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@transcript_summary["total_events"] || 0}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {length(@transcript_summary["families"] || [])} event families
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Latest activity</p>
          <p class="mt-2 text-base font-semibold font-mono tabular-nums tracking-tight text-foreground/90">
            {latest_activity(@recent_events)}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {latest_actor(@recent_events) || "No recorded actor"}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Full timeline</p>
          <.link
            navigate={~p"/observability/sessions/#{@session.id}/timeline"}
            class="mt-2 inline-flex items-center gap-1 text-sm font-semibold text-primary hover:text-primary transition cursor-pointer"
          >
            Open run timeline <.icon name="hero-arrow-right" class="size-3.5" />
          </.link>
          <p class="mt-1 text-xs text-muted-foreground">
            Health, events, memory, and cost for this run.
          </p>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <.section_title>Event feed</.section_title>
            <p class="mt-1 text-sm text-muted-foreground">
              Governed activity with links to the task, finding, or review it belongs to.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <%= for family <- Enum.take(@transcript_summary["families"] || [], 8) do %>
              <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2.5 py-1 text-xs text-muted-foreground">
                {family["family"]} · {family["count"]}
              </span>
            <% end %>
          </div>
        </div>

        <%= if @recent_events == [] do %>
          <p class="mt-6 text-sm text-muted-foreground">No transcript events recorded yet.</p>
        <% else %>
          <ul class="mt-5 divide-y divide-border list-none p-0 m-0 border-y">
            <%= for event <- @recent_events do %>
              <li
                id={"transcript-event-#{event["id"]}"}
                phx-click={event_details?(event) && "toggle_event"}
                phx-value-id={event["id"]}
                phx-keydown={event_details?(event) && "toggle_event"}
                phx-key="Enter"
                role={event_details?(event) && "button"}
                tabindex={event_details?(event) && "0"}
                aria-expanded={event_details?(event) && to_string(expanded?(@expanded_events, event))}
                class={[
                  "px-4 py-3 transition hover:bg-muted/30",
                  event_details?(event) && "cursor-pointer"
                ]}
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <strong class="text-sm font-medium text-foreground">{event["summary"]}</strong>
                  <span class="flex items-center gap-1.5">
                    <.icon
                      :if={event_details?(event)}
                      name="hero-chevron-down"
                      class={[
                        "size-4 text-muted-foreground transition-transform",
                        expanded?(@expanded_events, event) && "rotate-180"
                      ]}
                    />
                    <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground">
                      {event["event_type"]}
                    </span>
                  </span>
                </div>
                <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                  <span class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5">
                    {event["actor"]}
                  </span>
                  <span class="font-mono tabular-nums tracking-tight">
                    {event_timestamp(event["inserted_at"])}
                  </span>
                  <.link
                    :if={event["task_id"]}
                    navigate={
                      ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/tasks"
                    }
                    class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5 transition hover:text-foreground"
                  >
                    Task #{event["task_id"]}
                  </.link>
                  <.link
                    :if={event["finding_id"]}
                    navigate={
                      ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/findings"
                    }
                    class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5 transition hover:text-foreground"
                  >
                    Finding #{event["finding_id"]}
                  </.link>
                  <.link
                    :if={event["review_id"]}
                    navigate={
                      ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/reviews/#{event["review_id"]}"
                    }
                    class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5 transition hover:text-foreground"
                  >
                    Review #{event["review_id"]}
                  </.link>
                </div>
                <div
                  :if={expanded?(@expanded_events, event) and event_details?(event)}
                  id={"transcript-event-details-#{event["id"]}"}
                  class="mt-3 space-y-3"
                >
                  <pre
                    :if={is_binary(event["body"]) and event["body"] != ""}
                    class="p-3 border rounded-lg bg-muted/[0.03] text-xs text-muted-foreground whitespace-pre-wrap break-words"
                  >{event["body"]}</pre>
                  <pre
                    :if={map_size(event["payload"] || %{}) > 0}
                    class="p-3 max-h-72 overflow-auto border rounded-lg bg-muted/[0.03] text-xs font-mono whitespace-pre-wrap break-all"
                  >{Jason.encode!(event["payload"], pretty: true)}</pre>
                </div>
              </li>
            <% end %>
          </ul>

          <div class="mt-5 flex flex-wrap items-center justify-between gap-3 border-t pt-4">
            <p class="text-xs text-muted-foreground">
              Showing {length(@recent_events)} of {@transcript_summary["total_events"] || 0} recorded events.
            </p>
            <button
              :if={more_events?(@recent_events, @transcript_summary)}
              id="transcript-load-more"
              type="button"
              phx-click="load_more"
              class="inline-flex items-center gap-2 rounded-3xl border px-4 py-2 text-sm font-semibold text-muted-foreground transition hover:bg-muted hover:text-foreground"
            >
              <.icon name="hero-chevron-down" class="size-4" /> Load older events
            </button>
          </div>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <.section_title>Audit exports</.section_title>
            <p class="mt-1 text-sm text-muted-foreground">
              Export a checksummed record of this session's governed activity.
            </p>
            <p :if={@latest_audit_export} class="mt-2 text-xs text-muted-foreground">
              Last export ({@latest_audit_export.format}):
              <code class="font-mono break-all">{@latest_audit_export.checksum}</code>
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2" aria-label="Audit log exports">
            <.link
              :for={format <- ~w(json csv pdf)}
              id={"activity-audit-export-#{format}"}
              href={~p"/observability/sessions/#{@session.id}/audit-log/#{format}"}
              class="rounded-lg border border-border bg-transparent px-2.5 py-1.5 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground transition hover:bg-muted hover:text-foreground"
            >
              {String.upcase(format)}
            </.link>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp latest_activity([]), do: "No events yet"

  defp latest_activity([latest | _rest]), do: event_timestamp(latest["inserted_at"])

  defp latest_actor([]), do: nil
  defp latest_actor([latest | _rest]), do: latest["actor"]

  defp more_events?(events, summary),
    do: length(events) < (summary["total_events"] || 0)

  defp event_details?(event) do
    (is_binary(event["body"]) and event["body"] != "") or
      map_size(event["payload"] || %{}) > 0
  end

  defp expanded?(expanded_events, event),
    do: MapSet.member?(expanded_events, to_string(event["id"]))

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
end
