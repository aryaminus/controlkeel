defmodule ControlKeelWeb.DeploymentComponents do
  @moduledoc """
  Deploy review page sections rendered from `DeployReviewLive`. Events
  (`set_tab`, `select_tier`, `select_db_tier`, `toggle_db`, `set_bandwidth`,
  `set_storage`, `estimate_costs`, `preview_files`, `arm_write`,
  `cancel_write`, `confirm_write_files`, `copy_generated_file`) are handled by
  the parent LiveView.
  """

  use Phoenix.Component

  import ControlKeelWeb.CoreComponents, only: [button: 1, icon: 1]
  import ControlKeelWeb.Typography

  attr :tab, :string, required: true
  attr :name, :string, required: true

  def tab_link(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_tab"
      phx-value-tab={@name}
      class={[
        "rounded-full px-4 py-1.5 text-sm font-semibold capitalize transition cursor-pointer",
        @tab == @name && "bg-primary/15 text-primary ring-1 ring-primary/30",
        @tab != @name && "text-muted-foreground hover:bg-muted hover:text-foreground"
      ]}
    >
      {@name}
    </button>
    """
  end

  def unavailable_notice(assigns) do
    ~H"""
    <div class="rounded-2xl border bg-card p-5 shadow-card">
      <p class="text-sm font-medium text-foreground">
        This session's project is not available on this machine.
      </p>
      <p class="mt-1 text-sm text-muted-foreground">
        ControlKeel could not resolve a project root on disk for this session, so deployment analysis cannot run here. From your machine, run:
      </p>
      <code class="mt-3 inline-block font-mono bg-muted px-2 py-1 rounded text-xs text-foreground">
        controlkeel deploy analyze --project-root &lt;path&gt;
      </code>
    </div>
    """
  end

  attr :analysis, :map, required: true

  def overview_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Detected stack" value={String.capitalize(to_string(@analysis.stack))} />
        <.stat_card
          label="Monthly cost range"
          value={"$#{@analysis.monthly_cost_range.low} - $#{@analysis.monthly_cost_range.high}"}
        />
        <.stat_card label="Compatible platforms" value={length(@analysis.platforms)} />
        <.stat_card label="Files to generate" value={length(@analysis.generators)} />
      </div>

      <section class="space-y-3">
        <.section_title>Recommended platforms</.section_title>
        <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
              <tr>
                <th class="px-5 py-3 font-semibold">Platform</th>
                <th class="px-5 py-3 font-semibold">Tier</th>
                <th class="px-5 py-3 font-semibold">Starting price</th>
                <th class="px-5 py-3 font-semibold">Notes</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= for p <- @analysis.platforms do %>
                <tr class="transition hover:bg-muted/30">
                  <td class="px-5 py-4">
                    <a
                      href={p.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-medium text-foreground transition hover:text-primary"
                    >
                      {p.name}
                    </a>
                  </td>
                  <td class="px-5 py-4 text-muted-foreground">{p.tier.name}</td>
                  <td class="px-5 py-4 text-muted-foreground">
                    <%= if p.tier.monthly_low == 0 do %>
                      Free
                    <% else %>
                      ${p.tier.monthly_low}/mo
                    <% end %>
                  </td>
                  <td class="px-5 py-4 text-muted-foreground">{p.notes}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  attr :analysis, :map, required: true
  attr :tiers, :list, required: true
  attr :db_tiers, :list, required: true
  attr :selected_tier, :string, required: true
  attr :selected_db_tier, :string, required: true
  attr :needs_db, :boolean, required: true
  attr :bandwidth_gb, :integer, required: true
  attr :storage_gb, :integer, required: true
  attr :cost_estimates, :list, default: nil

  def costs_panel(assigns) do
    ~H"""
    <section class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <.section_title>Cost estimator</.section_title>

        <div class="flex flex-wrap items-center gap-3 text-sm">
          <label class="flex items-center gap-2 text-muted-foreground">
            Tier
            <select
              phx-change="select_tier"
              class="rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground cursor-pointer"
            >
              <option :for={{value, label} <- @tiers} value={value} selected={@selected_tier == value}>
                {label}
              </option>
            </select>
          </label>

          <label class="flex cursor-pointer items-center gap-2 text-muted-foreground">
            <input
              type="checkbox"
              checked={@needs_db}
              phx-click="toggle_db"
              class="size-4 rounded border-input bg-background accent-primary"
            /> Database
          </label>

          <label :if={@needs_db} class="flex items-center gap-2 text-muted-foreground">
            DB tier
            <select
              phx-change="select_db_tier"
              class="rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground cursor-pointer"
            >
              <option
                :for={{value, label} <- @db_tiers}
                value={value}
                selected={@selected_db_tier == value}
              >
                {label}
              </option>
            </select>
          </label>

          <label class="flex items-center gap-2 text-muted-foreground">
            Bandwidth GB
            <input
              type="number"
              name="bandwidth"
              value={@bandwidth_gb}
              min="0"
              class="w-20 rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground"
              phx-change="set_bandwidth"
            />
          </label>

          <label class="flex items-center gap-2 text-muted-foreground">
            Storage GB
            <input
              type="number"
              name="storage"
              value={@storage_gb}
              min="0"
              class="w-20 rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground"
              phx-change="set_storage"
            />
          </label>

          <.button phx-click="estimate_costs">Estimate costs</.button>
        </div>
      </div>

      <%= if @cost_estimates do %>
        <.costs_table estimates={@cost_estimates} />
      <% else %>
        <p class="text-sm text-muted-foreground">
          Choose a tier and click "Estimate costs" to compare monthly hosting across platforms for your {@analysis.stack} project.
        </p>
      <% end %>
    </section>
    """
  end

  attr :estimates, :list, required: true

  defp costs_table(assigns) do
    ~H"""
    <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
      <table class="min-w-full divide-y divide-border text-left text-sm">
        <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
          <tr>
            <th class="px-5 py-3 font-semibold">Platform</th>
            <th class="px-5 py-3 font-semibold">Compute</th>
            <th class="px-5 py-3 font-semibold">Database</th>
            <th class="px-5 py-3 font-semibold">Bandwidth</th>
            <th class="px-5 py-3 font-semibold">Storage</th>
            <th class="px-5 py-3 font-semibold text-right">Total</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-border">
          <%= for est <- @estimates do %>
            <tr class="transition hover:bg-muted/30">
              <td class="px-5 py-4">
                <div class="flex items-center gap-2">
                  <span class="font-medium text-foreground">{est.name}</span>
                  <%= if est.fits_stack do %>
                    <span class="inline-flex rounded-full bg-success/10 px-2 py-0.5 text-xs font-semibold text-success ring-1 ring-success/20">
                      Best fit
                    </span>
                  <% end %>
                </div>
              </td>
              <td class="px-5 py-4 text-muted-foreground">
                ${format_cents(est.breakdown.compute)}/mo
              </td>
              <td class="px-5 py-4 text-muted-foreground">
                ${format_cents(est.breakdown.database)}/mo
              </td>
              <td class="px-5 py-4 text-muted-foreground">
                ${format_cents(est.breakdown.bandwidth)}/mo
              </td>
              <td class="px-5 py-4 text-muted-foreground">
                ${format_cents(est.breakdown.storage)}/mo
              </td>
              <td class="px-5 py-4 text-right font-medium text-foreground">
                ${format_usd(est.total_monthly_usd)}/mo
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :analysis, :map, required: true
  attr :generated_files, :list, default: nil
  attr :generate_mode, :atom, default: nil
  attr :confirm_write, :boolean, default: false

  def files_panel(assigns) do
    ~H"""
    <section class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <.section_title>Deployment files</.section_title>
        <div class="flex flex-wrap items-center gap-2">
          <.button phx-click="preview_files">Preview files</.button>
          <.button variant="secondary" phx-click="arm_write" disabled={!@generated_files}>
            Write files…
          </.button>
        </div>
      </div>

      <%= if @confirm_write do %>
        <div class="rounded-2xl border border-warning/40 bg-warning/10 p-4 flex flex-wrap items-center justify-between gap-3">
          <p class="text-sm text-foreground">
            Write {length(@generated_files)} files to the project root? Existing files are never overwritten.
          </p>
          <div class="flex items-center gap-2">
            <.button phx-click="confirm_write_files">Confirm write</.button>
            <.button variant="outline" phx-click="cancel_write">Cancel</.button>
          </div>
        </div>
      <% end %>

      <%= if @generated_files do %>
        <div class="space-y-6">
          <%= for result <- @generated_files do %>
            <div class="divide-y divide-border bg-card border rounded-2xl shadow-card overflow-hidden">
              <div class="flex items-center justify-between gap-3 px-5 py-3">
                <div class="min-w-0">
                  <p class="font-medium text-foreground">{file_name(result)}</p>
                  <p class="mt-0.5 truncate text-xs text-muted-foreground">{file_path(result)}</p>
                </div>
                <div class="flex shrink-0 items-center gap-2">
                  <.button
                    :if={match?({:ok, _name, _path, _content, _status}, result)}
                    variant="secondary"
                    phx-click="copy_generated_file"
                    phx-value-name={file_name(result)}
                  >
                    <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
                  </.button>
                  <span class={[
                    "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                    status_class(result)
                  ]}>
                    {status_label(result, @generate_mode)}
                  </span>
                </div>
              </div>
              <%= case result do %>
                <% {:ok, _name, _path, content, _status} -> %>
                  <pre class="max-h-64 overflow-x-auto bg-muted px-5 py-4 font-mono text-xs text-foreground/90"><code>{content}</code></pre>
                <% {:error, _name, _path, reason} -> %>
                  <p class="px-5 py-4 text-sm font-medium text-destructive">
                    Write failed: {format_error(reason)}
                  </p>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-sm text-muted-foreground">
          Click "Preview files" to see what will be generated for your {@analysis.stack} project.
        </p>
      <% end %>
    </section>
    """
  end

  attr :guides, :map, default: nil

  def guides_panel(assigns) do
    ~H"""
    <section class="space-y-3">
      <%= if @guides do %>
        <details class="group rounded-2xl border bg-card p-5 shadow-card" open>
          <summary class="flex cursor-pointer select-none list-none items-center gap-2">
            <.card_title>DNS & SSL setup</.card_title>
            <.icon
              name="hero-chevron-right"
              class="size-3.5 group-open:rotate-90 transition-transform"
            />
          </summary>
          <div class="mt-4 space-y-4">
            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">DNS steps</p>
              <ol class="space-y-1 text-sm text-muted-foreground list-decimal ml-5">
                <%= for step <- @guides.dns_ssl.dns_setup do %>
                  <li>{step}</li>
                <% end %>
              </ol>
            </div>
            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">SSL</p>
              <ul class="space-y-1 text-sm text-muted-foreground list-disc ml-5">
                <%= for step <- @guides.dns_ssl.ssl_setup do %>
                  <li>{step}</li>
                <% end %>
              </ul>
            </div>
            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">Registrars</p>
              <div class="flex flex-wrap gap-2">
                <%= for r <- @guides.dns_ssl.domain_registrars do %>
                  <a
                    href={r.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-2 rounded-full border bg-muted/[0.05] px-3 py-1 text-xs text-muted-foreground transition hover:text-primary"
                  >
                    {r.name} · {r.price}
                  </a>
                <% end %>
              </div>
            </div>
            <div class="space-y-1.5">
              <p class="text-sm font-semibold text-muted-foreground">Free SSL options</p>
              <p class="text-sm text-muted-foreground">
                <strong>Let's Encrypt:</strong> {@guides.dns_ssl.free_ssl.letsencrypt}
              </p>
              <p class="text-sm text-muted-foreground">
                <strong>Cloudflare:</strong> {@guides.dns_ssl.free_ssl.cloudflare}
              </p>
              <p class="text-sm text-muted-foreground">
                <strong>Platform-provided:</strong> {@guides.dns_ssl.free_ssl.platform_provided}
              </p>
            </div>
          </div>
        </details>

        <details class="group rounded-2xl border bg-card p-5 shadow-card">
          <summary class="flex cursor-pointer select-none list-none items-center gap-2">
            <.card_title>Database migrations</.card_title>
            <.icon
              name="hero-chevron-right"
              class="size-3.5 group-open:rotate-90 transition-transform"
            />
          </summary>
          <div class="mt-4 space-y-4">
            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">Steps</p>
              <ol class="space-y-1 text-sm text-muted-foreground list-decimal ml-5">
                <%= for step <- @guides.migration.steps do %>
                  <li>{step}</li>
                <% end %>
              </ol>
            </div>
            <p class="rounded-xl bg-warning/10 p-3 text-sm text-foreground">
              Rollback: {@guides.migration.rollback}
            </p>
            <p class="text-sm text-muted-foreground">
              Backup first:
              <code class="font-mono bg-muted px-1.5 py-0.5 rounded text-xs">
                {@guides.migration.backup_before}
              </code>
            </p>
          </div>
        </details>

        <details class="group rounded-2xl border bg-card p-5 shadow-card">
          <summary class="flex cursor-pointer select-none list-none items-center gap-2">
            <.card_title>Scaling</.card_title>
            <.icon
              name="hero-chevron-right"
              class="size-3.5 group-open:rotate-90 transition-transform"
            />
          </summary>
          <div class="mt-4 space-y-4">
            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">
                Vertical — {@guides.scaling.vertical_scaling.description}
              </p>
              <table class="min-w-full divide-y divide-border text-left text-sm">
                <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                  <tr>
                    <th class="px-4 py-2 font-semibold">Users</th>
                    <th class="px-4 py-2 font-semibold">Instance</th>
                    <th class="px-4 py-2 font-semibold text-right">Cost</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-border">
                  <%= for t <- @guides.scaling.vertical_scaling.tiers do %>
                    <tr>
                      <td class="px-4 py-2 text-muted-foreground">{t.users}</td>
                      <td class="px-4 py-2 text-muted-foreground">{t.tier}</td>
                      <td class="px-4 py-2 text-right text-muted-foreground">{t.cost}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
              <p class="mt-2 text-xs text-muted-foreground">
                {@guides.scaling.vertical_scaling.note}
              </p>
            </div>

            <p class="text-sm text-muted-foreground">
              <strong>Horizontal:</strong> {@guides.scaling.horizontal_scaling}
            </p>
            <p class="text-sm text-muted-foreground">
              <strong>Database:</strong> {@guides.scaling.database_scaling}
            </p>

            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">Caching</p>
              <ul class="space-y-1 text-sm text-muted-foreground list-disc ml-5">
                <%= for c <- @guides.scaling.caching do %>
                  <li><strong>{c.type}:</strong> {c.recommendation}</li>
                <% end %>
              </ul>
            </div>

            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">Monitoring</p>
              <ul class="space-y-1 text-sm text-muted-foreground list-disc ml-5">
                <%= for m <- @guides.scaling.monitoring do %>
                  <li><strong>{m.type}:</strong> {m.tool} — {m.setup}</li>
                <% end %>
              </ul>
            </div>

            <div>
              <p class="text-sm font-semibold text-muted-foreground mb-2">
                Concurrent users cost ladder
              </p>
              <table class="min-w-full divide-y divide-border text-left text-sm">
                <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                  <tr>
                    <th class="px-4 py-2 font-semibold">Users</th>
                    <th class="px-4 py-2 font-semibold">Infrastructure</th>
                    <th class="px-4 py-2 font-semibold text-right">Cost</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-border">
                  <%= for row <- @guides.scaling.concurrent_users_guide do %>
                    <tr>
                      <td class="px-4 py-2 text-muted-foreground">{row.users}</td>
                      <td class="px-4 py-2 text-muted-foreground">{row.infrastructure}</td>
                      <td class="px-4 py-2 text-right text-muted-foreground">{row.cost}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </details>
      <% else %>
        <p class="text-sm text-muted-foreground">Loading guides…</p>
      <% end %>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat_card(assigns) do
    ~H"""
    <article class="rounded-2xl border bg-card p-5 shadow-card">
      <p class="text-sm font-medium text-muted-foreground">{@label}</p>
      <p class="mt-2 text-xl font-semibold text-foreground/90">{@value}</p>
    </article>
    """
  end

  defp file_name({:ok, name, _path, _content, _status}), do: name
  defp file_name({:error, name, _path, _reason}), do: name

  defp file_path({:ok, _name, path, _content, _status}), do: path
  defp file_path({:error, _name, path, _reason}), do: path

  defp status_label({:ok, _name, _path, _content, :skipped}, :write),
    do: "Skipped (already exists)"

  defp status_label({:ok, _name, _path, _content, :skipped}, _mode), do: "Skipped (dry run)"
  defp status_label({:ok, _name, _path, _content, status}, _mode), do: status_label(status)
  defp status_label({:error, _name, _path, _reason}, _mode), do: "Write failed"

  defp status_label(:written), do: "Written"
  defp status_label(status), do: String.capitalize(to_string(status))

  defp status_class({:ok, _name, _path, _content, :written}),
    do: "bg-success/10 text-success ring-success/20"

  defp status_class({:ok, _name, _path, _content, :skipped}),
    do: "bg-warning/10 text-warning ring-warning/20"

  defp status_class({:error, _name, _path, _reason}),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  defp format_error(reason) when is_atom(reason), do: to_string(:file.format_error(reason))
  defp format_error(reason), do: inspect(reason)

  defp format_cents(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
  defp format_usd(amount), do: :erlang.float_to_binary(amount, decimals: 2)
end
