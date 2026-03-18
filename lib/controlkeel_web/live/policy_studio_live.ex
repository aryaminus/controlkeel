defmodule ControlKeelWeb.PolicyStudioLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Policy.PackLoader

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Policy Studio")
     |> assign_packs()
     |> assign_sessions()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Policy Studio</p>
          <h1 class="ck-section-title">Active governance rules</h1>
          <p class="ck-lead ck-lead-tight">
            Every agent action passes through these policy packs before it executes. Rules that block are enforced automatically — no action required from you.
          </p>
        </div>
        <a href={~p"/"} class="ck-link">Back home</a>
      </div>

      <div class="ck-stat-grid">
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Active packs</p>
          <strong>{@pack_count}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Total rules</p>
          <strong>{@rule_count}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Blocking rules</p>
          <strong>{@block_count}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Active sessions</p>
          <strong>{length(@sessions)}</strong>
        </div>
      </div>

      <div class="ck-grid ck-grid-dashboard">
        <div>
          <div class="ck-card">
            <p class="ck-mini-label">Policy packs</p>
            <div class="ck-finding-list">
              <%= for {name, rules} <- @packs do %>
                <article class="ck-finding-item">
                  <div class="ck-finding-head">
                    <h3>{pack_label(name)}</h3>
                    <span class={"ck-pill #{pack_pill_class(name)}"}>{length(rules)} rules</span>
                  </div>
                  <p class="ck-note">{pack_description(name)}</p>
                  <div class="ck-tag-list" style="margin-top: 0.5rem;">
                    <%= for rule <- rules do %>
                      <span class={"ck-tag ck-severity-#{rule.severity}"}>
                        {rule.action}: {rule.category}
                      </span>
                    <% end %>
                  </div>
                </article>
              <% end %>
            </div>
          </div>
        </div>

        <div>
          <div class="ck-card" style="margin-bottom: 1rem;">
            <p class="ck-mini-label">Session budgets</p>
            <%= if @sessions == [] do %>
              <p class="ck-note">
                No active sessions. Start a mission at <a href={~p"/start"} class="ck-link">/start</a>.
              </p>
            <% else %>
              <div class="ck-finding-list">
                <%= for session <- @sessions do %>
                  <article class="ck-finding-item">
                    <div class="ck-finding-head">
                      <h3>
                        <.link navigate={~p"/missions/#{session.id}"} class="ck-link">
                          {session.title}
                        </.link>
                      </h3>
                      <span class={"ck-pill #{risk_pill_class(session.risk_tier)}"}>
                        {session.risk_tier}
                      </span>
                    </div>
                    <div class="ck-metric-row" style="margin-top: 0.5rem;">
                      <span class="ck-note">
                        Budget: {format_cents(session.budget_cents)}
                      </span>
                      <span class="ck-note">
                        Spent: {format_cents(session.spent_cents)}
                      </span>
                      <span class="ck-note">
                        Daily cap: {format_cents(session.daily_budget_cents)}
                      </span>
                    </div>
                    <%= if (session.budget_cents || 0) > 0 do %>
                      <% pct = budget_pct(session.spent_cents, session.budget_cents) %>
                      <div class="ck-progress-bar">
                        <div
                          class={"ck-progress-fill #{budget_fill_class(pct)}"}
                          style={"width: #{pct}%"}
                        >
                        </div>
                      </div>
                    <% end %>
                  </article>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">What gets blocked automatically</p>
            <ul class="ck-mini-list">
              <li>Hardcoded API keys, passwords, tokens (baseline pack)</li>
              <li>SQL injection patterns (baseline pack)</li>
              <li>Open CORS wildcard headers (software pack)</li>
              <li>Dynamic code execution — eval, exec (software pack)</li>
              <li>Auth bypass patterns (software pack)</li>
              <li>Agent runs that would exceed session budget (cost pack)</li>
            </ul>
            <p class="ck-note" style="margin-top: 1rem;">
              Warnings let the agent continue but surface a finding for your review. Blocks stop execution and require a policy fix before proceeding.
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp assign_packs(socket) do
    packs = PackLoader.all_packs()
    all_rules = packs |> Map.values() |> List.flatten()

    socket
    |> assign(:packs, Enum.sort_by(packs, fn {name, _} -> pack_sort_order(name) end))
    |> assign(:pack_count, map_size(packs))
    |> assign(:rule_count, length(all_rules))
    |> assign(:block_count, Enum.count(all_rules, &(&1.action == "block")))
  end

  defp assign_sessions(socket) do
    sessions = Mission.list_recent_sessions(20)
    assign(socket, :sessions, sessions)
  end

  defp pack_label("baseline"), do: "Baseline — Secrets & OWASP"
  defp pack_label("cost"), do: "Cost — Budget guardrails"
  defp pack_label("software"), do: "Software — Code hygiene"
  defp pack_label("healthcare"), do: "Healthcare — HIPAA / PHI"
  defp pack_label("education"), do: "Education — FERPA / COPPA"
  defp pack_label("finance"), do: "Finance — PCI-DSS / SOX"
  defp pack_label(name), do: String.capitalize(name)

  defp pack_description("baseline"),
    do: "Always active. Detects secrets, injection, and XSS in all agent output."

  defp pack_description("cost"),
    do: "Always active. Warns at 80% of budget, blocks at 100%."

  defp pack_description("software"),
    do: "Active for software domain. Catches debug endpoints, auth bypass, eval, open CORS."

  defp pack_description("healthcare"),
    do: "Active when domain pack is healthcare. Flags PHI patterns and HIPAA-sensitive data."

  defp pack_description("education"),
    do: "Active when domain pack is education. Flags student data and FERPA-sensitive content."

  defp pack_description("finance"),
    do: "Active when domain pack is finance. Flags payment card data and SOX-sensitive records."

  defp pack_description(_), do: "Domain-specific policy rules."

  defp pack_pill_class("baseline"), do: "ck-pill-critical"
  defp pack_pill_class("cost"), do: "ck-pill-medium"
  defp pack_pill_class(_), do: "ck-pill-neutral"

  defp pack_sort_order("baseline"), do: 0
  defp pack_sort_order("cost"), do: 1
  defp pack_sort_order("software"), do: 2
  defp pack_sort_order(_), do: 3

  defp risk_pill_class("critical"), do: "ck-pill-critical"
  defp risk_pill_class("high"), do: "ck-pill-high"
  defp risk_pill_class(_), do: "ck-pill-neutral"

  defp format_cents(nil), do: "not set"
  defp format_cents(0), do: "$0"

  defp format_cents(cents),
    do:
      "$#{div(cents, 100)}.#{rem(cents, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp budget_pct(_spent, nil), do: 0
  defp budget_pct(_spent, 0), do: 0
  defp budget_pct(spent, budget), do: min(round((spent || 0) / budget * 100), 100)

  defp budget_fill_class(pct) when pct >= 90, do: "ck-progress-critical"
  defp budget_fill_class(pct) when pct >= 75, do: "ck-progress-warn"
  defp budget_fill_class(_), do: "ck-progress-ok"
end
