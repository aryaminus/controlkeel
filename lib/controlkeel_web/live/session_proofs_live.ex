defmodule ControlKeelWeb.SessionProofsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.SessionScope

  import ControlKeelWeb.ProofComponents,
    only: [
      bundle_get: 3,
      deploy_badge_class: 1,
      risk_tier_pill_class: 1,
      session_breadcrumb_base: 3,
      verification_score_color: 1,
      verification_status_color: 1
    ]

  @impl true
  def mount(params, _session, socket) do
    case SessionScope.resolve(socket, params) do
      {:ok, session, socket} ->
        {:ok, assign_scope(socket, session, params["org_slug"], params["ws_slug"])}

      {:error, socket} ->
        {:ok, SessionScope.session_not_found(socket, params)}
    end
  end

  defp assign_scope(socket, session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    socket
    |> assign(:page_title, "Proof Browser")
    |> assign(:browser, empty_browser())
    |> assign(:session, session)
    |> assign(:org_slug, org_slug)
    |> assign(:ws_slug, ws_slug)
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:sibling_sessions, Mission.list_sibling_sessions(workspace.id))
    |> assign(
      :breadcrumbs,
      session_breadcrumb_base(org, workspace, session) ++ [%{label: "Proofs", to: nil}]
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case SessionScope.refresh(socket, params) do
      {:ok, session, socket, true} ->
        socket = assign_scope(socket, session, params["org_slug"], params["ws_slug"])
        load_browser(socket, params, session)

      {:ok, session, socket, false} ->
        load_browser(socket, params, session)

      {:error, socket} ->
        {:noreply, SessionScope.session_not_found(socket, params)}
    end
  end

  defp load_browser(socket, params, session) do
    browser = Mission.browse_proof_bundles(Map.put(params, "session_id", session.id))

    {:noreply,
     socket
     |> assign(:page_title, "Proof Browser")
     |> assign(:browser, browser)}
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_title
        title="Proofs"
        subtitle="Immutable task evidence for this session."
      />

      <div class="bg-card border rounded-2xl shadow-card overflow-clip">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
              <tr>
                <th class="px-5 py-3 font-semibold">Task</th>
                <th class="px-5 py-3 font-semibold">Version</th>
                <th class="px-5 py-3 font-semibold">Risk</th>
                <th class="px-5 py-3 font-semibold">Readiness</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr :if={@browser.entries == []}>
                <td colspan="4" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No proof bundles found.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Proof bundles appear here as tasks are completed and verified.
                  </p>
                </td>
              </tr>
              <tr
                :for={proof <- @browser.entries}
                class="transition hover:bg-muted/30"
              >
                <td class="px-5 py-4">
                  <.link
                    navigate={
                      ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@session.id}/proofs/#{proof.id}"
                    }
                    class="font-medium text-foreground transition hover:text-primary hover:underline"
                  >
                    {proof.task.title}
                  </.link>
                </td>

                <td class="px-5 py-4">
                  <p class="font-medium text-foreground">
                    v{proof.version}
                  </p>
                  <p class="mt-1 text-xs uppercase tracking-wider text-muted-foreground">
                    {proof.status}
                  </p>
                </td>

                <td class="px-5 py-4">
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    risk_tier_pill_class(proof.session.risk_tier)
                  ]}>
                    {proof.session.risk_tier}
                  </span>
                  <span class="ml-2 text-sm tabular-nums text-muted-foreground">
                    {proof.risk_score}
                  </span>
                  <% ver = bundle_get(proof, ["verification_assessment"], %{}) %>
                  <p :if={ver["score"] || ver["status"]} class="mt-1 text-xs text-muted-foreground">
                    Verification
                    <span class={[
                      "font-semibold tabular-nums",
                      verification_score_color(ver["score"])
                    ]}>
                      {ver["score"] || "—"}
                    </span>
                    <span class={[
                      "ml-1 inline-flex rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider ring-1",
                      verification_status_color(ver["status"])
                    ]}>
                      {ver["status"] || "n/a"}
                    </span>
                  </p>
                </td>

                <td class="px-5 py-4">
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    deploy_badge_class(proof.deploy_ready)
                  ]}>
                    {if proof.deploy_ready,
                      do: "Certified ready",
                      else: "Review required"}
                  </span>
                  <% tc = bundle_get(proof, ["task_checks"], %{}) %>
                  <% t_total = tc["total"] || 0 %>
                  <% t_passed = tc["passed"] || 0 %>
                  <div :if={t_total > 0} class="mt-2 max-w-40">
                    <div class="flex items-center justify-between text-xs text-muted-foreground">
                      <span>Checks</span>
                      <span class="tabular-nums">{t_passed}/{t_total} passed</span>
                    </div>
                    <div class="mt-1 h-2 overflow-hidden rounded-full bg-muted">
                      <div
                        style={"width: #{round(t_passed / t_total * 100)}%"}
                        class="h-full rounded-full bg-primary transition-all"
                      />
                    </div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4 border-t px-5 py-4">
          <p class="text-sm text-muted-foreground">
            Page {@browser.page} of {@browser.total_pages}
          </p>
          <div class="flex gap-4">
            <%= if @browser.page > 1 do %>
              <.link
                patch={
                  ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@session.id}/proofs?#{page_params(@browser, @browser.page - 1)}"
                }
                class="text-sm font-medium text-primary transition hover:underline"
              >
                Previous
              </.link>
            <% else %>
              <span class="text-sm text-muted-foreground">Previous</span>
            <% end %>

            <%= if @browser.page < @browser.total_pages do %>
              <.link
                patch={
                  ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@session.id}/proofs?#{page_params(@browser, @browser.page + 1)}"
                }
                class="text-sm font-medium text-primary transition hover:underline"
              >
                Next
              </.link>
            <% else %>
              <span class="text-sm text-muted-foreground">Next</span>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Current filters as URL params for pagination links, with the page
  # number swapped in. `session_id` is deliberately omitted: the session
  # already scopes the path, and `handle_params` forces it back in anyway.
  defp page_params(browser, page) do
    browser.filters |> browser_form_params() |> Map.put("page", page)
  end

  defp browser_form_params(filters) do
    %{
      "q" => filters.q,
      "task_id" => filters.task_id,
      "deploy_ready" => if(filters.deploy_ready != nil, do: to_string(filters.deploy_ready)),
      "risk_tier" => filters.risk_tier
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp empty_browser do
    %{entries: [], filters: %{page: 1}, total_count: 0, total_pages: 1, page: 1, page_size: 20}
  end
end
