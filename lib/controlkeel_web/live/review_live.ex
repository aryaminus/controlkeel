defmodule ControlKeelWeb.ReviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Review")
     |> assign(:review, nil)
     |> assign(:diff_chunks, [])
     |> assign(:response_form, response_form())
     |> assign(:review_url, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case parse_integer(id) do
      {:ok, review_id} ->
        case Mission.get_review_with_context(review_id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Review not found.")
             |> assign(:review, nil)
             |> assign(:diff_chunks, [])
             |> assign(:review_url, nil)}

          review ->
            {:noreply, assign_review(socket, review)}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid review id.")}
    end
  end

  @impl true
  def handle_event("respond", %{"review_response" => params}, socket) do
    review = socket.assigns.review

    annotations =
      case String.trim(params["annotation_text"] || "") do
        "" -> %{}
        text -> %{"browser_notes" => text}
      end

    case Mission.respond_review(review, %{
           "decision" => params["decision"],
           "feedback_notes" => params["feedback_notes"],
           "annotations" => annotations,
           "reviewed_by" => "browser"
         }) do
      {:ok, updated_review} ->
        {:noreply,
         socket
         |> assign_review(updated_review)
         |> put_flash(:info, "Review response saved.")}

      {:error, {:invalid_arguments, message}} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Review not found.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to respond to review: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <%= if @review do %>
          <div class="ck-section-header">
            <div>
              <p class="ck-kicker">Browser Review</p>
              <h1 class="ck-section-title">{@review.title}</h1>
              <p class="ck-lead ck-lead-tight">
                Review type: {String.capitalize(@review.review_type)}. Task: {if @review.task,
                  do: @review.task.title,
                  else: "session-level submission"}.
              </p>
            </div>
            <a class="ck-link" href={~p"/missions/#{@review.session_id}"}>Open mission</a>
          </div>

          <div class="ck-stat-grid">
            <div class="ck-card ck-stat-card" id="review-status-card">
              <p class="ck-mini-label">Status</p>
              <strong>{String.capitalize(@review.status)}</strong>
            </div>
            <div class="ck-card ck-stat-card">
              <p class="ck-mini-label">Phase</p>
              <strong>{review_phase(@review)}</strong>
            </div>
            <div class="ck-card ck-stat-card">
              <p class="ck-mini-label">Submitted by</p>
              <strong>{@review.submitted_by || "agent"}</strong>
            </div>
            <div class="ck-card ck-stat-card">
              <p class="ck-mini-label">Shareable URL</p>
              <a class="ck-link" href={@review_url}>{@review_url}</a>
            </div>
          </div>

          <div class="ck-grid ck-grid-dashboard" style="margin-top: 1rem;">
            <div class="space-y-4">
              <article class="ck-card" id="review-submission-body">
                <p class="ck-mini-label">Submission</p>
                <pre class="ck-code-block whitespace-pre-wrap">{@review.submission_body}</pre>
              </article>

              <article
                :if={
                  present_plan_context?(@review, "alignment_context") or
                    present_plan_context?(@review, "consulted_roles")
                }
                class="ck-card"
                id="review-alignment-card"
              >
                <div class="ck-finding-head">
                  <div>
                    <p class="ck-mini-label">Alignment context</p>
                    <h2>Human context gathered before execution</h2>
                  </div>
                </div>
                <div class="mt-4 space-y-4">
                  <div :if={present_plan_context?(@review, "alignment_context")}>
                    <p class="ck-mini-label">Context that shaped the plan</p>
                    <ul class="list-disc space-y-2 pl-5 text-sm text-slate-700">
                      <li :for={entry <- plan_context(@review, "alignment_context")}>{entry}</li>
                    </ul>
                  </div>
                  <div :if={present_plan_context?(@review, "consulted_roles")}>
                    <p class="ck-mini-label">Roles consulted</p>
                    <div class="flex flex-wrap gap-2">
                      <span
                        :for={role <- plan_context(@review, "consulted_roles")}
                        class="ck-pill ck-pill-neutral"
                      >
                        {role}
                      </span>
                    </div>
                  </div>
                </div>
              </article>

              <article :if={@review.previous_review} class="ck-card" id="review-diff-card">
                <div class="ck-finding-head">
                  <div>
                    <p class="ck-mini-label">Revision diff</p>
                    <h2>Compared with review #{@review.previous_review_id}</h2>
                  </div>
                  <span class="ck-pill ck-pill-neutral">
                    Previous: {String.capitalize(@review.previous_review.status)}
                  </span>
                </div>
                <div class="mt-4 space-y-3">
                  <%= for chunk <- @diff_chunks do %>
                    <div class={diff_chunk_class(chunk.kind)}>
                      <p class="ck-mini-label">{diff_chunk_label(chunk.kind)}</p>
                      <pre class="ck-code-block whitespace-pre-wrap">{chunk.text}</pre>
                    </div>
                  <% end %>
                </div>
              </article>
            </div>

            <div class="space-y-4">
              <article class="ck-card" id="review-response-card">
                <div class="ck-finding-head">
                  <div>
                    <p class="ck-mini-label">Respond</p>
                    <h2>Approve, deny, or annotate</h2>
                  </div>
                  <span class={review_status_pill_class(@review.status)}>
                    {String.capitalize(@review.status)}
                  </span>
                </div>

                <.form for={@response_form} id="review-response-form" phx-submit="respond">
                  <div class="space-y-4">
                    <.input
                      field={@response_form[:decision]}
                      type="select"
                      label="Decision"
                      options={[{"Approve", "approved"}, {"Deny", "denied"}]}
                    />

                    <.input
                      field={@response_form[:feedback_notes]}
                      type="textarea"
                      label="Feedback notes"
                      rows="6"
                    />

                    <.input
                      field={@response_form[:annotation_text]}
                      type="textarea"
                      label="Annotations"
                      rows="5"
                    />

                    <button
                      class="ck-button ck-button-primary"
                      id="review-response-submit"
                      type="submit"
                    >
                      Save response
                    </button>
                  </div>
                </.form>
              </article>

              <article class="ck-card" id="review-audit-card">
                <p class="ck-mini-label">Audit trail</p>
                <div class="ck-finding-list">
                  <article class="ck-finding-item">
                    <div class="ck-finding-head">
                      <h3>Submitted</h3>
                      <span class="ck-pill ck-pill-neutral">{format_dt(@review.inserted_at)}</span>
                    </div>
                    <p class="ck-note">By {@review.submitted_by || "agent"}</p>
                  </article>
                  <article :if={@review.responded_at} class="ck-finding-item">
                    <div class="ck-finding-head">
                      <h3>Responded</h3>
                      <span class={review_status_pill_class(@review.status)}>
                        {String.capitalize(@review.status)}
                      </span>
                    </div>
                    <p class="ck-note">At {format_dt(@review.responded_at)}</p>
                    <p class="ck-note">By {@review.reviewed_by || "human"}</p>
                    <p :if={present?(@review.feedback_notes)} class="ck-note">
                      {@review.feedback_notes}
                    </p>
                  </article>
                </div>
              </article>
            </div>
          </div>
        <% else %>
          <div class="ck-card" id="review-missing">
            <p class="ck-mini-label">Browser Review</p>
            <h1 class="ck-section-title">Review not found</h1>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp assign_review(socket, review) do
    socket
    |> assign(:review, review)
    |> assign(:page_title, review.title)
    |> assign(:review_url, ControlKeelWeb.Endpoint.url() <> "/reviews/#{review.id}")
    |> assign(:diff_chunks, diff_chunks(review))
    |> assign(:response_form, response_form(review))
  end

  defp response_form(review \\ nil) do
    to_form(
      %{
        "decision" => default_decision(review),
        "feedback_notes" => (review && review.feedback_notes) || "",
        "annotation_text" => annotation_text(review)
      },
      as: :review_response
    )
  end

  defp default_decision(nil), do: "approved"
  defp default_decision(review) when review.status in ["approved", "denied"], do: review.status
  defp default_decision(_review), do: "approved"

  defp annotation_text(nil), do: ""

  defp annotation_text(review) do
    review.annotations
    |> Kernel.||(%{})
    |> case do
      %{"browser_notes" => notes} -> notes
      _ -> ""
    end
  end

  defp diff_chunks(%{previous_review: nil}), do: []

  defp diff_chunks(review) do
    previous_lines = String.split(review.previous_review.submission_body || "", "\n")
    current_lines = String.split(review.submission_body || "", "\n")

    previous_lines
    |> List.myers_difference(current_lines)
    |> Enum.map(fn
      {:eq, lines} -> %{kind: :unchanged, text: Enum.join(lines, "\n")}
      {:ins, lines} -> %{kind: :added, text: Enum.join(lines, "\n")}
      {:del, lines} -> %{kind: :removed, text: Enum.join(lines, "\n")}
    end)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  defp diff_chunk_class(:added),
    do: "rounded-2xl border border-emerald-200 bg-emerald-50/80 p-4"

  defp diff_chunk_class(:removed),
    do: "rounded-2xl border border-rose-200 bg-rose-50/80 p-4"

  defp diff_chunk_class(:unchanged),
    do: "rounded-2xl border border-slate-200 bg-slate-50/80 p-4"

  defp diff_chunk_label(:added), do: "Added"
  defp diff_chunk_label(:removed), do: "Removed"
  defp diff_chunk_label(:unchanged), do: "Unchanged"

  defp review_status_pill_class("approved"), do: "ck-pill ck-pill-low"
  defp review_status_pill_class("denied"), do: "ck-pill ck-pill-high"
  defp review_status_pill_class("superseded"), do: "ck-pill ck-pill-medium"
  defp review_status_pill_class(_status), do: "ck-pill ck-pill-neutral"

  defp review_phase(review) do
    review
    |> Map.get(:task)
    |> case do
      nil -> "review"
      task -> Mission.review_gate_status(task)["phase"]
    end
  end

  defp format_dt(nil), do: "pending"
  defp format_dt(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp plan_context(review, key) do
    get_in(review.metadata || %{}, ["plan_refinement", key]) || []
  end

  defp present_plan_context?(review, key) do
    plan_context(review, key) != []
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end
end
