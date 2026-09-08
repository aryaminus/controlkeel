defmodule ControlKeelWeb.ReleaseReadiness do
  @moduledoc """
  Renders the per-session release readiness gate in Mission Control: verdict
  badge, release-candidate proof, findings breakdown, blocking reasons, and
  the smoke/provenance evidence form. Events (`check_release_readiness`) are
  handled by the parent LiveView.
  """
  use ControlKeelWeb, :html

  attr :readiness, :map, default: nil, doc: "result map from Governance.release_readiness/1"
  attr :form, Phoenix.HTML.Form, required: true
  attr :session_id, :integer, required: true

  def release_readiness(assigns) do
    ~H"""
    <section id="mission-release-readiness" class="rounded-2xl border bg-card p-5 shadow-card mt-6">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <.section_title>Release readiness</.section_title>
        <span
          :if={@readiness}
          id="release-readiness-status"
          class={status_badge_class(@readiness["status"])}
        >
          {status_label(@readiness["status"])}
        </span>
      </div>
      <p class="text-sm text-muted-foreground mt-2">
        Ship / no-ship gate over proof state, findings, smoke evidence, and artifact provenance —
        the same gate behind <code class="font-mono bg-muted px-1.5 py-0.5 rounded text-xs">controlkeel release-ready</code>.
      </p>

      <%= if is_nil(@readiness) do %>
        <p class="mt-4 text-sm text-muted-foreground" id="release-readiness-unavailable">
          Release readiness could not be evaluated for this session yet. Submit the evidence below to run the gate.
        </p>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
          <div class="rounded-2xl bg-muted p-4">
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
              Release-candidate proof
            </p>
            <%= if @readiness["proof"] do %>
              <div class="flex flex-wrap items-center gap-2">
                <.link
                  navigate={~p"/proofs/#{@readiness["proof"]["id"]}"}
                  class="text-sm font-medium text-primary transition hover:text-primary"
                >
                  Proof #{@readiness["proof"]["id"]} v{@readiness["proof"]["version"]}
                </.link>
                <span class={[
                  "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1",
                  if(@readiness["proof"]["deploy_ready"],
                    do: "bg-success/10 text-success ring-success/20",
                    else: "bg-warning/10 text-warning ring-warning/20"
                  )
                ]}>
                  {if @readiness["proof"]["deploy_ready"], do: "deploy-ready", else: "review required"}
                </span>
                <span class="text-xs text-muted-foreground">
                  risk {@readiness["proof"]["risk_score"]}
                </span>
              </div>
            <% else %>
              <p class="text-sm text-muted-foreground">
                No proof bundle is available for release review yet.
              </p>
            <% end %>
          </div>
          <div class="rounded-2xl bg-muted p-4">
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
              Unresolved findings
            </p>
            <div class="flex flex-wrap items-center gap-1.5">
              <span class="inline-flex rounded-full border bg-card px-2.5 py-1 text-xs text-muted-foreground">
                {@readiness["findings"]["open"]} open
              </span>
              <span class="inline-flex rounded-full border bg-card px-2.5 py-1 text-xs text-muted-foreground">
                {@readiness["findings"]["blocked"]} blocked
              </span>
              <span class="inline-flex rounded-full border bg-card px-2.5 py-1 text-xs text-muted-foreground">
                {@readiness["findings"]["escalated"]} escalated
              </span>
              <span class="inline-flex rounded-full border bg-card px-2.5 py-1 text-xs text-muted-foreground">
                {@readiness["findings"]["high_or_critical"]} high or critical
              </span>
              <span
                :if={@readiness["findings"]["critical_vulnerability_cases"] > 0}
                class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ring-1 bg-destructive/10 text-destructive ring-destructive/20"
              >
                {@readiness["findings"]["critical_vulnerability_cases"]} vulnerability case(s)
              </span>
            </div>
            <.link
              navigate={~p"/findings?#{%{"session_id" => @session_id, "status" => "open"}}"}
              class="inline-flex items-center gap-1 mt-3 text-sm font-medium text-muted-foreground transition hover:text-primary"
            >
              View open findings <.icon name="hero-arrow-up-right" class="size-3" />
            </.link>
          </div>
        </div>

        <%= if @readiness["status"] == "ready" do %>
          <p class="mt-4 text-sm text-success" id="release-readiness-summary">
            {@readiness["summary"]}
          </p>
        <% else %>
          <div class="mt-4" id="release-readiness-reasons">
            <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
              Unmet gate conditions
            </p>
            <ul class="space-y-1 text-sm text-muted-foreground list-disc ml-5">
              <%= for reason <- @readiness["reasons"] do %>
                <li>{reason}</li>
              <% end %>
            </ul>
          </div>
        <% end %>
      <% end %>

      <div class="mt-5 border-t pt-5">
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-3">
          Release evidence
        </p>
        <.form
          for={@form}
          id="release-readiness-form"
          phx-submit="check_release_readiness"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-start"
        >
          <.input
            field={@form[:smoke_status]}
            type="select"
            label="Smoke status"
            options={[{"Not run yet", ""}, {"Passed", "success"}, {"Failed", "failed"}]}
          />
          <.input
            field={@form[:smoke_run]}
            type="text"
            label="Smoke run URL or note"
            placeholder="https://ci.example.com/run/1234"
          />
          <.input
            field={@form[:artifact_source]}
            type="text"
            label="Artifact source"
            placeholder="github-actions"
          />
          <.input
            field={@form[:sha]}
            type="text"
            label="Commit SHA"
            placeholder="release commit (optional)"
          />
          <.input
            field={@form[:provenance_verified]}
            type="checkbox"
            label="Artifact provenance verified"
          />
          <div>
            <.button type="submit" variant="default">
              <.icon name="hero-shield-check" class="size-4" /> Check release readiness
            </.button>
          </div>
        </.form>
      </div>
    </section>
    """
  end

  defp status_badge_class("ready"),
    do:
      "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em] bg-success/15 text-success border-success/30"

  defp status_badge_class("blocked"),
    do:
      "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em] bg-destructive/15 text-destructive border-destructive/30"

  defp status_badge_class(_status),
    do:
      "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em] bg-warning/15 text-warning border-warning/30"

  defp status_label("needs-review"), do: "needs review"
  defp status_label(status) when is_binary(status), do: status
  defp status_label(nil), do: "not checked"
end
