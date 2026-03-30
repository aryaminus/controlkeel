defmodule ControlKeelWeb.DeploymentLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Deployment.Advisor
  alias ControlKeel.Deployment.HostingCost

  @impl true
  def mount(_params, _session, socket) do
    project_root = socket.endpoint.config(:project_root) || File.cwd!()

    socket =
      socket
      |> assign(:page_title, "Deployment Advisor")
      |> assign(:project_root, project_root)
      |> assign(:analysis, nil)
      |> assign(:cost_estimates, nil)
      |> assign(:generating, false)
      |> assign(:generated_files, nil)
      |> assign(:selected_tier, "free")
      |> assign(:needs_db, true)
      |> assign(:show_costs, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    {:ok, analysis} = Advisor.analyze(socket.assigns.project_root)
    {:noreply, assign(socket, :analysis, analysis)}
  end

  @impl true
  def handle_event("estimate_costs", _params, socket) do
    tier = String.to_atom(socket.assigns.selected_tier)

    {:ok, estimates} =
      HostingCost.estimate(
        stack: socket.assigns.analysis.stack,
        tier: tier,
        needs_db: socket.assigns.needs_db,
        expected_bandwidth_gb: 10,
        expected_storage_gb: 1
      )

    {:noreply, assign(socket, cost_estimates: estimates, show_costs: true)}
  end

  @impl true
  def handle_event("toggle_db", _params, socket) do
    {:noreply, assign(socket, :needs_db, not socket.assigns.needs_db)}
  end

  @impl true
  def handle_event("select_tier", %{"tier" => tier}, socket) do
    {:noreply, assign(socket, :selected_tier, tier)}
  end

  @impl true
  def handle_event("generate_files", _params, socket) do
    {:ok, results} =
      Advisor.generate_files(
        socket.assigns.project_root,
        socket.assigns.analysis.generators,
        dry_run: true
      )

    {:noreply, assign(socket, :generated_files, results)}
  end

  @impl true
  def handle_event("write_files", _params, socket) do
    {:ok, results} =
      Advisor.generate_files(
        socket.assigns.project_root,
        socket.assigns.analysis.generators,
        dry_run: false
      )

    {:noreply,
     socket
     |> assign(:generated_files, results)
     |> put_flash(:info, "Files written successfully!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <section class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">Deployment</p>
          <h1 class="ck-section-title">Deployment Advisor</h1>
          <p class="ck-lead ck-lead-tight">
            Analyze your project stack, generate Dockerfiles, CI pipelines, and estimate hosting costs across major platforms.
          </p>
        </div>
        <div class="ck-action-row">
          <button phx-click="analyze" class="ck-btn ck-btn-primary">
            Analyze Project
          </button>
          <a href={~p"/"} class="ck-link">Back home</a>
        </div>
      </div>

      <%= if @analysis do %>
        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Detected Stack</p>
            <strong class="text-lg">{String.capitalize(to_string(@analysis.stack))}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Monthly Cost Range</p>
            <strong>
              ${@analysis.monthly_cost_range.low} - ${@analysis.monthly_cost_range.high}
            </strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Compatible Platforms</p>
            <strong>{length(@analysis.platforms)}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Files to Generate</p>
            <strong>{length(@analysis.generators)}</strong>
          </div>
        </div>

        <div class="ck-card">
          <div class="flex items-center justify-between mb-4">
            <h2 class="ck-card-title">Recommended Platforms</h2>
            <div class="flex gap-2 items-center">
              <label class="ck-mini-label">Tier:</label>
              <select phx-change="select_tier" class="ck-input text-sm" style="width:auto">
                <option value="free" selected={@selected_tier == "free"}>Free</option>
                <option value="hobby" selected={@selected_tier == "hobby"}>Hobby ($5-10/mo)</option>
                <option value="standard_1x" selected={@selected_tier == "standard_1x"}>
                  Standard ($25/mo)
                </option>
                <option value="performance" selected={@selected_tier == "performance"}>
                  Performance ($85+/mo)
                </option>
              </select>
              <label class="flex items-center gap-1 text-sm">
                <input type="checkbox" checked={@needs_db} phx-click="toggle_db" class="rounded" />
                Database
              </label>
              <button phx-click="estimate_costs" class="ck-btn ck-btn-sm">
                Estimate Costs
              </button>
            </div>
          </div>

          <%= if @show_costs and @cost_estimates do %>
            <div class="ck-table-wrap">
              <.table id="cost-estimates" rows={@cost_estimates}>
                <:col :let={est} label="Platform">
                  <div>
                    <strong>{est.name}</strong>
                    <%= if est.fits_stack do %>
                      <span class="inline-block ml-2 px-1.5 py-0.5 text-xs rounded bg-green-100 text-green-800">
                        Best fit
                      </span>
                    <% end %>
                  </div>
                </:col>
                <:col :let={est} label="Compute">
                  ${:erlang.float_to_binary(est.breakdown.compute / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Database">
                  ${:erlang.float_to_binary(est.breakdown.database / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Bandwidth">
                  ${:erlang.float_to_binary(est.breakdown.bandwidth / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Total">
                  <strong>${:erlang.float_to_binary(est.total_monthly_usd, decimals: 2)}/mo</strong>
                </:col>
              </.table>
            </div>
          <% else %>
            <div class="ck-table-wrap">
              <.table id="platform-list" rows={@analysis.platforms}>
                <:col :let={p} label="Platform">
                  <a href={p.url} target="_blank" class="ck-link">{p.name}</a>
                </:col>
                <:col :let={p} label="Tier">
                  {p.tier.name}
                </:col>
                <:col :let={p} label="Starting Price">
                  <%= if p.tier.monthly_low == 0 do %>
                    Free
                  <% else %>
                    ${p.tier.monthly_low}/mo
                  <% end %>
                </:col>
                <:col :let={p} label="Notes">
                  <span class="text-sm text-gray-600">{p.notes}</span>
                </:col>
              </.table>
            </div>
          <% end %>
        </div>

        <div class="ck-card">
          <div class="flex items-center justify-between mb-4">
            <h2 class="ck-card-title">Generated Files (Preview)</h2>
            <div class="flex gap-2">
              <button phx-click="generate_files" class="ck-btn ck-btn-sm">
                Preview Files
              </button>
              <button phx-click="write_files" class="ck-btn ck-btn-primary ck-btn-sm">
                Write to Disk
              </button>
            </div>
          </div>

          <%= if @generated_files do %>
            <div class="space-y-4">
              <%= for {:ok, name, path, content, status} <- @generated_files do %>
                <div class="border rounded-lg overflow-hidden">
                  <div class="flex items-center justify-between px-4 py-2 bg-gray-50 border-b">
                    <div>
                      <strong class="text-sm">{name}</strong>
                      <span class="ml-2 text-xs text-gray-500">{path}</span>
                    </div>
                    <span class={[
                      "text-xs px-2 py-0.5 rounded",
                      status == :written && "bg-green-100 text-green-800",
                      status == :skipped && "bg-yellow-100 text-yellow-800"
                    ]}>
                      {String.capitalize(to_string(status))}
                    </span>
                  </div>
                  <pre class="p-4 text-xs overflow-x-auto bg-gray-900 text-green-400 max-h-64"><code phx-no-curly-interpolation>{content}</code></pre>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500 text-sm">
              Click "Preview Files" to see what will be generated for your {@analysis.stack} project.
            </p>
          <% end %>
        </div>
      <% else %>
        <div class="ck-card">
          <p class="text-gray-500">
            Click "Analyze Project" to detect your project stack and get deployment recommendations.
          </p>
        </div>
      <% end %>
    </section>
    """
  end
end
