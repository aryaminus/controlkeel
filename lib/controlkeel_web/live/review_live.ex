defmodule ControlKeelWeb.ReviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Review")
     |> assign(:review, nil)
     |> assign(:diff_chunks, [])
     |> assign(:response_form, response_form())}
  end

  # Cross-session ownership is enforced by matching review.session_id against
  # the id path segment; org-level access is enforced via the shared
  # Accounts.session_accessible?/2 gate (issue #83), plus a URL slug
  # agreement check so the org/workspace segments can't be swapped.
  @impl true
  def handle_params(
        %{"id" => sid, "rid" => rid, "org_slug" => org_slug, "ws_slug" => ws_slug},
        _uri,
        socket
      ) do
    with {:ok, review_id} <- parse_integer(rid),
         {:ok, session_id} <- parse_integer(sid) do
      case Mission.get_review_with_context(review_id) do
        nil ->
          {:noreply, review_not_found(socket)}

        %{session_id: ^session_id} = review ->
          session = review.session

          cond do
            not Accounts.session_accessible?(session, socket.assigns[:current_user]) ->
              {:noreply, review_not_found(socket)}

            check_session_scope(session, org_slug, ws_slug) != :ok ->
              {:noreply, review_not_found(socket)}

            true ->
              {:noreply, assign_review(socket, review)}
          end

        _review ->
          {:noreply, review_not_found(socket)}
      end
    else
      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid review id.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("respond", %{"review_response" => params}, socket) do
    case socket.assigns.review do
      nil ->
        {:noreply, put_flash(socket, :error, "Review not found.")}

      review ->
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
            {:noreply,
             put_flash(socket, :error, "Failed to respond to review: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= if @review do %>
        <.page_title title={@review.title} />

        <%!-- Stat row --%>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Review type</p>
            <p class="mt-2 text-xl font-semibold capitalize text-foreground/90">
              {@review.review_type}
            </p>
          </article>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Task</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {if @review.task, do: @review.task.title, else: "session-level"}
            </p>
          </article>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Phase</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">{review_phase(@review)}</p>
          </article>
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Submitted by</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@review.submitted_by || "agent"}
            </p>
          </article>
        </div>

        <div class="grid gap-6 lg:grid-cols-3">
          <div class="space-y-6 lg:col-span-2">
            <article class="rounded-2xl border bg-card p-5 shadow-card" id="review-submission-body">
              <div class="flex items-center justify-between gap-3">
                <.card_title>Submission</.card_title>
                <.button
                  type="button"
                  variant="outline"
                  phx-click={
                    JS.dispatch("phx:copy-to-clipboard", detail: %{text: @review.submission_body})
                  }
                >
                  <.icon name="hero-clipboard" class="size-3.5" /> Copy
                </.button>
              </div>
              <pre class="mt-4 rounded-lg bg-muted p-4 whitespace-pre-wrap break-words font-mono text-xs leading-6 overflow-y-auto max-h-96">{@review.submission_body}</pre>
            </article>

            <article
              :if={
                present_plan_context?(@review, "alignment_context") or
                  present_plan_context?(@review, "consulted_roles")
              }
              class="rounded-2xl border bg-card p-5 shadow-card"
              id="review-alignment-card"
            >
              <.card_title>Alignment context</.card_title>
              <p class="mt-1 text-sm text-muted-foreground">
                Human context gathered before execution
              </p>
              <div class="mt-4 space-y-4">
                <div :if={present_plan_context?(@review, "alignment_context")}>
                  <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                    Context that shaped the plan
                  </p>
                  <ul class="mt-2 list-disc space-y-2 pl-5 text-sm text-muted-foreground">
                    <li :for={entry <- plan_context(@review, "alignment_context")}>{entry}</li>
                  </ul>
                </div>
                <div :if={present_plan_context?(@review, "consulted_roles")}>
                  <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                    Roles consulted
                  </p>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <span
                      :for={role <- plan_context(@review, "consulted_roles")}
                      class="inline-flex rounded-full bg-success/10 px-2.5 py-1 text-xs font-medium text-success"
                    >
                      {role}
                    </span>
                  </div>
                </div>
              </div>
            </article>

            <article
              :if={present_semantic_boundaries?(@review)}
              class="rounded-2xl border bg-card p-5 shadow-card"
              id="review-semantic-boundaries-card"
            >
              <.card_title>Semantic boundaries</.card_title>
              <p class="mt-1 text-sm text-muted-foreground">Agent execution guardrails</p>
              <div class="mt-4 space-y-4">
                <div :for={boundary <- semantic_boundary_sections(@review)}>
                  <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                    {boundary.label}
                  </p>
                  <ul class="mt-2 list-disc space-y-2 pl-5 text-sm text-muted-foreground">
                    <li :for={entry <- boundary.entries}>{entry}</li>
                  </ul>
                </div>
              </div>
            </article>

            <article
              :if={@review.previous_review}
              class="rounded-2xl border bg-card p-5 shadow-card"
              id="review-diff-card"
            >
              <div class="flex items-center justify-between gap-3">
                <div>
                  <.card_title>Revision diff</.card_title>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Compared with review #{@review.previous_review_id}
                  </p>
                </div>
                <span class="inline-flex rounded-full border px-2.5 py-1 text-xs text-muted-foreground">
                  Previous: {String.capitalize(@review.previous_review.status)}
                </span>
              </div>
              <div class="mt-4 space-y-3 overflow-y-auto max-h-96">
                <%= for chunk <- @diff_chunks do %>
                  <div class={diff_chunk_class(chunk.kind)}>
                    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {diff_chunk_label(chunk.kind)}
                    </p>
                    <pre class="mt-2 whitespace-pre-wrap break-words font-mono text-xs leading-6">{chunk.text}</pre>
                  </div>
                <% end %>
              </div>
            </article>

            <article
              class="rounded-2xl border bg-card p-5 shadow-card"
              id="review-revisions-card"
            >
              <div class="flex items-center justify-between gap-3">
                <.card_title>Revisions</.card_title>
                <span class="inline-flex rounded-full border px-2.5 py-1 text-xs text-muted-foreground">
                  {length(@review.revisions)}
                </span>
              </div>
              <p class="mt-1 text-sm text-muted-foreground">
                Later resubmissions of this review
              </p>
              <ul class="mt-4 space-y-3">
                <li
                  :for={revision <- @review.revisions}
                  class="flex items-center justify-between gap-3"
                >
                  <div>
                    <.link
                      navigate={
                        ~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{revision.session_id || @review.session_id}/reviews/#{revision.id}"
                      }
                      class="font-medium text-sm hover:text-primary"
                    >
                      {revision.title}
                    </.link>
                    <p class="mt-0.5 text-xs text-muted-foreground">
                      {String.capitalize(revision.review_type)} · {format_dt(revision.inserted_at)}
                    </p>
                  </div>
                  <span class={status_text_class(revision.status)}>
                    {String.capitalize(revision.status)}
                  </span>
                </li>
              </ul>
            </article>
          </div>

          <div
            class="rounded-2xl h-fit border bg-card p-5 shadow-card space-y-6"
            id="review-response-card"
          >
            <div class="space-y-3">
              <.card_title>Respond</.card_title>

              <.form for={@response_form} id="review-response-form" phx-submit="respond">
                <div class="flex items-center justify-between gap-3">
                  <span class={status_text_class(@review.status)}>
                    {String.capitalize(@review.status)}
                  </span>

                  <div class="flex items-center gap-2">
                    <.button
                      id="review-response-approve"
                      type="submit"
                      name="review_response[decision]"
                      value="approved"
                      disabled={@review.status != "pending"}
                    >
                      Approve
                    </.button>
                    <.button
                      id="review-response-deny"
                      type="submit"
                      variant="destructive"
                      name="review_response[decision]"
                      value="denied"
                      disabled={@review.status != "pending"}
                    >
                      Deny
                    </.button>
                  </div>
                </div>

                <div class="mt-5 space-y-4">
                  <.textarea
                    field={@response_form[:feedback_notes]}
                    label="Feedback notes"
                    placeholder="Add notes..."
                    class="resize-none h-24"
                  />

                  <.textarea
                    field={@response_form[:annotation_text]}
                    label="Annotations"
                    placeholder="Add notes..."
                    class="resize-none h-24"
                  />
                </div>
              </.form>
            </div>

            <div class="space-y-3">
              <.card_title>Audit trail</.card_title>

              <div class="flex items-start gap-3">
                <div class="flex h-6 w-6 items-center justify-center rounded-full border border-border/80 bg-muted text-muted-foreground shadow-sm">
                  <.icon name="hero-clock" class="size-3.5" />
                </div>
                <div>
                  <p class="text-sm font-semibold text-foreground">Submitted</p>
                  <p class="mt-0.5 text-xs text-muted-foreground">
                    {format_dt(@review.inserted_at)}
                  </p>
                  <p class="mt-0.5 text-xs text-muted-foreground">
                    By {@review.submitted_by || "agent"}
                  </p>
                </div>
              </div>

              <div
                :if={@review.responded_at || @review.status != "pending"}
                class="flex items-start gap-3"
              >
                <div class={[
                  "flex h-6 w-6 items-center justify-center rounded-full border shadow-sm",
                  audit_timeline_icon_class(@review.status)
                ]}>
                  <.icon name={audit_timeline_icon_name(@review.status)} class="size-3.5" />
                </div>
                <div>
                  <p class="text-sm font-semibold text-foreground">
                    {String.capitalize(@review.status)}
                  </p>
                  <p class="mt-0.5 text-xs text-muted-foreground">
                    {format_dt(@review.responded_at || @review.updated_at)}
                  </p>
                  <p :if={@review.reviewed_by} class="mt-0.5 text-xs text-muted-foreground">
                    By {@review.reviewed_by}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <section class="rounded-2xl border bg-card p-5 shadow-card" id="review-missing">
          <.card_title>Review not found</.card_title>
          <p class="mt-2 text-sm text-muted-foreground">
            This review may have been removed or does not belong to this session.
          </p>
        </section>
      <% end %>
    </div>
    """
  end

  defp assign_review(socket, review) do
    session = review.session
    workspace = session.workspace
    org = workspace.org

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
      %{label: "Reviews", to: nil}
    ])
    |> assign(:review, review)
    |> assign(:page_title, review.title)
    |> assign(:diff_chunks, diff_chunks(review))
    |> assign(:response_form, response_form(review))
  end

  # URL slug agreement only — must run after the session_accessible? gate,
  # which is what guarantees a loaded workspace/org (a nil session never
  # reaches here).
  defp check_session_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  # No nav context without a loaded session — redirect instead of rendering
  # the layout with nil assigns (which would crash the sidebar).
  defp review_not_found(socket) do
    socket
    |> put_flash(:error, "Review not found.")
    |> push_navigate(to: ~p"/")
  end

  defp response_form(review \\ nil) do
    to_form(
      %{
        "feedback_notes" => (review && review.feedback_notes) || "",
        "annotation_text" => annotation_text(review)
      },
      as: :review_response
    )
  end

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
    do: "rounded-lg border border-success/20 bg-success/10 p-4"

  defp diff_chunk_class(:removed),
    do: "rounded-lg border border-destructive/20 bg-destructive/10 p-4"

  defp diff_chunk_class(:unchanged),
    do: "rounded-lg border bg-muted p-4"

  defp diff_chunk_label(:added), do: "Added"
  defp diff_chunk_label(:removed), do: "Removed"
  defp diff_chunk_label(:unchanged), do: "Unchanged"

  defp status_text_class("approved"), do: "text-success font-semibold text-sm"
  defp status_text_class("denied"), do: "text-destructive font-semibold text-sm"
  defp status_text_class("superseded"), do: "text-warning font-semibold text-sm"
  defp status_text_class(_status), do: "text-info font-semibold text-sm"

  defp audit_timeline_icon_class("approved"),
    do: "bg-success/20 border-success/40 text-success"

  defp audit_timeline_icon_class("denied"),
    do: "bg-destructive/20 border-destructive/40 text-destructive"

  defp audit_timeline_icon_class("superseded"),
    do: "bg-warning/20 border-warning/40 text-warning"

  defp audit_timeline_icon_class(_status),
    do: "bg-muted border-border text-muted-foreground"

  defp audit_timeline_icon_name("approved"), do: "hero-check"
  defp audit_timeline_icon_name("denied"), do: "hero-x-mark"
  defp audit_timeline_icon_name("superseded"), do: "hero-clock"
  defp audit_timeline_icon_name(_status), do: "hero-clock"

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

  defp plan_context(review, key) do
    get_in(review.metadata || %{}, ["plan_refinement", key]) || []
  end

  defp present_plan_context?(review, key) do
    plan_context(review, key) != []
  end

  defp present_semantic_boundaries?(review) do
    semantic_boundary_sections(review) != []
  end

  defp semantic_boundary_sections(review) do
    [
      {"Allowed semantic changes", "allowed_semantic_changes"},
      {"Forbidden semantic changes", "forbidden_semantic_changes"},
      {"Invariant boundaries", "invariant_boundaries"},
      {"Requires re-approval if", "requires_reapproval_if"},
      {"Harness quality checks", "harness_quality_checks"}
    ]
    |> Enum.map(fn {label, key} -> %{label: label, entries: plan_context(review, key)} end)
    |> Enum.reject(&(&1.entries == []))
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end
end
