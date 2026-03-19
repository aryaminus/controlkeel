defmodule ControlKeelWeb.ProofBrowserLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission

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
     |> assign(:session_options, Mission.list_recent_sessions(30))
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Mission.get_proof_bundle_with_context(String.to_integer(id)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Proof bundle not found.")
         |> push_navigate(to: ~p"/proofs")}

      proof ->
        memory_hits = related_memory_hits(proof)

        {:noreply,
         socket
         |> assign(:page_title, "Proof #{proof.id}")
         |> assign(:proof, proof)
         |> assign(:memory_hits, memory_hits)}
    end
  end

  def handle_params(params, _uri, socket) do
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

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Proof browser</p>
          <h1 class="ck-section-title">Immutable proof snapshot</h1>
          <p class="ck-lead ck-lead-tight">
            Every proof bundle is a frozen audit artifact for a single task version.
          </p>
        </div>
        <div class="ck-badge-stack">
          <.link navigate={~p"/proofs"} class="ck-link">Back to proofs</.link>
          <.link navigate={~p"/missions/#{@proof.session_id}"} class="ck-link">Open mission</.link>
        </div>
      </div>

      <div class="ck-stat-grid">
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Task</p>
          <strong>{@proof.task.title}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Version</p>
          <strong>v{@proof.version}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Risk score</p>
          <strong>{@proof.risk_score}</strong>
        </div>
        <div class="ck-card ck-stat-card">
          <p class="ck-mini-label">Deploy ready</p>
          <strong>{if @proof.deploy_ready, do: "Yes", else: "No"}</strong>
        </div>
      </div>

      <div class="ck-grid ck-grid-dashboard">
        <div class="ck-card">
          <p class="ck-mini-label">Snapshot</p>
          <div class="ck-brief-grid">
            <div>
              <h3>Mission</h3>
              <p class="ck-note">{@proof.session.title}</p>
            </div>
            <div>
              <h3>Generated</h3>
              <p class="ck-note">{format_datetime(@proof.generated_at)}</p>
            </div>
            <div>
              <h3>Open findings</h3>
              <p class="ck-note">{@proof.open_findings_count}</p>
            </div>
            <div>
              <h3>Blocked findings</h3>
              <p class="ck-note">{@proof.blocked_findings_count}</p>
            </div>
            <div>
              <h3>Domain pack</h3>
              <p class="ck-note">
                {format_domain_pack(get_in(@proof.session.execution_brief || %{}, ["domain_pack"]))}
              </p>
            </div>
          </div>

          <p class="ck-mini-label" style="margin-top: 1.5rem;">Compliance attestations</p>
          <ul class="ck-mini-list">
            <%= for attestation <- List.wrap(@proof.bundle["compliance_attestations"]) do %>
              <li>
                {format_domain_pack(attestation["pack"])}: {attestation["status"]} ({attestation[
                  "blocked_count"
                ]} blocked)
              </li>
            <% end %>
          </ul>

          <p class="ck-mini-label" style="margin-top: 1.5rem;">Rollback instructions</p>
          <pre class="ck-code-block">{@proof.bundle["rollback_instructions"]}</pre>

          <p class="ck-mini-label" style="margin-top: 1.5rem;">Proof payload</p>
          <pre class="ck-code-block">{Jason.encode!(@proof.bundle, pretty: true)}</pre>
        </div>

        <div class="ck-side-stack">
          <div class="ck-card">
            <p class="ck-mini-label">Related memory</p>
            <%= if @memory_hits == [] do %>
              <p class="ck-note">No related memory hits for this task yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for hit <- @memory_hits do %>
                  <li>
                    <strong>{hit.title}</strong>
                    <p class="ck-note">{hit.summary}</p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Finding resolution summary</p>
            <div class="ck-stat-grid">
              <div class="ck-stat-card">
                <p class="ck-mini-label">Approved</p>
                <strong>
                  {get_in(@proof.bundle, ["finding_resolution_summary", "approved"]) || 0}
                </strong>
              </div>
              <div class="ck-stat-card">
                <p class="ck-mini-label">Resolved</p>
                <strong>
                  {get_in(@proof.bundle, ["finding_resolution_summary", "resolved"]) || 0}
                </strong>
              </div>
              <div class="ck-stat-card">
                <p class="ck-mini-label">Open</p>
                <strong>{get_in(@proof.bundle, ["finding_resolution_summary", "open"]) || 0}</strong>
              </div>
              <div class="ck-stat-card">
                <p class="ck-mini-label">Blocked</p>
                <strong>
                  {get_in(@proof.bundle, ["finding_resolution_summary", "blocked"]) || 0}
                </strong>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Proof browser</p>
          <h1 class="ck-section-title">Search proof bundles across missions</h1>
          <p class="ck-lead ck-lead-tight">
            Review immutable task evidence, filter by readiness and risk, and jump back to the mission that generated each bundle.
          </p>
        </div>
        <.link navigate={~p"/"} class="ck-link">Back home</.link>
      </div>

      <div class="ck-card ck-browser-filters">
        <.form for={@form} id="proof-filters" phx-change="filter">
          <div class="ck-filter-grid">
            <.input
              field={@form[:q]}
              type="text"
              label="Search"
              placeholder="Mission or task..."
              phx-debounce="300"
            />
            <.input
              field={@form[:session_id]}
              type="select"
              label="Mission"
              prompt="All missions"
              options={Enum.map(@session_options, &{&1.title, &1.id})}
            />
            <.input
              field={@form[:task_id]}
              type="text"
              label="Task ID"
              placeholder="Task id"
            />
            <.input
              field={@form[:deploy_ready]}
              type="select"
              label="Deploy ready"
              prompt="All"
              options={[{"Yes", "true"}, {"No", "false"}]}
            />
            <.input
              field={@form[:risk_tier]}
              type="select"
              label="Risk tier"
              prompt="All tiers"
              options={Enum.map(@risk_tiers, &{String.capitalize(&1), &1})}
            />
          </div>
        </.form>

        <div class="ck-metric-row">
          <span>{@browser.total_count} total proof bundles</span>
          <span>Page {@browser.page} of {@browser.total_pages}</span>
        </div>
      </div>

      <div class="ck-card">
        <div class="ck-table-wrap">
          <.table id="proofs-browser" rows={@browser.entries}>
            <:col :let={proof} label="Task">
              <div>
                <strong>{proof.task.title}</strong>
                <p class="ck-note">{proof.session.title}</p>
              </div>
            </:col>
            <:col :let={proof} label="Version">
              <div>
                <strong>v{proof.version}</strong>
                <p class="ck-note">{proof.status}</p>
              </div>
            </:col>
            <:col :let={proof} label="Risk">
              <div class="ck-badge-stack">
                <span class={["ck-pill", "ck-pill-#{proof.session.risk_tier}"]}>
                  {proof.session.risk_tier}
                </span>
                <span class="ck-pill ck-pill-neutral">{proof.risk_score}</span>
              </div>
            </:col>
            <:col :let={proof} label="Readiness">
              <span class="ck-note">
                {if proof.deploy_ready, do: "Deploy ready", else: "Review required"}
              </span>
            </:col>
            <:action :let={proof}>
              <.link navigate={~p"/missions/#{proof.session_id}"} class="ck-link">Mission</.link>
            </:action>
            <:action :let={proof}>
              <.link navigate={~p"/proofs/#{proof.id}"} class="ck-link">View proof</.link>
            </:action>
          </.table>
        </div>

        <div class="ck-action-row" style="margin-top: 1rem;">
          <.link
            :if={@browser.page > 1}
            patch={
              ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page - 1})}"
            }
            class="ck-link"
          >
            Previous page
          </.link>
          <div />
          <.link
            :if={@browser.page < @browser.total_pages}
            patch={
              ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page + 1})}"
            }
            class="ck-link"
          >
            Next page
          </.link>
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
      "deploy_ready" => filters.deploy_ready,
      "risk_tier" => filters.risk_tier
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

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
  defp format_datetime(nil), do: "Not recorded"
  defp format_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
end
