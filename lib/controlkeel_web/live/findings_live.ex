defmodule ControlKeelWeb.FindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Governance.SecurityWorkflow
  alias ControlKeel.Mission
  alias ControlKeel.Mission.FindingPlainEnglish
  alias ControlKeelWeb.WorkspaceAccess

  @severities ~w(critical high medium low)
  @statuses ~w(open blocked escalated approved rejected)
  @patch_statuses ~w(none drafted validated merged)
  @disclosure_statuses ~w(draft triaged reported patched public wont_fix)
  @maintainer_scopes ~w(first_party open_source third_party_vendor)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Findings")
     |> assign(:browser, empty_browser())
     |> assign(:categories, Mission.list_finding_categories())
     |> assign(
       :session_options,
       Mission.list_findings_browser_sessions_for_user(socket.assigns[:current_user])
     )
     |> assign(:selected_finding, nil)
     |> assign(:selected_fix, nil)
     |> assign(:selected_plain_english, nil)
     |> assign(:selected_vuln, nil)
     |> assign(:selected_audit_events, [])
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")
     |> assign(:severities, @severities)
     |> assign(:statuses, @statuses)
     |> assign(:patch_statuses, @patch_statuses)
     |> assign(:disclosure_statuses, @disclosure_statuses)
     |> assign(:maintainer_scopes, @maintainer_scopes)
     |> assign(:more_filters_open?, false)
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = inject_org_workspace_ids(params, socket.assigns[:current_user])
    browser = Mission.browse_findings(params)

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} ->
          Enum.find(browser.entries, &(&1.id == id)) || Mission.get_finding_with_context(id)

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:browser, browser)
     |> assign(:selected_finding, selected_finding)
     |> assign(:selected_fix, maybe_regenerate_fix(selected_finding))
     |> assign(:more_filters_open?, advanced_active?(browser.filters))
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: findings_path(filter_params(filters)))}
  end

  @impl true
  def handle_event("toggle_more_filters", _params, socket) do
    {:noreply, assign(socket, :more_filters_open?, !socket.assigns.more_filters_open?)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    with {:ok, finding} <- fetch_mutable_finding(socket, id),
         {:ok, _updated} <- Mission.approve_finding(finding, actor_opts(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding approved.")
       |> refresh_browser()
       |> refresh_modal_context()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not approve that finding.")}
    end
  end

  @impl true
  def handle_event("escalate", %{"id" => id}, socket) do
    with {:ok, finding} <- fetch_mutable_finding(socket, id),
         {:ok, _updated} <- Mission.escalate_finding(finding, actor_opts(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding escalated.")
       |> refresh_browser()
       |> refresh_modal_context()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not escalate that finding.")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, id)
     |> assign(:reject_reason, "")}
  end

  @impl true
  def handle_event("set_reject_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :reject_reason, reason)}
  end

  @impl true
  def handle_event("confirm_reject", _params, socket) do
    id = socket.assigns.reject_id

    reason =
      socket.assigns.reject_reason |> String.trim() |> then(&if &1 == "", do: nil, else: &1)

    with {:ok, finding} <- fetch_mutable_finding(socket, id),
         {:ok, _updated} <- Mission.reject_finding(finding, reason, actor_opts(socket)) do
      {:noreply,
       socket
       |> assign(:reject_id, nil)
       |> assign(:reject_reason, "")
       |> put_flash(:info, "Finding rejected.")
       |> refresh_browser()
       |> refresh_modal_context()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not reject that finding.")}
    end
  end

  @impl true
  def handle_event("cancel_reject", _params, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")}
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding} <- fetch_readable_finding(socket, id) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)
       |> assign(:selected_plain_english, FindingPlainEnglish.translate(finding))
       |> assign(:selected_vuln, vuln_case_summary(finding))
       |> assign(:selected_audit_events, Mission.finding_audit_events(finding.id))}
    else
      _error ->
        {:noreply,
         socket
         |> put_flash(:error, "ControlKeel could not load that fix.")}
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
    {:noreply,
     socket
     |> assign(:selected_finding, nil)
     |> assign(:selected_fix, nil)
     |> assign(:selected_plain_english, nil)
     |> assign(:selected_vuln, nil)
     |> assign(:selected_audit_events, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <.page_title
        title="Findings browser"
        subtitle="Filter, approve, reject, and inspect guided fixes without leaving the governed ControlKeel workflow."
        class="mb-6"
      />

      <div
        :if={@browser.security_summary["case_count"] > 0}
        class="rounded-2xl border bg-card shadow-card p-5 mb-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-2">
          <.section_title>Security cases</.section_title>
          <p class="text-sm text-muted-foreground">
            <span class="font-semibold text-foreground/90">
              {summary_count(@browser.security_summary, "case_count")} total
            </span>
            <span class="mx-2 text-border">·</span>
            <span class="text-warning">
              {summary_count(@browser.security_summary, "unresolved")} unresolved
            </span>
            <span
              :if={summary_count(@browser.security_summary, "critical_unresolved") > 0}
              class="text-destructive"
            >
              <span class="mx-2 text-border">·</span>
              {summary_count(@browser.security_summary, "critical_unresolved")} critical
              unresolved
            </span>
          </p>
        </div>
        <div class="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <div>
            <p class="text-sm font-medium text-muted-foreground">Patch</p>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <%= for {value, count} <- breakdown_entries(@browser.security_summary, "patch_status") do %>
                <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {option_label(value)} {count}
                </span>
              <% end %>
            </div>
          </div>
          <div>
            <p class="text-sm font-medium text-muted-foreground">Disclosure</p>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <%= for {value, count} <- breakdown_entries(@browser.security_summary, "disclosure_status") do %>
                <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {option_label(value)} {count}
                </span>
              <% end %>
            </div>
          </div>
          <div>
            <p class="text-sm font-medium text-muted-foreground">Maintainer scope</p>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <%= for {value, count} <- breakdown_entries(@browser.security_summary, "maintainer_scope") do %>
                <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {option_label(value)} {count}
                </span>
              <% end %>
            </div>
          </div>
          <div>
            <p class="text-sm font-medium text-muted-foreground">Exploitability</p>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <%= for {value, count} <- breakdown_entries(@browser.security_summary, "exploitability_status") do %>
                <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {option_label(value)} {count}
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="rounded-2xl border bg-card shadow-card overflow-clip">
        <div class="space-y-4 p-5">
          <.form for={@form} phx-change="filter">
            <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
              <div class="space-y-2">
                <label for="filters-q" class="text-xs uppercase tracking-[0.28em]">Search</label>
                <input
                  id="filters-q"
                  name="filters[q]"
                  type="text"
                  value={@form[:q].value}
                  placeholder="Rule, title, session..."
                  phx-debounce="300"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                />
              </div>
              <div class="space-y-2">
                <label for="filters-severity" class="text-xs uppercase tracking-[0.28em]">
                  Severity
                </label>
                <select
                  id="filters-severity"
                  name="filters[severity]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All severities</option>
                  <%= for s <- @severities do %>
                    <option value={s} selected={@form[:severity].value == s}>
                      {String.capitalize(s)}
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="space-y-2">
                <label for="filters-status" class="text-xs uppercase tracking-[0.28em]">
                  Status
                </label>
                <select
                  id="filters-status"
                  name="filters[status]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All statuses</option>
                  <%= for s <- @statuses do %>
                    <option value={s} selected={@form[:status].value == s}>
                      {String.capitalize(s)}
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="space-y-2">
                <label for="filters-session_id" class="text-xs uppercase tracking-[0.28em]">
                  Session
                </label>
                <select
                  id="filters-session_id"
                  name="filters[session_id]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All sessions</option>
                  <%= for {label, id} <- session_filter_options(@session_options) do %>
                    <option
                      value={id}
                      selected={to_string(@form[:session_id].value) == to_string(id)}
                    >
                      {label}
                    </option>
                  <% end %>
                </select>
              </div>
            </div>

            <div class="flex justify-end mt-4">
              <button
                type="button"
                class="rounded-md border border-input bg-background px-4 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-primary hover:text-primary"
                phx-click="toggle_more_filters"
              >
                {more_filters_label(@form, @more_filters_open?)}
              </button>
            </div>

            <div class={[
              "grid gap-4 md:grid-cols-2 xl:grid-cols-3 mt-4",
              !@more_filters_open? && "hidden"
            ]}>
              <div class="space-y-2">
                <label for="filters-category" class="text-xs uppercase tracking-[0.28em]">
                  Category
                </label>
                <select
                  id="filters-category"
                  name="filters[category]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All categories</option>
                  <%= for c <- @categories do %>
                    <option value={c} selected={@form[:category].value == c}>
                      {String.capitalize(c)}
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="space-y-2">
                <label for="filters-patch_status" class="text-xs uppercase tracking-[0.28em]">
                  Patch status
                </label>
                <select
                  id="filters-patch_status"
                  name="filters[patch_status]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All patch statuses</option>
                  <%= for s <- @patch_statuses do %>
                    <option value={s} selected={@form[:patch_status].value == s}>
                      {option_label(s)}
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="space-y-2">
                <label for="filters-disclosure_status" class="text-xs uppercase tracking-[0.28em]">
                  Disclosure status
                </label>
                <select
                  id="filters-disclosure_status"
                  name="filters[disclosure_status]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All disclosure statuses</option>
                  <%= for s <- @disclosure_statuses do %>
                    <option value={s} selected={@form[:disclosure_status].value == s}>
                      {option_label(s)}
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="space-y-2">
                <label for="filters-maintainer_scope" class="text-xs uppercase tracking-[0.28em]">
                  Maintainer scope
                </label>
                <select
                  id="filters-maintainer_scope"
                  name="filters[maintainer_scope]"
                  class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
                >
                  <option value="">All scopes</option>
                  <%= for s <- @maintainer_scopes do %>
                    <option value={s} selected={@form[:maintainer_scope].value == s}>
                      {option_label(s)}
                    </option>
                  <% end %>
                </select>
              </div>
            </div>
          </.form>

          <div class="flex items-center justify-between">
            <p class="text-muted-foreground tracking-tight">
              <span class="text-primary mr-1">{@browser.total_count}</span> total findings
            </p>

            <.link
              patch={findings_path(%{})}
              class="self-end rounded-md border border-input bg-background px-4 py-3 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-destructive/40 hover:text-destructive text-center"
            >
              Reset all
            </.link>
          </div>
        </div>

        <div class="border-t bg-muted/20">
          <ul class="divide-y divide-border">
            <li
              :if={@browser.entries == []}
              class="px-6 py-12 text-center text-sm text-muted-foreground"
            >
              No findings match the current filters.
            </li>
            <li
              :for={finding <- @browser.entries}
              class="px-6 py-5 transition hover:bg-muted/[0.02]"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="flex flex-wrap items-center gap-3">
                  <span class={[pill_base(), severity_colors(finding.severity)]}>
                    {finding.severity}
                  </span>
                  <span class={status_pill(finding.status)}>{finding.status}</span>
                </div>
                <button
                  type="button"
                  class="shrink-0 rounded-md border border-input bg-background px-4 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary transition hover:border-primary"
                  phx-click="view_fix"
                  phx-value-id={finding.id}
                >
                  View
                </button>
              </div>
              <h3 class="mt-3 font-bold text-foreground break-words">{finding.title}</h3>
              <p class="mt-1 text-sm text-muted-foreground break-words">{finding.plain_message}</p>
              <div class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                <span>session:</span>
                <.link
                  navigate={~p"/sessions/#{finding.session_id}"}
                  class="font-semibold text-primary hover:underline"
                >
                  {finding.session.title}
                </.link>
                <span aria-hidden="true">·</span>
                <span>rule: {rule_label(finding.rule_id)}</span>
              </div>
              <p
                :if={finding.status == "rejected" && finding.metadata["rejection_reason"]}
                class="mt-2 text-xs text-muted-foreground italic"
              >
                {finding.metadata["rejection_reason"]}
              </p>
            </li>
          </ul>
        </div>

        <div class="border-t bg-muted/20 px-6 py-4">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="text-xs uppercase tracking-[0.15em] text-muted-foreground">
              Page {@browser.page} of {@browser.total_pages}
            </div>
            <div class="flex gap-3">
              <%= if @browser.page > 1 do %>
                <.link
                  patch={
                    findings_path(
                      Map.merge(browser_form_params(@browser.filters), %{
                        "page" => @browser.page - 1
                      })
                    )
                  }
                  class="rounded-md border bg-overlay px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary transition hover:border-primary"
                >
                  Previous
                </.link>
              <% else %>
                <span class="cursor-not-allowed rounded-md border bg-muted px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground">
                  Previous
                </span>
              <% end %>
              <%= if @browser.page < @browser.total_pages do %>
                <.link
                  patch={
                    findings_path(
                      Map.merge(browser_form_params(@browser.filters), %{
                        "page" => @browser.page + 1
                      })
                    )
                  }
                  class="rounded-md border bg-overlay px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary transition hover:border-primary"
                >
                  Next
                </.link>
              <% else %>
                <span class="cursor-not-allowed rounded-md border bg-muted px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground">
                  Next
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={@reject_id}
        class="fixed inset-0 z-[60] flex items-center justify-center"
        phx-key="Escape"
        phx-key-target="window"
      >
        <div class="fixed inset-0 bg-overlay/60" phx-click="cancel_reject"></div>
        <div class="relative rounded-2xl border bg-card shadow-card p-6 w-full max-w-md mx-4">
          <h3 class="text-lg font-semibold text-foreground">Reject finding</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            Rule: {rejected_finding_title(@browser.entries, @reject_id)}
          </p>
          <textarea
            class="mt-4 w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
            placeholder="Reason for rejection..."
            value={@reject_reason}
            phx-keyup="set_reject_reason"
            phx-debounce="blur"
            rows="3"
          ></textarea>
          <div class="flex justify-end gap-3 mt-4">
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

      <div
        :if={@selected_finding && @selected_fix}
        class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto"
        phx-click-away="close_fix"
        phx-key="Escape"
        phx-key-target="window"
      >
        <div class="fixed inset-0 bg-overlay/60" phx-click="close_fix"></div>
        <div class="relative rounded-2xl border bg-card shadow-card p-8 w-full max-w-2xl mx-4 space-y-4">
          <button
            type="button"
            class="absolute top-2 right-2 text-muted-foreground hover:text-foreground transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
            phx-click="close_fix"
            aria-label="Close guided fix"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
          <div class="flex items-center justify-between gap-4">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
                Guided fix
              </p>
              <h3 class="text-lg font-semibold text-foreground mt-1">{@selected_finding.title}</h3>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <span class={status_pill(@selected_finding.status)}>
                {@selected_finding.status}
              </span>
              <span class={[
                "inline-flex items-center px-3 py-1 text-xs font-semibold rounded-full border uppercase tracking-wider",
                @selected_fix["supported"] && "border-primary/40 bg-primary/10 text-primary",
                !@selected_fix["supported"] &&
                  "border-warning/40 bg-warning/10 text-warning"
              ]}>
                {if @selected_fix["supported"], do: "supported", else: "manual review"}
              </span>
            </div>
          </div>

          <p class="text-sm text-muted-foreground">{@selected_fix["summary"]}</p>

          <div :if={@selected_plain_english && @selected_plain_english.explanation != ""}>
            <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              In plain English
            </h4>
            <p class="mt-1 text-sm">{@selected_plain_english.explanation}</p>
            <p :if={@selected_plain_english.fix} class="mt-2 text-sm">
              <span class="font-semibold">Recommended:</span> {@selected_plain_english.fix}
            </p>
            <p
              :if={@selected_plain_english.risk_if_ignored}
              class="mt-2 text-sm text-warning"
            >
              If ignored: {@selected_plain_english.risk_if_ignored}
            </p>
          </div>

          <div :if={@selected_vuln} class="rounded-md border border-input bg-background/50 px-3 py-2">
            <p class="text-[10px] uppercase tracking-[0.2em] text-muted-foreground">
              Security case
            </p>
            <div class="mt-1 flex flex-wrap gap-1.5">
              <span class="rounded-full bg-muted px-2 py-0.5 text-[11px] text-muted-foreground">
                {option_label(@selected_vuln["patch_status"])}
              </span>
              <span class="rounded-full bg-muted px-2 py-0.5 text-[11px] text-muted-foreground">
                {option_label(@selected_vuln["disclosure_status"])}
              </span>
              <span class={[
                "rounded-full px-2 py-0.5 text-[11px] border",
                @selected_vuln["is_resolved"] &&
                  "border-primary/40 bg-primary/10 text-primary",
                !@selected_vuln["is_resolved"] &&
                  "border-warning/40 bg-warning/10 text-warning"
              ]}>
                {if @selected_vuln["is_resolved"], do: "resolved", else: "unresolved"}
              </span>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
                Why
              </h4>
              <p class="mt-1 text-sm text-muted-foreground">{@selected_fix["why"]}</p>
            </div>
            <div>
              <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
                Requires human
              </h4>
              <p class="mt-1 text-sm text-muted-foreground">
                {if @selected_fix["requires_human"], do: "Yes", else: "No"}
              </p>
            </div>
          </div>

          <div>
            <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Steps
            </h4>
            <ul class="mt-1 space-y-1 list-none p-0">
              <%= for step <- @selected_fix["steps"] || [] do %>
                <li class="text-sm text-muted-foreground">• {step}</li>
              <% end %>
            </ul>
          </div>

          <div :if={@selected_fix["example"]}>
            <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Example
            </h4>
            <pre class="mt-1 rounded-lg border border-input bg-background p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words"><code>{@selected_fix["example"]}</code></pre>
          </div>

          <div :if={@selected_fix["agent_prompt"]}>
            <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Agent prompt
            </h4>
            <pre class="mt-1 rounded-lg border border-input bg-background p-4 font-mono text-sm leading-relaxed whitespace-pre-wrap break-words max-h-60 overflow-y-auto"><code>{@selected_fix["agent_prompt"]}</code></pre>
          </div>

          <div :if={length(@selected_audit_events) > 0}>
            <h4 class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Audit trail
            </h4>
            <ul class="mt-1 space-y-1 list-none p-0">
              <%= for event <- @selected_audit_events do %>
                <li class="text-xs text-muted-foreground">
                  {ControlKeelWeb.FormatHelpers.format_datetime(event.recorded_at, "short")} · {event.event_type} · {event.actor_identifier ||
                    event.actor_source}
                </li>
              <% end %>
            </ul>
          </div>

          <div class="flex flex-wrap items-center gap-3 border-t border-border pt-4">
            <button
              :if={@selected_finding.status != "approved"}
              type="button"
              class="rounded-md border border-primary bg-primary px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary-foreground transition hover:brightness-110"
              phx-click="approve"
              phx-value-id={@selected_finding.id}
            >
              Approve
            </button>
            <button
              :if={@selected_finding.status != "rejected"}
              type="button"
              class="rounded-md border border-warning/40 bg-warning/10 px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-warning transition hover:brightness-110"
              phx-click="reject"
              phx-value-id={@selected_finding.id}
            >
              Reject
            </button>
            <button
              :if={@selected_finding.status in ~w(open blocked)}
              type="button"
              class="rounded-md border border-input bg-background px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-primary hover:text-primary"
              phx-click="escalate"
              phx-value-id={@selected_finding.id}
            >
              Escalate
            </button>
            <div class="ml-auto flex flex-wrap items-center gap-3">
              <button
                :if={@selected_fix["agent_prompt"]}
                type="button"
                class="rounded-md border border-primary bg-primary px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary-foreground transition hover:brightness-110"
                phx-click="copy_fix_prompt"
                phx-value-id={@selected_finding.id}
              >
                Copy fix prompt
              </button>
              <button
                type="button"
                class="rounded-md border bg-overlay px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-destructive/40 hover:text-destructive"
                phx-click="close_fix"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # Scoping is derived from the *authenticated viewer*, never from the ambient
  # `current_org_id` (which is only a UI hint and defaults to the user's first
  # membership). In cloud mode an empty accessible set must degrade to "no
  # rows", not to an unscoped query — otherwise a user whose orgs have no
  # workspaces sees every finding in the database.
  defp inject_org_workspace_ids(params, user) do
    if ControlKeel.Runtime.Mode.current() == :local do
      params
    else
      workspace_ids =
        case user do
          %{id: user_id} -> Mission.accessible_workspace_ids(user_id)
          _ -> []
        end

      params
      |> Map.put("workspace_ids", workspace_ids)
      |> Map.delete("workspace_id")
    end
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

  defp rejected_finding_title(entries, reject_id) do
    case Enum.find(entries, &(to_string(&1.id) == reject_id)) do
      nil -> ""
      finding -> finding.title
    end
  end

  defp refresh_browser(socket) do
    params =
      socket.assigns.browser.filters
      |> browser_form_params()
      |> inject_org_workspace_ids(socket.assigns[:current_org_id])

    browser = Mission.browse_findings(params)

    selected_finding =
      case socket.assigns.selected_finding do
        %{id: id} ->
          Enum.find(browser.entries, &(&1.id == id)) || Mission.get_finding_with_context(id)

        _ ->
          nil
      end

    socket
    |> assign(:browser, browser)
    |> assign(:selected_finding, selected_finding)
    |> assign(:selected_fix, maybe_regenerate_fix(selected_finding))
    |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))
  end

  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

  defp refresh_modal_context(socket) do
    case socket.assigns.selected_finding do
      %{id: id} ->
        with %{} = finding <- Mission.get_finding_with_context(id) do
          socket
          |> assign(:selected_finding, finding)
          |> assign(:selected_fix, Mission.auto_fix_for_finding(finding))
          |> assign(:selected_plain_english, FindingPlainEnglish.translate(finding))
          |> assign(:selected_vuln, vuln_case_summary(finding))
          |> assign(:selected_audit_events, Mission.finding_audit_events(id))
        else
          _error -> socket
        end

      _other ->
        socket
    end
  end

  defp more_filters_label(_form, true), do: "Fewer filters"

  defp more_filters_label(form, false) do
    case advanced_filter_count(form) do
      0 -> "More filters"
      n -> "More filters (#{n} active)"
    end
  end

  defp advanced_filter_count(form) do
    Enum.count(advanced_filter_keys(), &(not empty_filter_value?(input_value(form, &1))))
  end

  defp advanced_active?(filters) do
    Enum.any?(advanced_filter_keys(), &(not empty_filter_value?(Map.get(filters, &1))))
  end

  defp advanced_filter_keys do
    [:category, :patch_status, :disclosure_status, :maintainer_scope]
  end

  defp input_value(form, key), do: Phoenix.HTML.Form.input_value(form, key)

  defp empty_filter_value?(nil), do: true
  defp empty_filter_value?(value) when is_binary(value), do: value == ""
  defp empty_filter_value?(_value), do: false

  defp vuln_case_summary(finding) do
    if SecurityWorkflow.vulnerability_case?(finding) do
      SecurityWorkflow.vulnerability_case_summary(finding)
    else
      nil
    end
  end

  defp filter_params(params) do
    params
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), normalize_param_value(value)} end)
    |> Map.put("page", 1)
  end

  defp browser_form_params(filters) do
    %{
      "q" => filters.q || "",
      "severity" => filters.severity || "",
      "status" => filters.status || "",
      "category" => filters.category || "",
      "session_id" => filters.session_id || "",
      "patch_status" => filters.patch_status || "",
      "disclosure_status" => filters.disclosure_status || "",
      "maintainer_scope" => filters.maintainer_scope || "",
      "page" => filters.page
    }
  end

  defp findings_path(params), do: ~p"/findings?#{prune_params(params)}"

  defp prune_params(params) do
    params
    |> Enum.reject(fn
      {"page", 1} -> true
      {_key, value} when value in [nil, ""] -> true
      _other -> false
    end)
    |> Map.new()
  end

  defp session_filter_options(sessions) do
    Enum.map(sessions, fn session ->
      {session.title, session.id}
    end)
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

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp normalize_param_value(nil), do: ""
  defp normalize_param_value(value), do: value

  defp rule_label(rule_id) do
    rule_id
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp empty_browser do
    %{
      entries: [],
      filters: %{
        q: nil,
        severity: nil,
        status: nil,
        category: nil,
        session_id: nil,
        patch_status: nil,
        disclosure_status: nil,
        maintainer_scope: nil,
        page: 1
      },
      total_count: 0,
      total_pages: 1,
      page: 1,
      page_size: 10
    }
  end

  defp summary_count(security_summary, key), do: Map.get(security_summary, key, 0)

  defp actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> [actor_source: "web", actor_identifier: "web"]
      user -> [actor_source: "web", actor_user_id: user.id, actor_identifier: user.email]
    end
  end

  # Findings are governance state, so every mutation is gated on the viewer's
  # admin role *in the finding's own workspace*. This closes two holes at once:
  # a crafted event could previously target any finding ID across tenants
  # (cross-tenant write), and any member including a viewer could mutate
  # disposition. Returns the finding with its workspace preloaded on success,
  # or {:error, :not_found | :forbidden}.
  defp fetch_mutable_finding(socket, id) do
    with {:ok, finding} <- fetch_readable_finding(socket, id, "admin") do
      {:ok, finding}
    end
  end

  # Tenant-scoped read: the viewer must have at least the given role in the
  # finding's own workspace. Prevents cross-tenant autofix/plain-English
  # disclosure via a crafted id even though the list view is already scoped.
  defp fetch_readable_finding(socket, id, required_role \\ "viewer") do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding_with_context(finding_id),
         workspace when not is_nil(workspace) <- finding.session.workspace,
         :ok <- WorkspaceAccess.check(workspace, socket.assigns[:current_user], required_role) do
      {:ok, finding}
    else
      nil -> {:error, :not_found}
      {:error, _reason} -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp breakdown_entries(security_summary, key) do
    security_summary
    |> Map.get(key, %{})
    |> Enum.sort_by(fn {_value, count} -> -count end)
  end

  defp option_label("open_source"), do: "Open source"
  defp option_label("third_party_vendor"), do: "Third party vendor"
  defp option_label("first_party"), do: "First party"
  defp option_label("wont_fix"), do: "Won't fix"
  defp option_label(value), do: value |> String.replace("_", " ") |> String.capitalize()
end
