defmodule ControlKeelWeb.SessionFindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope
  alias ControlKeelWeb.FindingComponents

  @refresh_interval_ms 2_000
  @filters ~w(all blocked open resolved)

  # Collections skipped on refetch: findings page reads findings only.
  # Uses `LIMIT 0` (valid Ecto, returns []) instead of loading them.
  @refresh_opts [tasks_limit: 0, invocations_limit: 0, reviews_limit: 0]

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
             |> assign(:open_ids, MapSet.new())
             |> assign(:fixes, %{})
             |> assign(:reject_id, nil)
             |> assign(:reject_reason, "")
             |> assign(:filter, "all")
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
      %{label: "Findings", to: nil}
    ])
    |> assign(:page_title, "#{session.title} — Findings")
    |> assign(:session, session)
    |> assign_view()
  end

  # Derives the filtered + sorted list and the chip counts from the session.
  # Called after every session refresh and every filter change.
  defp assign_view(socket) do
    findings = socket.assigns.session.findings || []

    view =
      findings
      |> Enum.filter(&matches_filter?(&1, socket.assigns.filter))
      |> sort_findings()

    socket
    |> assign(:counts, counts(findings))
    |> assign(:findings_view, view)
  end

  @impl true
  def handle_info(:refresh, socket) do
    case Mission.get_session_context(socket.assigns.session.id, @refresh_opts) do
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
  def handle_event("set_filter", %{"filter" => filter}, socket) when filter in @filters do
    {:noreply, socket |> assign(:filter, filter) |> assign_view()}
  end

  def handle_event("set_filter", _params, socket), do: {:noreply, socket}

  # Accordion toggle. Open state lives in assigns so the 2s poll re-render
  # never collapses an expanded row; the guided fix is computed lazily on
  # first open and cached under the finding id.
  @impl true
  def handle_event("toggle_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      if MapSet.member?(socket.assigns.open_ids, finding_id) do
        {:noreply, assign(socket, :open_ids, MapSet.delete(socket.assigns.open_ids, finding_id))}
      else
        fix = Map.get(socket.assigns.fixes, finding_id) || Mission.auto_fix_for_finding(finding)
        emit_autofix_event(:viewed, finding, fix)

        {:noreply,
         socket
         |> assign(:open_ids, MapSet.put(socket.assigns.open_ids, finding_id))
         |> assign(:fixes, Map.put(socket.assigns.fixes, finding_id, fix))}
      end
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("copy_fix_prompt", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         %{"agent_prompt" => prompt} = fix <- Map.get(socket.assigns.fixes, finding_id),
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
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding approved.")
       |> refresh_session()}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  # Reject opens the reason dialog; `set_reject_reason` tracks the input,
  # `confirm_reject_finding` executes, `cancel_reject` closes the dialog
  # (also wired as the modal's on_close for backdrop/X/Escape).
  @impl true
  def handle_event("reject_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = _finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      {:noreply,
       socket
       |> assign(:reject_id, finding_id)
       |> assign(:reject_reason, "")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_reject_reason", %{"reject_reason" => reason}, socket) do
    {:noreply, assign(socket, :reject_reason, reason)}
  end

  @impl true
  def handle_event("cancel_reject", _params, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")}
  end

  @impl true
  def handle_event("confirm_reject_finding", _params, socket) do
    with finding_id when not is_nil(finding_id) <- socket.assigns.reject_id,
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <-
           Mission.reject_finding(finding, reject_reason(socket), actor_opts(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding rejected.")
       |> assign(:reject_id, nil)
       |> assign(:reject_reason, "")
       |> refresh_session()}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  @impl true
  def handle_event("escalate_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.escalate_finding(finding, actor_opts(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding escalated.")
       |> refresh_session()}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not escalate finding.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_title title="Findings" />

      <%= if @session.findings == [] do %>
        <div class="rounded-2xl border bg-card px-5 py-12 text-center">
          <p class="text-base font-medium text-foreground">No findings yet.</p>
          <p class="mt-1 text-sm text-muted-foreground">
            ControlKeel is monitoring every agent action.
          </p>
        </div>
      <% else %>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <p class="text-sm text-muted-foreground">
            {@counts.all} {if @counts.all == 1, do: "finding", else: "findings"}
          </p>

          <div role="group" aria-label="Filter findings" class="flex flex-wrap items-center gap-2">
            <button
              :for={{key, label, count_key} <- filter_options()}
              type="button"
              id={"filter-#{key}"}
              phx-click="set_filter"
              phx-value-filter={key}
              aria-pressed={@filter == key}
              class={[
                "inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50",
                if(@filter == key,
                  do: "bg-primary text-primary-foreground",
                  else: "bg-muted text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              <.icon name={filter_icon(key)} class="size-3.5" />
              {label}
              <span class="tabular-nums">{Map.fetch!(@counts, count_key)}</span>
            </button>
          </div>
        </div>

        <%= if @findings_view == [] do %>
          <div class="rounded-2xl border bg-card px-5 h-72 text-center flex items-center flex-col justify-center gap-3">
            <p class="text-base font-medium text-foreground">No findings match this filter.</p>
            <div class="mt-3">
              <.button variant="outline" phx-click="set_filter" phx-value-filter="all">
                Show all findings
              </.button>
            </div>
          </div>
        <% else %>
          <ul id="session-findings-list" class="space-y-6">
            <.finding_card
              :for={finding <- @findings_view}
              finding={finding}
              open?={MapSet.member?(@open_ids, finding.id)}
              fix={Map.get(@fixes, finding.id)}
            />
          </ul>

          <.modal
            :if={reject_target(@reject_id, @session.findings)}
            id="reject-finding-modal"
            title="Reject finding"
            on_close="cancel_reject"
            width="max-w-lg"
          >
            <form
              id="reject-reason-form"
              class="space-y-4"
              phx-change="set_reject_reason"
              phx-submit="confirm_reject_finding"
            >
              <p class="text-sm text-muted-foreground">
                <span class="font-medium text-foreground">
                  {reject_target(@reject_id, @session.findings).title}
                </span>
                <span
                  :if={reject_target(@reject_id, @session.findings).rule_id}
                  class="font-mono text-xs"
                >
                  · {reject_target(@reject_id, @session.findings).rule_id}
                </span>
              </p>
              <.input
                type="text"
                name="reject_reason"
                label="Reason"
                value={@reject_reason}
                placeholder="False positive, duplicate, out of scope…"
                class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground shadow-sm transition placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/50"
              />
              <div class="flex items-center justify-end gap-2">
                <.button variant="secondary" type="button" phx-click="cancel_reject">
                  Cancel
                </.button>
                <.button variant="destructive" type="submit">Confirm reject</.button>
              </div>
            </form>
          </.modal>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :finding, :map, required: true
  attr :open?, :boolean, required: true
  attr :fix, :map, default: nil

  defp finding_card(assigns) do
    ~H"""
    <li
      id={"finding-#{@finding.id}"}
      class="relative overflow-hidden rounded-xl border bg-card shadow-card"
    >
      <button
        type="button"
        id={"finding-toggle-#{@finding.id}"}
        phx-click="toggle_finding"
        phx-value-id={@finding.id}
        aria-expanded={@open?}
        aria-controls={"finding-detail-#{@finding.id}"}
        class="relative flex w-full cursor-pointer items-center gap-4 py-4 pr-5 pl-6 text-left transition hover:bg-muted/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary/50"
      >
        <span
          aria-hidden="true"
          style="position:absolute;top:0;bottom:0;left:0;width:4px;"
          class={severity_bar(@finding)}
        >
        </span>

        <div class="flex w-full items-center gap-4 px-4">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-muted">
            <.icon
              name={category_icon(@finding.category)}
              class={["size-5", category_icon_tone(@finding.severity)]}
            />
          </span>

          <span class="min-w-0 flex-1">
            <span class={[
              "block font-medium",
              if(resolved?(@finding), do: "text-muted-foreground", else: "text-foreground")
            ]}>
              <.finding_title title={@finding.title} />
            </span>
            <span class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
              <%= for {{kind, value}, index} <- Enum.with_index(meta_items(@finding)) do %>
                <span
                  :if={index > 0}
                  aria-hidden="true"
                  class="opacity-50 text-foreground font-medium"
                >
                  -
                </span>
                <span
                  :if={kind == :path}
                  title={value}
                  class="max-w-[20rem] truncate font-mono"
                >
                  {value}
                </span>
                <span :if={kind == :rule} class="font-mono">
                  {value}
                </span>
                <span :if={kind == :category} class="capitalize">{value}</span>
                <time
                  :if={kind == :time}
                  datetime={iso8601(@finding.inserted_at)}
                  title={event_timestamp(@finding.inserted_at)}
                  class="tabular-nums"
                >
                  {relative_time(@finding.inserted_at)}
                </time>
              <% end %>
            </span>
          </span>

          <span class="flex shrink-0 items-center gap-2">
            <span class={[
              "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              severity_pill(@finding.severity)
            ]}>
              {@finding.severity}
            </span>
            <span class="inline-flex rounded-full bg-muted px-2.5 py-1 text-xs font-semibold capitalize text-muted-foreground ring-1 ring-border">
              {@finding.status}
            </span>
            <.icon
              name="hero-chevron-down"
              class={["size-4 text-muted-foreground transition-transform", @open? && "rotate-180"]}
            />
          </span>
        </div>
      </button>

      <div
        :if={@open?}
        id={"finding-detail-#{@finding.id}"}
        class="border-t p-4 space-y-6"
      >
        <div
          :if={meta_value(@finding, "path") || meta_value(@finding, "matched_text_redacted")}
          class="space-y-1"
        >
          <p :if={meta_value(@finding, "path")} class="text-xs text-muted-foreground">
            <span class="font-medium text-foreground">Path:</span>
            <span class="font-mono">{meta_value(@finding, "path")}</span>
          </p>
          <p
            :if={meta_value(@finding, "matched_text_redacted")}
            class="text-xs text-muted-foreground"
          >
            <span class="font-medium text-foreground">Matched:</span>
            <span class="font-mono">{meta_value(@finding, "matched_text_redacted")}</span>
          </p>
        </div>

        <FindingComponents.finding_fix_detail
          finding={@finding}
          fix={@fix}
          copy_event="copy_fix_prompt"
        />

        <div
          :if={@finding.status in ["open", "blocked"]}
          class="flex flex-wrap items-center gap-2"
        >
          <.button phx-click="approve_finding" phx-value-id={@finding.id}>
            <.icon name="hero-check" class="size-3.5" /> Approve
          </.button>
          <.button variant="outline" phx-click="escalate_finding" phx-value-id={@finding.id}>
            <.icon name="hero-arrow-up" class="size-3.5" /> Escalate
          </.button>
          <.button variant="destructive" phx-click="reject_finding" phx-value-id={@finding.id}>
            <.icon name="hero-x-mark" class="size-3.5" /> Reject
          </.button>
        </div>
      </div>
    </li>
    """
  end

  # Renders `code` segments inline when backticks are balanced; strips stray
  # backticks otherwise so a title never shows a dangling "`".
  attr :title, :string, default: ""

  defp finding_title(assigns) do
    assigns = assign(assigns, :parts, title_parts(assigns.title))

    ~H"""
    <span
      :for={{kind, text} <- @parts}
      class={
        if kind == :code,
          do: "rounded bg-muted px-1 py-0.5 font-mono text-[0.85em]",
          else: nil
      }
    >
      {text}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # View helpers
  # ---------------------------------------------------------------------------

  defp filter_options do
    [
      {"all", "All", :all},
      {"blocked", "Blocked", :blocked},
      {"open", "Open", :open},
      {"resolved", "Resolved", :resolved}
    ]
  end

  defp filter_icon("all"), do: "hero-squares-2x2"
  defp filter_icon("blocked"), do: "hero-lock-closed"
  defp filter_icon("open"), do: "hero-clock"
  defp filter_icon("resolved"), do: "hero-check-circle"
  defp filter_icon(_), do: "hero-list-bullet"

  # Category says what kind of problem it is; severity is carried by the
  # left bar and the pill, so the icon deliberately does not repeat it.
  # NOTE: icon names must already exist in the compiled app.css — the
  # heroicons Tailwind plugin only emits icons seen at build time, so any
  # newly introduced name stays invisible until `mix assets.build` runs.
  # Every name below was verified present in priv/static/assets/css/app-*.css.
  defp category_icon("security"), do: "hero-shield-exclamation"
  defp category_icon("secret"), do: "hero-key"
  defp category_icon("privacy"), do: "hero-lock-closed"
  defp category_icon("compliance"), do: "hero-scale"
  defp category_icon("governance"), do: "hero-document-check"
  defp category_icon("cost"), do: "hero-currency-dollar"
  defp category_icon("token"), do: "hero-cpu-chip"
  defp category_icon("review"), do: "hero-document-text"

  defp category_icon(category) when category in ["quality", "code_quality"],
    do: "hero-check-badge"

  defp category_icon("correctness"), do: "hero-puzzle-piece"
  defp category_icon("completeness"), do: "hero-list-bullet"
  defp category_icon("dependencies"), do: "hero-link"
  defp category_icon("destructive_operation"), do: "hero-no-symbol"
  defp category_icon("ops"), do: "hero-server"
  defp category_icon("health"), do: "hero-chart-bar"
  defp category_icon("proof"), do: "hero-shield-check"
  defp category_icon("problem"), do: "hero-exclamation-triangle"
  defp category_icon("research"), do: "hero-beaker"
  defp category_icon("unverified"), do: "hero-information-circle"
  defp category_icon(_), do: "hero-bolt"

  # Severity tone for the category glyph (currentColor). Tinted chip
  # backgrounds (bg-*/10) are absent from the current CSS bundle, so the
  # chip stays neutral bg-muted and only the glyph takes the tone.
  defp category_icon_tone(severity) when severity in ["critical", "high"], do: "text-destructive"
  defp category_icon_tone(severity) when severity in ["medium", "moderate"], do: "text-warning"
  defp category_icon_tone("low"), do: "text-success"
  defp category_icon_tone(_), do: "text-muted-foreground"

  defp severity_bar(finding) do
    if resolved?(finding) do
      # NOTE: bg-border is absent from the compiled CSS bundle; bg-muted
      # keeps the strip visible (dimmed) instead of transparent.
      "bg-muted"
    else
      severity_bar_color(finding.severity)
    end
  end

  defp severity_bar_color(severity) when severity in ["critical", "high"], do: "bg-destructive"
  defp severity_bar_color(severity) when severity in ["medium", "moderate"], do: "bg-warning"
  defp severity_bar_color("low"), do: "bg-success"
  defp severity_bar_color(_), do: "bg-muted"

  defp severity_pill(severity) when severity in ["critical", "high"],
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp severity_pill(severity) when severity in ["medium", "moderate"],
    do: "bg-warning/10 text-warning ring-warning/20"

  defp severity_pill("low"), do: "bg-success/10 text-success ring-success/20"
  defp severity_pill(_), do: "bg-muted text-muted-foreground ring-border"

  defp resolved?(finding), do: finding.status not in ["open", "blocked"]

  defp meta_value(%{metadata: %{} = metadata}, key), do: metadata[key]
  defp meta_value(_finding, _key), do: nil

  # Present meta segments in display order. Separators render between
  # segments, so missing values (no path, no rule_id) leave no dangling
  # dashes. The timestamp always renders ("unknown" fallback).
  defp meta_items(finding) do
    [
      {:path, meta_value(finding, "path")},
      {:rule, finding.rule_id},
      {:category, finding.category},
      {:time, true}
    ]
    |> Enum.reject(fn {_kind, value} -> value in [nil, ""] end)
  end

  defp title_parts(title) do
    title = title || ""
    segments = String.split(title, "`")

    if rem(length(segments), 2) == 1 do
      segments
      |> Enum.with_index()
      |> Enum.reject(fn {text, _index} -> text == "" end)
      |> Enum.map(fn {text, index} -> {if(rem(index, 2) == 1, do: :code, else: :text), text} end)
    else
      [{:text, String.replace(title, "`", "")}]
    end
  end

  # ---------------------------------------------------------------------------
  # Filtering, sorting, counting
  # ---------------------------------------------------------------------------

  defp matches_filter?(_finding, "all"), do: true
  defp matches_filter?(finding, "blocked"), do: finding.status == "blocked"
  defp matches_filter?(finding, "open"), do: finding.status == "open"
  defp matches_filter?(finding, "resolved"), do: resolved?(finding)
  defp matches_filter?(_finding, _other), do: true

  defp counts(findings) do
    %{
      all: length(findings),
      blocked: Enum.count(findings, &(&1.status == "blocked")),
      open: Enum.count(findings, &(&1.status == "open")),
      resolved: Enum.count(findings, &resolved?/1)
    }
  end

  # Newest first, and nothing else. Deliberately no status/severity
  # bucketing: re-sorting on disposition would relocate the row from under
  # the user's cursor (and the 2s poll would keep moving rows), so positions
  # stay stable while triaging. The status filter chips and the resolved
  # dimming separate done from todo instead.
  defp sort_findings(findings) do
    # id breaks same-second ties (inserted_at has second precision).
    Enum.sort_by(findings, &{unix(&1.inserted_at), &1.id}, :desc)
  end

  defp unix(%DateTime{} = timestamp), do: DateTime.to_unix(timestamp)
  defp unix(_), do: 0

  # ---------------------------------------------------------------------------
  # Time
  # ---------------------------------------------------------------------------

  defp event_timestamp(nil), do: "unknown"
  defp event_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d")

  defp iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp iso8601(_), do: nil

  defp relative_time(nil), do: "unknown"

  defp relative_time(%DateTime{} = timestamp) do
    diff = DateTime.diff(DateTime.utc_now(), timestamp, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      diff < 7 * 86_400 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(timestamp, "%b %d, %Y")
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp refresh_session(socket) do
    case Mission.get_session_context(socket.assigns.session.id, @refresh_opts) do
      nil -> SessionScope.session_not_found(socket)
      session -> assign_session(socket, session)
    end
  end

  defp reject_target(nil, _findings), do: nil
  defp reject_target(_id, nil), do: nil
  defp reject_target(id, findings), do: Enum.find(findings, &(&1.id == id))

  defp reject_reason(socket) do
    case String.trim(socket.assigns.reject_reason) do
      "" -> nil
      reason -> reason
    end
  end

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

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_value), do: {:error, :invalid_id}

  defp actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> [actor_source: "web", actor_identifier: "web"]
      user -> [actor_source: "web", actor_user_id: user.id, actor_identifier: user.email]
    end
  end
end
