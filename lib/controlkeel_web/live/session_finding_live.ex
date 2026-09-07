defmodule ControlKeelWeb.SessionFindingLive do
  @moduledoc """
  Single finding detail for a session: guided fix, plain-English context,
  security case, audit trail, and disposition controls. Mirrors the finding
  dialog shown by `FindingsLive`. Routed at `/sessions/:id/findings/:finding_id`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Governance.SecurityWorkflow
  alias ControlKeel.Mission
  alias ControlKeel.Mission.FindingPlainEnglish

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id, "finding_id" => finding_id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if Accounts.session_accessible?(session, org_id) do
          mount_finding(socket, session, finding_id)
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        mount_finding(socket, session, finding_id)
    end
  end

  defp mount_finding(socket, session, finding_id) do
    case Mission.get_finding_with_context(finding_id) do
      %{session_id: session_id} = finding when session_id == session.id ->
        if connected?(socket), do: schedule_refresh()

        {:ok,
         socket
         |> assign(:page_title, "#{session.title} — Finding")
         |> assign(:menu_open?, false)
         |> assign(:reject_open?, false)
         |> assign(:reject_reason, "")
         |> assign_finding(session, finding)}

      _other ->
        {:ok,
         socket
         |> put_flash(:error, "Finding not found.")
         |> push_navigate(to: ~p"/sessions/#{session.id}/findings")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_finding_with_context(socket.assigns.finding.id) do
      %{} = finding ->
        {:noreply, assign_finding(socket, socket.assigns.session, finding)}

      _other ->
        {:noreply,
         socket
         |> put_flash(:error, "Finding not found.")
         |> push_navigate(to: ~p"/sessions/#{socket.assigns.session.id}/findings")}
    end
  end

  @impl true
  def handle_event("toggle_menu", _params, socket) do
    {:noreply, assign(socket, :menu_open?, !socket.assigns.menu_open?)}
  end

  @impl true
  def handle_event("close_menu", _params, socket) do
    {:noreply, assign(socket, :menu_open?, false)}
  end

  @impl true
  def handle_event("copy_fix_prompt", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.finding,
         %{"agent_prompt" => prompt} = fix <- socket.assigns.fix,
         true <- is_binary(prompt) and prompt != "" do
      emit_autofix_event(:copied, finding, fix)

      {:noreply,
       socket
       |> assign(:menu_open?, false)
       |> push_event("copy-to-clipboard", %{text: prompt})
       |> put_flash(:info, "Fix prompt copied to the clipboard.")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.finding,
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      refresh_finding(socket, "Finding approved.")
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("escalate_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.finding,
         {:ok, _updated} <- Mission.escalate_finding(finding, actor_opts(socket)) do
      refresh_finding(socket, "Finding escalated.")
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not escalate finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} <- socket.assigns.finding do
      {:noreply,
       socket
       |> assign(:menu_open?, false)
       |> assign(:reject_open?, true)
       |> assign(:reject_reason, "")}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  @impl true
  def handle_event("set_reject_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :reject_reason, reason)}
  end

  @impl true
  def handle_event("cancel_reject", _params, socket) do
    {:noreply, socket |> assign(:reject_open?, false) |> assign(:reject_reason, "")}
  end

  @impl true
  def handle_event("confirm_reject", _params, socket) do
    reason =
      socket.assigns.reject_reason |> String.trim() |> then(&if &1 == "", do: nil, else: &1)

    case Mission.reject_finding(socket.assigns.finding, reason, actor_opts(socket)) do
      {:ok, _updated} ->
        socket
        |> assign(:reject_open?, false)
        |> assign(:reject_reason, "")
        |> refresh_finding("Finding rejected.")

      _error ->
        {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  defp refresh_finding(socket, message) do
    case Mission.get_finding_with_context(socket.assigns.finding.id) do
      %{} = finding ->
        {:noreply,
         socket
         |> assign(:menu_open?, false)
         |> put_flash(:info, message)
         |> assign_finding(socket.assigns.session, finding)}

      _other ->
        {:noreply,
         socket
         |> put_flash(:error, "Finding not found.")
         |> push_navigate(to: ~p"/sessions/#{socket.assigns.session.id}/findings")}
    end
  end

  defp assign_finding(socket, session, finding) do
    fix = Mission.auto_fix_for_finding(finding)

    socket
    |> assign(:session, session)
    |> assign(:finding, finding)
    |> assign(:fix, fix)
    |> assign(:plain_english, FindingPlainEnglish.translate(finding))
    |> assign(:vuln, vuln_case_summary(finding))
    |> assign(:audit_events, Mission.finding_audit_events(finding.id))
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp vuln_case_summary(finding) do
    if SecurityWorkflow.vulnerability_case?(finding) do
      SecurityWorkflow.vulnerability_case_summary(finding)
    else
      nil
    end
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

  defp pill_base do
    "inline-flex items-center px-2.5 py-1 text-xs font-semibold capitalize ring-1"
  end

  defp severity_colors(severe) when severe in ~w(critical high),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp severity_colors("medium"), do: "bg-warning/10 text-warning ring-warning/20"
  defp severity_colors("low"), do: "bg-success/10 text-success ring-success/20"
  defp severity_colors(_), do: "bg-muted text-muted-foreground ring-border"

  defp status_pill("approved"), do: [pill_base(), "bg-success/10 text-success ring-success/20"]

  defp status_pill("rejected"),
    do: [pill_base(), "bg-destructive/10 text-destructive ring-destructive/20"]

  defp status_pill("escalated"), do: [pill_base(), "bg-primary/10 text-primary ring-primary/20"]
  defp status_pill("blocked"), do: [pill_base(), "bg-warning/10 text-warning ring-warning/20"]
  defp status_pill(_status), do: [pill_base(), "bg-muted text-muted-foreground ring-border"]

  defp option_label("open_source"), do: "Open source"
  defp option_label("third_party_vendor"), do: "Third party vendor"
  defp option_label("first_party"), do: "First party"
  defp option_label("wont_fix"), do: "Won't fix"
  defp option_label(value), do: value |> String.replace("_", " ") |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
            Guided fix
          </p>
          <.section_title class="mt-1">{@finding.title}</.section_title>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <span class={[pill_base(), severity_colors(@finding.severity)]}>
            {@finding.severity}
          </span>
          <span class={status_pill(@finding.status)}>{@finding.status}</span>
          <span class={[
            "inline-flex items-center px-3 py-1 text-xs font-semibold rounded-full border uppercase tracking-wider",
            @fix["supported"] && "border-primary/40 bg-primary/10 text-primary",
            !@fix["supported"] && "border-warning/40 bg-warning/10 text-warning"
          ]}>
            {if @fix["supported"], do: "supported", else: "manual review"}
          </span>
          <div class="relative inline-block text-left" phx-click-away="close_menu">
            <button
              type="button"
              id="finding-actions-menu-button"
              class="inline-flex items-center justify-center rounded-md p-1.5 text-muted-foreground transition hover:bg-muted hover:text-foreground cursor-pointer"
              phx-click="toggle_menu"
              aria-label="Finding actions"
              aria-haspopup="menu"
              aria-expanded={@menu_open?}
            >
              <.icon name="hero-ellipsis-vertical" class="size-5" />
            </button>
            <div
              :if={@menu_open?}
              id="finding-actions-menu"
              role="menu"
              class="absolute right-0 z-20 mt-1 w-48 rounded-md border bg-card shadow-card py-1"
            >
              <button
                :if={@finding.status != "approved"}
                type="button"
                role="menuitem"
                class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                phx-click="approve_finding"
                phx-value-id={@finding.id}
              >
                Approve
              </button>
              <button
                :if={@finding.status != "rejected" and not @reject_open?}
                type="button"
                role="menuitem"
                class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                phx-click="reject_finding"
                phx-value-id={@finding.id}
              >
                Reject
              </button>
              <button
                :if={@finding.status in ~w(open blocked)}
                type="button"
                role="menuitem"
                class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                phx-click="escalate_finding"
                phx-value-id={@finding.id}
              >
                Escalate
              </button>
              <button
                :if={@fix["agent_prompt"]}
                type="button"
                role="menuitem"
                class="block w-full text-left px-4 py-2 text-sm text-foreground transition hover:bg-muted cursor-pointer"
                phx-click="copy_fix_prompt"
                phx-value-id={@finding.id}
              >
                Copy fix prompt
              </button>
            </div>
          </div>
        </div>
      </div>

      <p class="text-sm text-muted-foreground">{@fix["summary"]}</p>

      <div :if={@plain_english && @plain_english.explanation != ""}>
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          In plain English
        </p>
        <p class="mt-1 text-sm">{@plain_english.explanation}</p>
        <p :if={@plain_english.fix} class="mt-2 text-sm">
          <span class="font-semibold">Recommended:</span> {@plain_english.fix}
        </p>
        <p :if={@plain_english.risk_if_ignored} class="mt-2 text-sm text-warning">
          If ignored: {@plain_english.risk_if_ignored}
        </p>
      </div>

      <div :if={@vuln} class="rounded-xl bg-muted/[0.03] px-3 py-2">
        <p class="text-[10px] uppercase tracking-[0.2em] text-muted-foreground">
          Security case
        </p>
        <div class="mt-1 flex flex-wrap gap-1.5">
          <span class="rounded-full bg-muted px-2 py-0.5 text-[11px] text-muted-foreground">
            {option_label(@vuln["patch_status"])}
          </span>
          <span class="rounded-full bg-muted px-2 py-0.5 text-[11px] text-muted-foreground">
            {option_label(@vuln["disclosure_status"])}
          </span>
          <span class={[
            "rounded-full px-2 py-0.5 text-[11px] border",
            @vuln["is_resolved"] && "border-primary/40 bg-primary/10 text-primary",
            !@vuln["is_resolved"] && "border-warning/40 bg-warning/10 text-warning"
          ]}>
            {if @vuln["is_resolved"], do: "resolved", else: "unresolved"}
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
            Why
          </p>
          <p class="mt-1 text-sm text-muted-foreground">{@fix["why"]}</p>
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
            Requires human
          </p>
          <p class="mt-1 text-sm text-muted-foreground">
            {if @fix["requires_human"], do: "Yes", else: "No"}
          </p>
        </div>
      </div>

      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          Steps
        </p>
        <ul class="mt-1 space-y-1 list-none p-0">
          <%= for step <- @fix["steps"] || [] do %>
            <li class="text-sm text-muted-foreground">• {step}</li>
          <% end %>
        </ul>
      </div>

      <div :if={@fix["example"]}>
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          Example
        </p>
        <pre class="mt-1 rounded-lg border border-input bg-background p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words"><code>{@fix["example"]}</code></pre>
      </div>

      <div :if={@fix["agent_prompt"]}>
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          Agent prompt
        </p>
        <pre class="mt-1 rounded-lg border border-input bg-background p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words max-h-60 overflow-y-auto"><code>{@fix["agent_prompt"]}</code></pre>
      </div>

      <div :if={length(@audit_events) > 0} class="border-t border-border pt-4">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          Audit trail
        </p>
        <ul class="mt-1 space-y-1 list-none p-0">
          <%= for event <- @audit_events do %>
            <li class="text-xs text-muted-foreground">
              {ControlKeelWeb.FormatHelpers.format_datetime(event.recorded_at, "short")} · {event.event_type} · {event.actor_identifier ||
                event.actor_source}
            </li>
          <% end %>
        </ul>
      </div>

      <div :if={@reject_open?} class="rounded-xl bg-muted/[0.03] p-4 space-y-3">
        <p class="text-sm font-semibold text-foreground">Reject finding</p>
        <textarea
          id="finding-reject-reason"
          class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
          placeholder="Reason for rejection..."
          value={@reject_reason}
          phx-keyup="set_reject_reason"
          phx-debounce="blur"
          rows="3"
        ></textarea>
        <div class="flex justify-end gap-3">
          <button
            type="button"
            class="rounded-md border bg-overlay px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-destructive/40 hover:text-destructive"
            phx-click="cancel_reject"
          >
            Cancel
          </button>
          <button
            type="button"
            class="rounded-md border bg-overlay px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary transition hover:border-primary"
            phx-click="confirm_reject"
          >
            Confirm
          </button>
        </div>
      </div>
    </div>
    """
  end
end
