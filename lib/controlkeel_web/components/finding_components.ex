defmodule ControlKeelWeb.FindingComponents do
  use Phoenix.Component

  attr :finding, :map, required: true
  attr :fix, :map, required: true
  attr :copy_event, :string, default: nil
  attr :close_event, :string, default: nil

  def autofix_panel(assigns) do
    ~H"""
    <div class="border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 grid gap-4">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Guided fix
          </p>
          <h3>{@finding.title}</h3>
        </div>
        <span class={[
          "border bg-muted rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem]",
          @fix["supported"] && "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]",
          !@fix["supported"] && "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
        ]}>
          {if @fix["supported"], do: "supported", else: "manual review"}
        </span>
      </div>

      <p class="text-muted-foreground">{@fix["summary"]}</p>

      <div class="grid grid-cols-2 gap-4 max-[900px]:grid-cols-1">
        <div>
          <h3>Why</h3>
          <p class="text-muted-foreground">{@fix["why"]}</p>
        </div>
        <div>
          <h3>Requires human</h3>
          <p class="text-muted-foreground">
            {if @fix["requires_human"], do: "Yes", else: "No"}
          </p>
        </div>
      </div>

      <div>
        <h3>Steps</h3>
        <ul class="grid gap-4 m-0 p-0 list-none">
          <%= for step <- @fix["steps"] || [] do %>
            <li>{step}</li>
          <% end %>
        </ul>
      </div>

      <div :if={@fix["example"]}>
        <h3>Example</h3>
        <pre class="m-0 p-4 border rounded-xl bg-muted/[0.03] whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]"><code>{@fix["example"]}</code></pre>
      </div>

      <div :if={@fix["agent_prompt"]}>
        <h3>Agent prompt</h3>
        <pre class="m-0 p-4 border rounded-xl bg-muted/[0.03] whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]"><code>{@fix["agent_prompt"]}</code></pre>
      </div>

      <div class="flex items-center justify-between gap-4">
        <button
          :if={@copy_event && @fix["agent_prompt"]}
          type="button"
          class="inline-flex items-center justify-center gap-[0.4rem] px-[1.25rem] py-[0.95rem] rounded-full bg-primary text-[#11170d] font-bold transition-[transform,box-shadow] duration-[160ms] ease-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
          phx-click={@copy_event}
          phx-value-id={@finding.id}
        >
          Copy fix prompt
        </button>
        <button
          :if={@close_event}
          type="button"
          class="uppercase tracking-[0.14em] text-xs text-primary font-semibold hover:opacity-80 transition-opacity cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
          phx-click={@close_event}
        >
          Close
        </button>
      </div>
    </div>
    """
  end
end
