defmodule ControlKeelWeb.ProofBrowserLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  @risk_tiers ~w(low moderate high critical)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Proof Browser")
     |> assign(:proof, nil)
     |> assign(:browser, empty_browser())
     |> assign(:memory_hits, [])
     |> assign(:risk_tiers, @risk_tiers)
     |> assign(:session_options, Mission.list_recent_sessions(30, nil))
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  def handle_params(params, _uri, socket) do
    workspace_ids = org_workspace_ids(socket.assigns[:current_org_id])

    params =
      if workspace_ids != [],
        do: Map.put(params, "workspace_ids", workspace_ids),
        else: params

    browser = Mission.browse_proof_bundles(params)

    {:noreply,
     socket
     |> assign(:page_title, "Proof Browser")
     |> assign(:proof, nil)
     |> assign(:memory_hits, [])
     |> assign(:browser, browser)
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: ~p"/proofs?#{filter_params(filters)}")}
  end

  def render(assigns) do
    ~H"""
    <section class="mx-auto w-[min(1180px,calc(100%-2rem))]">
      <div class="space-y-1 mb-12">
        <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
          Proof browser
        </h2>
        <p class="text-muted-foreground">
          Review immutable task evidence, filter by readiness and risk, and jump back to the session that generated each bundle.
        </p>
      </div>

      <div class="rounded-lg border bg-card">
        <div class="space-y-4 p-4">
          <form id="proof-filters" phx-change="filter" class="grid gap-4 xl:grid-cols-5">
            <div class="space-y-4">
              <label
                for="filters-q"
                class="text-xs uppercase tracking-[0.28em]"
              >
                Search
              </label>
              <input
                id="filters-q"
                name="filters[q]"
                type="text"
                value={@form[:q].value}
                placeholder="Session or task..."
                phx-debounce="300"
                class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
              />
            </div>

            <div class="space-y-2">
              <label
                for="filters-session_id"
                class="text-xs uppercase tracking-[0.28em]"
              >
                Session
              </label>
              <select
                id="filters-session_id"
                name="filters[session_id]"
                class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
              >
                <option value="">All sessions</option>
                <%= for session_option <- @session_options do %>
                  <option
                    value={session_option.id}
                    selected={to_string(@form[:session_id].value) == to_string(session_option.id)}
                  >
                    {session_option.title}
                  </option>
                <% end %>
              </select>
            </div>

            <div class="space-y-2">
              <label
                for="filters-task_id"
                class="text-xs uppercase tracking-[0.28em]"
              >
                Task ID
              </label>
              <input
                id="filters-task_id"
                name="filters[task_id]"
                type="text"
                value={@form[:task_id].value}
                placeholder="Task id"
                class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
              />
            </div>

            <div class="space-y-2">
              <label
                for="filters-deploy_ready"
                class="text-xs uppercase tracking-[0.28em]"
              >
                Deploy ready
              </label>
              <select
                id="filters-deploy_ready"
                name="filters[deploy_ready]"
                class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
              >
                <option value="">All</option>
                <option value="true" selected={@form[:deploy_ready].value == "true"}>Yes</option>
                <option value="false" selected={@form[:deploy_ready].value == "false"}>No</option>
              </select>
            </div>

            <div class="space-y-2">
              <label
                for="filters-risk_tier"
                class="text-xs uppercase tracking-[0.28em]"
              >
                Risk tier
              </label>
              <select
                id="filters-risk_tier"
                name="filters[risk_tier]"
                class="w-full rounded-md border border-input bg-background px-4 py-3 text-sm text-foreground focus:border-primary focus:ring-2 focus:ring-primary/15 focus:outline-none"
              >
                <option value="">All tiers</option>
                <%= for tier <- @risk_tiers do %>
                  <option value={tier} selected={@form[:risk_tier].value == tier}>
                    {String.capitalize(tier)}
                  </option>
                <% end %>
              </select>
            </div>
          </form>

          <div class="flex items-center justify-between">
            <p class="text-muted-foreground tracking-tight">
              <span class="text-primary mr-1">{@browser.total_count}</span> total proof bundles found
            </p>

            <.link
              patch={~p"/proofs"}
              class="self-end rounded-md border border-input bg-background px-4 py-3 text-xs font-semibold uppercase tracking-[0.1em] text-muted-foreground transition hover:border-destructive/40 hover:text-destructive text-center"
            >
              Reset all
            </.link>
          </div>
        </div>

        <div class="overflow-x-auto w-full">
          <div class="overflow-hidden border bg-overlay/30">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-border">
                <thead class="bg-muted">
                  <tr>
                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                      Task
                    </th>

                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                      Version
                    </th>

                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                      Risk
                    </th>

                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                      Readiness
                    </th>

                    <th class="px-8 py-6 text-right text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                      Actions
                    </th>
                  </tr>
                </thead>

                <tbody class="divide-y divide-border">
                  <tr :if={@browser.entries == []}>
                    <td colspan="5" class="px-8 py-12 text-center text-sm text-muted-foreground">
                      No proof bundles match the current filters.
                    </td>
                  </tr>
                  <tr
                    :for={proof <- @browser.entries}
                    class="transition hover:bg-muted/[0.02]"
                  >
                    <td class="px-8 py-6 align-top">
                      <div>
                        <p class="font-bold text-foreground">
                          {proof.task.title}
                        </p>

                        <p class="mt-2 max-w-md text-sm text-muted-foreground">
                          {proof.session.title}
                        </p>
                      </div>
                    </td>

                    <td class="px-8 py-6 align-top">
                      <div>
                        <p class="font-semibold text-foreground">
                          v{proof.version}
                        </p>

                        <p class="mt-2 text-xs uppercase tracking-wider text-primary">
                          {proof.status}
                        </p>
                      </div>
                    </td>

                    <td class="px-8 py-6 align-top">
                      <div class="flex items-center gap-3">
                        <span class={[
                          "inline-flex rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-wider",
                          proof.session.risk_tier == "low" &&
                            "border-primary/40 bg-primary/10 text-primary",
                          proof.session.risk_tier == "moderate" &&
                            "border-info/40 bg-info/10 text-info",
                          proof.session.risk_tier == "high" &&
                            "border-destructive/40 bg-destructive/10 text-destructive"
                        ]}>
                          {proof.session.risk_tier}
                        </span>

                        <span class="inline-flex rounded-full border px-4 py-2 text-sm text-muted-foreground">
                          {proof.risk_score}
                        </span>
                      </div>
                      <% ver = bundle_get(proof, ["verification_assessment"], %{}) %>
                      <div :if={ver["score"] || ver["status"]} class="mt-2 flex items-center gap-2">
                        <span class={[
                          "text-sm font-semibold tabular-nums",
                          verification_score_color(ver["score"])
                        ]}>
                          {ver["score"] || "—"}
                        </span>
                        <span class={[
                          "inline-flex rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
                          verification_status_color(ver["status"])
                        ]}>
                          {ver["status"] || "n/a"}
                        </span>
                      </div>
                    </td>

                    <td class="px-8 py-6 align-top">
                      <div class="flex items-center gap-4">
                        <span class={[
                          "inline-flex h-8 w-8 items-center justify-center rounded-full border text-xs",
                          proof.deploy_ready &&
                            "border-primary/40 text-primary",
                          !proof.deploy_ready &&
                            "border-[var(--ck-warning)]/40 text-[var(--ck-warning)]"
                        ]}>
                          {proof.risk_score}
                        </span>

                        <span class={[
                          "text-sm",
                          proof.deploy_ready &&
                            "text-foreground",
                          !proof.deploy_ready &&
                            "text-muted-foreground"
                        ]}>
                          {if proof.deploy_ready,
                            do: "Certified ready",
                            else: "Review required"}
                        </span>
                      </div>
                      <% tc = bundle_get(proof, ["task_checks"], %{}) %>
                      <% t_total = tc["total"] || 0 %>
                      <% t_passed = tc["passed"] || 0 %>
                      <div :if={t_total > 0} class="mt-2">
                        <div class="flex items-center justify-between text-[11px] text-muted-foreground mb-1">
                          <span>Checks</span>
                          <span>{t_passed}/{t_total} passed</span>
                        </div>
                        <div class="h-1.5 rounded-full bg-card overflow-hidden">
                          <div
                            style={"width: #{if t_total > 0, do: round(t_passed / t_total * 100), else: 0}%"}
                            class="bg-primary h-full rounded-full transition-all"
                          >
                          </div>
                        </div>
                      </div>
                    </td>

                    <td class="px-2 py-6 text-right align-top">
                      <div class="flex justify-end gap-2 font-semibold text-sm">
                        <.link
                          navigate={~p"/sessions/#{proof.session_id}"}
                          class="text-muted-foreground transition hover:text-foreground border px-2 py-1 rounded-md"
                        >
                          Session
                        </.link>

                        <.link
                          navigate={proof_path(proof)}
                          class="text-primary transition hover:text-primary border px-2 py-1 rounded-md"
                        >
                          View
                        </.link>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
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
                        ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page - 1})}"
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
                        ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page + 1})}"
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
        </div>
      </div>
    </section>
    """
  end

  defp related_memory_hits(proof) do
    related = Memory.list_related_to_task(proof.task_id, 5)

    if related != [] do
      related
    else
      Memory.search(proof.task.title,
        session_id: proof.session_id,
        task_id: proof.task_id,
        top_k: 5
      ).entries
    end
  end

  defp browser_form_params(filters) do
    %{
      "q" => filters.q,
      "session_id" => filters.session_id,
      "task_id" => filters.task_id,
      "deploy_ready" => if(filters.deploy_ready != nil, do: to_string(filters.deploy_ready)),
      "risk_tier" => filters.risk_tier
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp filter_params(filters) do
    filters
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp empty_browser do
    %{entries: [], filters: %{page: 1}, total_count: 0, total_pages: 1, page: 1, page_size: 20}
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(pack) when pack in ["baseline", "cost"], do: String.capitalize(pack)
  defp format_domain_pack(pack), do: Intent.pack_label(pack)

  defp bundle_get(proof, keys, default \\ nil) do
    if proof, do: get_in(proof.bundle || %{}, keys) || default, else: default
  end

  defp verification_score_color(score) when is_integer(score) do
    cond do
      score >= 80 -> "text-primary"
      score >= 50 -> "text-[var(--ck-warning)]"
      true -> "text-destructive"
    end
  end

  defp verification_score_color(_), do: "text-muted-foreground"

  defp verification_status_color("strong"), do: "border-primary/40 bg-primary/10 text-primary"

  defp verification_status_color("moderate"),
    do: "border-[var(--ck-warning)]/40 bg-[var(--ck-warning)]/10 text-[var(--ck-warning)]"

  defp verification_status_color("weak"),
    do: "border-destructive/40 bg-destructive/10 text-destructive"

  defp verification_status_color(_), do: "border-border/40 bg-muted/10 text-muted-foreground"

  defp context_status_color("clean"), do: "border-primary/40 bg-primary/10 text-primary"

  defp context_status_color("degraded"),
    do: "border-destructive/40 bg-destructive/10 text-destructive"

  defp context_status_color(_), do: "border-border/40 bg-muted/10 text-muted-foreground"

  defp deploy_badge_class(true), do: "border-primary/40 bg-primary/10 text-primary"

  defp deploy_badge_class(_),
    do: "border-[var(--ck-warning)]/40 bg-[var(--ck-warning)]/10 text-[var(--ck-warning)]"

  defp risk_bar_width(nil), do: 0
  defp risk_bar_width(score) when is_float(score), do: min(round(score * 100), 100)
  defp risk_bar_width(_), do: 0

  # Org-bound proofs deep-link into the session-scoped detail; unbound
  # (local/orphan) rows fall back to the legacy session redirect, which
  # resolves the nesting or 404s.
  defp proof_path(proof) do
    with %{session_id: session_id} when is_integer(session_id) <- proof,
         %{workspace: %{slug: ws_slug, org: %{slug: org_slug}}} <-
           Repo.preload(proof, session: [workspace: :org]) |> Map.get(:session) do
      "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/proofs/#{proof.id}"
    else
      _ -> "/sessions/#{proof.session_id}"
    end
  end

  defp org_workspace_ids(nil), do: []

  defp org_workspace_ids(org_id) when is_integer(org_id) do
    org_id
    |> ControlKeel.Accounts.list_workspaces_for_org()
    |> Enum.map(& &1.id)
  end
end
