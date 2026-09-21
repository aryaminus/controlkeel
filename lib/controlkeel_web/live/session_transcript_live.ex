defmodule ControlKeelWeb.SessionTranscriptLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @refresh_interval_ms 2_000
  @initial_event_limit 50
  @load_more_step 50

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
             |> assign(:event_limit, @initial_event_limit)
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
      %{label: "Transcript", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Transcript")
    |> assign(:session, session)
    |> assign_transcript()
  end

  defp assign_transcript(socket) do
    session_id = socket.assigns.session.id
    limit = socket.assigns.event_limit

    socket
    |> assign(:transcript_summary, Mission.transcript_summary(session_id))
    |> assign(:recent_events, Mission.list_session_events(session_id, limit))
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
        title="Transcript"
        subtitle="Every recorded event for this governed run, newest first."
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
          <ul class="mt-5 space-y-2 list-none p-0 m-0">
            <%= for event <- @recent_events do %>
              <li
                id={"transcript-event-#{event["id"]}"}
                class="rounded-xl border bg-card px-4 py-3 transition hover:bg-muted/30"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <strong class="text-sm font-medium text-foreground">{event["summary"]}</strong>
                  <span class="inline-flex items-center rounded-full border bg-muted/[0.05] px-2 py-0.5 text-[0.65rem] text-muted-foreground">
                    {event["event_type"]}
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
                <details :if={event_details?(event)} class="mt-3">
                  <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-primary hover:text-primary cursor-pointer select-none">
                    View event details
                  </summary>
                  <pre
                    :if={is_binary(event["body"]) and event["body"] != ""}
                    class="mt-3 p-3 border rounded-lg bg-muted/[0.03] text-xs text-muted-foreground whitespace-pre-wrap break-words"
                  >{event["body"]}</pre>
                  <pre
                    :if={map_size(event["payload"] || %{}) > 0}
                    class="mt-3 p-3 max-h-72 overflow-auto border rounded-lg bg-muted/[0.03] text-xs font-mono whitespace-pre-wrap break-all"
                  >{Jason.encode!(event["payload"], pretty: true)}</pre>
                </details>
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

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
end
