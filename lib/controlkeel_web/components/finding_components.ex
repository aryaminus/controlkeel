defmodule ControlKeelWeb.FindingComponents do
  use Phoenix.Component

  attr :finding, :map, required: true
  attr :fix, :map, required: true
  attr :copy_event, :string, default: nil
  attr :close_event, :string, default: nil

  def autofix_panel(assigns) do
    ~H"""
    <div class="ck-card ck-fix-panel">
      <div class="ck-finding-head">
        <div>
          <p class="ck-mini-label">Guided fix</p>
          <h3>{@finding.title}</h3>
        </div>
        <span class={[
          "ck-pill",
          @fix["supported"] && "ck-pill-low",
          !@fix["supported"] && "ck-pill-medium"
        ]}>
          {if @fix["supported"], do: "supported", else: "manual review"}
        </span>
      </div>

      <p class="ck-note">{@fix["summary"]}</p>

      <div class="ck-brief-grid">
        <div>
          <h3>Why</h3>
          <p class="ck-note">{@fix["why"]}</p>
        </div>
        <div>
          <h3>Requires human</h3>
          <p class="ck-note">
            {if @fix["requires_human"], do: "Yes", else: "No"}
          </p>
        </div>
      </div>

      <div>
        <h3>Steps</h3>
        <ul class="ck-mini-list">
          <%= for step <- @fix["steps"] || [] do %>
            <li>{step}</li>
          <% end %>
        </ul>
      </div>

      <div :if={@fix["example"]}>
        <h3>Example</h3>
        <pre class="ck-code-block"><code>{@fix["example"]}</code></pre>
      </div>

      <div :if={@fix["agent_prompt"]}>
        <h3>Agent prompt</h3>
        <pre class="ck-code-block"><code>{@fix["agent_prompt"]}</code></pre>
      </div>

      <div class="ck-action-row">
        <button
          :if={@copy_event && @fix["agent_prompt"]}
          type="button"
          class="ck-button-primary"
          phx-click={@copy_event}
          phx-value-id={@finding.id}
        >
          Copy fix prompt
        </button>
        <button :if={@close_event} type="button" class="ck-link" phx-click={@close_event}>
          Close
        </button>
      </div>
    </div>
    """
  end
end
