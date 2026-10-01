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
          class="inline-flex items-center justify-center gap-[0.4rem] px-[1.25rem] py-[0.95rem] rounded-full bg-primary text-[#11170d] font-bold transition-[transform,box-shadow] duration-[160ms] ease-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          phx-click={@copy_event}
          phx-value-id={@finding.id}
        >
          Copy fix prompt
        </button>
        <button
          :if={@close_event}
          type="button"
          class="uppercase tracking-[0.14em] text-xs text-primary font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded"
          phx-click={@close_event}
        >
          Close
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Inline (non-modal) guided-fix detail for the session findings accordion.
  Same fix payload as `autofix_panel`, lighter chrome: no modal surface,
  tone tokens only, action buttons stay in the host page.
  """
  attr :finding, :map, required: true
  attr :fix, :map, required: true
  attr :copy_event, :string, default: nil

  def finding_fix_detail(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between gap-4">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
          Guided fix
        </p>
        <span class={[
          "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
          @fix["supported"] && "bg-success/10 text-success ring-success/20",
          !@fix["supported"] && "bg-warning/10 text-warning ring-warning/20"
        ]}>
          {if @fix["supported"], do: "supported", else: "manual review"}
        </span>
      </div>

      <p class="text-sm leading-relaxed text-muted-foreground">{@fix["summary"]}</p>

      <div class="grid grid-cols-2 gap-4 max-[900px]:grid-cols-1">
        <div>
          <p class="text-sm font-semibold text-foreground">Why</p>
          <p class="mt-1 text-sm text-muted-foreground">{@fix["why"]}</p>
        </div>
        <div>
          <p class="text-sm font-semibold text-foreground">Requires human</p>
          <p class="mt-1 text-sm text-muted-foreground">
            {if @fix["requires_human"], do: "Yes", else: "No"}
          </p>
        </div>
      </div>

      <div :if={@fix["steps"] != [] && @fix["steps"]}>
        <p class="text-sm font-semibold text-foreground">Steps</p>
        <ol class="mt-2 list-decimal space-y-1.5 pl-5 text-sm text-muted-foreground">
          <%= for step <- @fix["steps"] || [] do %>
            <li class="leading-relaxed">{step}</li>
          <% end %>
        </ol>
      </div>

      <div :if={@fix["example"]}>
        <p class="text-sm font-semibold text-foreground">Example</p>
        <pre class="mt-2 m-0 p-4 border rounded-xl bg-muted/[0.03] whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]"><code>{@fix["example"]}</code></pre>
      </div>

      <div :if={@fix["agent_prompt"]}>
        <p class="text-sm font-semibold text-foreground">Agent prompt</p>
        <pre class="mt-2 m-0 p-4 border rounded-xl bg-muted/[0.03] whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]"><code>{@fix["agent_prompt"]}</code></pre>
        <button
          :if={@copy_event}
          type="button"
          class="mt-3 inline-flex items-center gap-2 rounded-lg border border-border bg-transparent px-4 py-1.5 text-xs font-semibold text-foreground transition cursor-pointer hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
          phx-click={@copy_event}
          phx-value-id={@finding.id}
        >
          Copy fix prompt
        </button>
      </div>
    </div>
    """
  end
end
