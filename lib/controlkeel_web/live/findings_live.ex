defmodule ControlKeelWeb.FindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @severities ~w(critical high medium low)
  @statuses ~w(open blocked escalated approved rejected)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Findings")
     |> assign(:browser, empty_browser())
     |> assign(:categories, Mission.list_finding_categories())
     |> assign(:session_options, Mission.list_findings_browser_sessions())
     |> assign(:selected_finding, nil)
     |> assign(:selected_fix, nil)
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")
     |> assign(:severities, @severities)
     |> assign(:statuses, @statuses)
     |> assign(:open_dropdown_id, nil)
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = inject_org_workspace_ids(params, socket.assigns[:current_org_id])
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
     |> assign(:open_dropdown_id, nil)
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: findings_path(filter_params(filters)))}
  end

  @impl true
  def handle_event("toggle_dropdown", %{"id" => id}, socket) do
    current = socket.assigns.open_dropdown_id
    {:noreply, assign(socket, :open_dropdown_id, if(current == id, do: nil, else: id))}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, :open_dropdown_id, nil)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding(finding_id),
         {:ok, _updated} <- Mission.approve_finding(finding) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding approved.")
       |> refresh_browser()}
    else
      _error ->
        {:noreply,
         socket
         |> assign(:open_dropdown_id, nil)
         |> put_flash(:error, "ControlKeel could not approve that finding.")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, id)
     |> assign(:reject_reason, "")
     |> assign(:open_dropdown_id, nil)}
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

    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding(finding_id),
         {:ok, _updated} <- Mission.reject_finding(finding, reason) do
      {:noreply,
       socket
       |> assign(:reject_id, nil)
       |> assign(:reject_reason, "")
       |> put_flash(:info, "Finding rejected.")
       |> refresh_browser()}
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
     |> assign(:reject_reason, "")
     |> assign(:open_dropdown_id, nil)}
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding_with_context(finding_id) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:open_dropdown_id, nil)
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error ->
        {:noreply,
         socket
         |> assign(:open_dropdown_id, nil)
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
     |> assign(:open_dropdown_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16">
      <div class="space-y-1 mb-12">
        <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
          Findings browser
        </h2>
        <p class="text-muted-foreground">
          Filter, approve, reject, and inspect guided fixes without leaving the governed ControlKeel workflow.
        </p>
      </div>

      <div class="rounded-lg border bg-card">
        <div class="space-y-4 p-4">
          <.form for={@form} phx-change="filter">
            <div class="grid gap-4 xl:grid-cols-5">
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

        <div class="overflow-x-auto w-full">
          <div class="overflow-hidden border-t bg-overlay/30">
            <table class="min-w-full divide-y divide-border">
              <thead class="bg-muted">
                <tr>
                  <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Finding
                  </th>
                  <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Session
                  </th>
                  <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Severity
                  </th>
                  <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Status
                  </th>
                  <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Rule
                  </th>
                  <th class="w-0 px-2 py-6 text-right text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                <tr :if={@browser.entries == []}>
                  <td colspan="6" class="px-8 py-12 text-center text-sm text-muted-foreground">
                    No findings match the current filters.
                  </td>
                </tr>
                <tr
                  :for={finding <- @browser.entries}
                  class="transition hover:bg-muted/[0.02]"
                >
                  <td class="px-8 py-6 align-top">
                    <div>
                      <p class="font-bold text-foreground">{finding.title}</p>
                      <p class="mt-2 max-w-md text-sm text-muted-foreground">
                        {finding.plain_message}
                      </p>
                    </div>
                  </td>
                  <td class="px-8 py-6 align-top">
                    <.link
                      navigate={~p"/sessions/#{finding.session_id}"}
                      class="text-xs font-semibold tracking-[0.14em] text-primary hover:underline"
                    >
                      {finding.session.title}
                    </.link>
                  </td>
                  <td class="px-8 py-6 align-top">
                    <span class={[pill_base(), severity_colors(finding.severity)]}>
                      {finding.severity}
                    </span>
                  </td>
                  <td class="px-8 py-6 align-top">
                    <span class={[pill_base(), "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"]}>
                      {finding.status}
                    </span>
                    <p
                      :if={finding.status == "rejected" && finding.metadata["rejection_reason"]}
                      class="mt-2 text-xs text-muted-foreground italic"
                    >
                      {finding.metadata["rejection_reason"]}
                    </p>
                  </td>
                  <td class="px-8 py-6 align-top">
                    <p>{rule_label(finding.rule_id)}</p>
                  </td>
                  <td class="px-2 py-6 text-right align-top">
                    <div class="relative inline-flex">
                      <button
                        type="button"
                        aria-label="Finding actions"
                        class="flex items-center justify-center w-8 h-8 rounded-md border border-input bg-background hover:bg-muted text-muted-foreground hover:text-foreground transition-colors"
                        phx-click="toggle_dropdown"
                        phx-value-id={finding.id}
                      >
                        ⋮
                      </button>
                      <div
                        :if={@open_dropdown_id == to_string(finding.id)}
                        class="absolute right-0 top-full mt-1 z-50 min-w-[140px] rounded-lg border bg-card shadow-2xl py-1"
                        phx-click-away="close_dropdown"
                      >
                        <%= if finding.status == "approved" do %>
                          <span class="block w-full text-left px-4 py-2 text-sm text-muted-foreground cursor-not-allowed">
                            Approved
                          </span>
                        <% else %>
                          <button
                            type="button"
                            class="w-full text-left px-4 py-2 text-sm text-muted-foreground hover:bg-muted transition-colors"
                            phx-click="approve"
                            phx-value-id={finding.id}
                          >
                            Approve
                          </button>
                        <% end %>
                        <%= if finding.status == "rejected" do %>
                          <span class="block w-full text-left px-4 py-2 text-sm text-muted-foreground cursor-not-allowed">
                            Rejected
                          </span>
                        <% else %>
                          <button
                            type="button"
                            class="w-full text-left px-4 py-2 text-sm text-muted-foreground hover:bg-muted transition-colors"
                            phx-click="reject"
                            phx-value-id={finding.id}
                          >
                            Reject
                          </button>
                        <% end %>
                        <button
                          type="button"
                          class="w-full text-left px-4 py-2 text-sm text-muted-foreground hover:bg-muted transition-colors"
                          phx-click="view_fix"
                          phx-value-id={finding.id}
                        >
                          View fix
                        </button>
                      </div>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="border-t bg-overlay/40 px-6 py-4">
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
        class="fixed inset-0 z-50 flex items-center justify-center"
        phx-key="Escape"
        phx-key-target="window"
      >
        <div class="fixed inset-0 bg-overlay/60" phx-click="cancel_reject"></div>
        <div class="relative rounded-lg border bg-card shadow-2xl p-6 w-full max-w-md mx-4">
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
        <div class="relative rounded-lg border bg-card shadow-2xl p-8 w-full max-w-2xl mx-4 space-y-4">
          <button
            type="button"
            class="absolute top-2 right-2 text-muted-foreground hover:text-foreground transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
            aria-label="Close guided fix"
            phx-click="close_fix"
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
            <span class={[
              "inline-flex items-center px-3 py-1 text-xs font-semibold rounded-full border uppercase tracking-wider",
              @selected_fix["supported"] && "border-primary/40 bg-primary/10 text-primary",
              !@selected_fix["supported"] &&
                "border-[var(--ck-warning)]/40 bg-[var(--ck-warning)]/10 text-[var(--ck-warning)]"
            ]}>
              {if @selected_fix["supported"], do: "supported", else: "manual review"}
            </span>
          </div>

          <p class="text-sm text-muted-foreground">{@selected_fix["summary"]}</p>

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

          <div class="flex items-center justify-between pt-2">
            <button
              :if={@selected_fix["agent_prompt"]}
              type="button"
              class="rounded-md border border-primary bg-primary px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-primary-foreground transition hover:brightness-110"
              phx-click="copy_fix_prompt"
              phx-value-id={@selected_finding.id}
            >
              Copy fix prompt
            </button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp inject_org_workspace_ids(params, nil), do: params

  defp inject_org_workspace_ids(params, org_id) when is_integer(org_id) do
    workspace_ids =
      org_id
      |> ControlKeel.Accounts.list_workspaces_for_org()
      |> Enum.map(& &1.id)

    if workspace_ids == [], do: params, else: Map.put(params, "workspace_ids", workspace_ids)
  end

  defp pill_base do
    "inline-flex items-center px-3 py-1.5 text-sm rounded-full border"
  end

  defp severity_colors("critical"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp severity_colors("high"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp severity_colors("medium"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp severity_colors("low"), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  defp severity_colors(_), do: "bg-muted text-foreground/70"

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
    |> assign(:open_dropdown_id, nil)
    |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))
  end

  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

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
      filters: %{q: nil, severity: nil, status: nil, category: nil, session_id: nil, page: 1},
      total_count: 0,
      total_pages: 1,
      page: 1,
      page_size: 20
    }
  end
end
