defmodule ControlKeelWeb.SessionTranscriptLive do
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
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        {:ok, mount_session(socket, session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()
    {:noreply, assign_transcript(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-card border rounded-2xl shadow-card">
      <div :if={@recent_events == []} class="px-5 py-12 text-center">
        <p class="text-base font-medium text-foreground">No transcript events yet.</p>
        <p class="mt-1 text-sm text-muted-foreground">
          Governed agent and harness actions for this session appear here.
        </p>
      </div>

      <%= if @recent_events != [] do %>
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground [&>tr>th:first-child]:rounded-tl-2xl [&>tr>th:last-child]:rounded-tr-2xl">
            <tr>
              <th class="px-5 py-3 font-semibold">Event</th>
              <th class="px-5 py-3 font-semibold">Family</th>
              <th class="px-5 py-3 font-semibold">Type</th>
              <th class="px-5 py-3 font-semibold">Actor</th>
              <th class="px-5 py-3 font-semibold w-px whitespace-nowrap">Created</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border [&>tr:last-child>td:first-child]:rounded-bl-2xl [&>tr:last-child>td:last-child]:rounded-br-2xl">
            <tr :for={event <- @recent_events} class="transition hover:bg-muted/30">
              <td class="px-5 py-4 text-foreground break-words">{event["summary"]}</td>
              <td class="px-5 py-4">
                <span class="inline-flex items-center rounded-full bg-muted px-2 py-0.5 text-[0.65rem] font-semibold text-foreground">{family_name(event["event_type"])}</span>
              </td>
              <td class="px-5 py-4">
                <span class="inline-flex items-center rounded-full bg-muted px-2 py-0.5 font-mono text-[0.65rem] text-muted-foreground">
                  {event["event_type"]}
                </span>
              </td>
              <td class="px-5 py-4">
                <span class="inline-flex items-center rounded-md border border-input bg-background px-1.5 py-0.5 text-xs text-muted-foreground">
                  {event["actor"]}
                </span>
              </td>
              <td class="px-5 py-4 text-muted-foreground whitespace-nowrap w-px font-mono text-xs tabular-nums tracking-tight">
                {event_timestamp(event["inserted_at"])}
              </td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp mount_session(socket, session) do
    if connected?(socket), do: schedule_refresh()

    socket
    |> assign(:page_title, "#{session.title} — Transcript")
    |> assign(:session, session)
    |> assign_transcript()
  end

  defp assign_transcript(socket) do
    session_id = socket.assigns.session.id

    socket
    |> assign(:recent_events, Mission.list_session_events(session_id, :all))
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp family_name(event_type) when is_binary(event_type) do
    case String.split(event_type, ".", parts: 2) do
      [family, _rest] -> family
      [family] -> family
      _ -> "other"
    end
  end

  defp family_name(_event_type), do: "other"

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d")
end
