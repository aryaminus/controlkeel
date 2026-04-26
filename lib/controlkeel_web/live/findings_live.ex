defmodule ControlKeelWeb.FindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.FindingComponents

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
     |> assign(:severities, @severities)
     |> assign(:statuses, @statuses)
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
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
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: findings_path(filter_params(filters)))}
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
        {:noreply, put_flash(socket, :error, "ControlKeel could not approve that finding.")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding(finding_id),
         {:ok, _updated} <- Mission.reject_finding(finding, nil) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding rejected.")
       |> refresh_browser()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not reject that finding.")}
    end
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding_with_context(finding_id) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error -> {:noreply, put_flash(socket, :error, "ControlKeel could not load that fix.")}
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
    {:noreply, socket |> assign(:selected_finding, nil) |> assign(:selected_fix, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Findings browser</p>
            <h1 class="ck-section-title">Review findings across all missions</h1>
            <p class="ck-lead ck-lead-tight">
              Filter, approve, reject, and inspect guided fixes without leaving the governed ControlKeel workflow.
            </p>
          </div>
          <a href={~p"/"} class="ck-link">Back home</a>
        </div>

        <div class="ck-card ck-browser-filters">
          <.form for={@form} phx-change="filter">
            <div class="ck-filter-grid">
              <.input
                field={@form[:q]}
                type="text"
                label="Search"
                placeholder="Rule, title, session..."
                phx-debounce="300"
              />
              <.input
                field={@form[:severity]}
                type="select"
                label="Severity"
                prompt="All severities"
                options={Enum.map(@severities, &{String.capitalize(&1), &1})}
              />
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                prompt="All statuses"
                options={Enum.map(@statuses, &{String.capitalize(&1), &1})}
              />
              <.input
                field={@form[:category]}
                type="select"
                label="Category"
                prompt="All categories"
                options={Enum.map(@categories, &{String.capitalize(&1), &1})}
              />
              <.input
                field={@form[:session_id]}
                type="select"
                label="Mission"
                prompt="All missions"
                options={session_filter_options(@session_options)}
              />
            </div>
          </.form>

          <div class="ck-metric-row">
            <span>{@browser.total_count} total findings</span>
            <span>Page {@browser.page} of {@browser.total_pages}</span>
          </div>
        </div>

        <div class="ck-card">
          <div class="ck-table-wrap">
            <.table id="findings-browser" rows={@browser.entries}>
              <:col :let={finding} label="Finding">
                <div>
                  <strong>{finding.title}</strong>
                  <p class="ck-note">{finding.plain_message}</p>
                </div>
              </:col>
              <:col :let={finding} label="Mission">
                <div>
                  <.link navigate={~p"/missions/#{finding.session_id}"} class="ck-link">
                    {finding.session.title}
                  </.link>
                  <p class="ck-note">{finding.session.workspace.name}</p>
                </div>
              </:col>
              <:col :let={finding} label="Status">
                <div class="ck-badge-stack">
                  <span class={["ck-pill", "ck-pill-#{finding.severity}"]}>{finding.severity}</span>
                  <span class="ck-pill ck-pill-neutral">{finding.status}</span>
                </div>
              </:col>
              <:col :let={finding} label="Rule">
                <div>
                  <strong>{finding.rule_id}</strong>
                  <p class="ck-note">{finding.category}</p>
                </div>
              </:col>
              <:action :let={finding}>
                <button type="button" class="ck-link" phx-click="approve" phx-value-id={finding.id}>
                  Approve
                </button>
              </:action>
              <:action :let={finding}>
                <button type="button" class="ck-link" phx-click="reject" phx-value-id={finding.id}>
                  Reject
                </button>
              </:action>
              <:action :let={finding}>
                <button type="button" class="ck-link" phx-click="view_fix" phx-value-id={finding.id}>
                  View fix
                </button>
              </:action>
            </.table>
          </div>

          <div class="ck-action-row" style="margin-top: 1rem;">
            <.link
              :if={@browser.page > 1}
              patch={
                findings_path(
                  Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page - 1})
                )
              }
              class="ck-link"
            >
              Previous page
            </.link>
            <div />
            <.link
              :if={@browser.page < @browser.total_pages}
              patch={
                findings_path(
                  Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page + 1})
                )
              }
              class="ck-link"
            >
              Next page
            </.link>
          </div>
        </div>

        <FindingComponents.autofix_panel
          :if={@selected_finding && @selected_fix}
          finding={@selected_finding}
          fix={@selected_fix}
          copy_event="copy_fix_prompt"
          close_event="close_fix"
        />
      </section>
    </Layouts.app>
    """
  end

  defp refresh_browser(socket) do
    browser = Mission.browse_findings(browser_form_params(socket.assigns.browser.filters))

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
      workspace = (session.workspace && session.workspace.name) || "Workspace"
      {"#{session.title} (#{workspace})", session.id}
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
