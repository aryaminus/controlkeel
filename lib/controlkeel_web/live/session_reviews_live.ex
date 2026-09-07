defmodule ControlKeelWeb.SessionReviewsLive do
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
    {:noreply, assign_reviews(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-card border rounded-2xl shadow-card overflow-clip">
      <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
            <tr>
              <th class="px-5 py-3 font-semibold">Review</th>
              <th class="px-5 py-3 font-semibold">Task</th>
              <th class="px-5 py-3 font-semibold">Type</th>
              <th class="px-5 py-3 font-semibold">Submitted by</th>
              <th class="px-5 py-3 font-semibold w-px whitespace-nowrap">Date</th>
              <th class="px-5 py-3 font-semibold w-px whitespace-nowrap text-right">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= for review <- @reviews do %>
              <tr class="transition hover:bg-muted/30">
                <td class="px-5 py-4">
                  <.link
                    navigate={~p"/sessions/#{@session.id}/reviews/#{review.id}"}
                    class="font-medium text-foreground hover:text-primary"
                  >
                    {review.title}
                  </.link>
                </td>
                <td class="px-5 py-4 text-muted-foreground">
                  {if review.task, do: review.task.title, else: "Session-level"}
                </td>
                <td class="px-5 py-4 text-muted-foreground capitalize">{review.review_type}</td>
                <td class="px-5 py-4 text-muted-foreground">{review.submitted_by || "agent"}</td>
                <td class="px-5 py-4 text-muted-foreground whitespace-nowrap w-px font-mono tabular-nums tracking-tight">
                  {event_timestamp(review.inserted_at)}
                </td>
                <td class="px-5 py-4 text-right whitespace-nowrap w-px">
                  <span class={review_status_pill_class(review.status)}>{review.status}</span>
                </td>
              </tr>
            <% end %>
            <%= if @reviews == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No reviews yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Agent plan, diff, or completion submissions for this session appear here.
                  </p>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    """
  end

  defp mount_session(socket, session) do
    if connected?(socket), do: schedule_refresh()

    socket
    |> assign(:page_title, "#{session.title} — Reviews")
    |> assign(:session, session)
    |> assign_reviews()
  end

  defp assign_reviews(socket) do
    session_id = socket.assigns.session.id

    socket
    |> assign(:reviews, Mission.list_reviews_for_session(session_id))
    |> assign(:review_counts, Mission.session_review_counts(session_id))
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  defp review_status_pill_class("approved"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp review_status_pill_class("denied"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp review_status_pill_class("superseded"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp review_status_pill_class(_status),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-info/10 text-info ring-info/20"
end
