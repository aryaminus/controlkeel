defmodule ControlKeelWeb.Layouts do
  @moduledoc """
  App layout templates, embedded via `embed_templates "layouts/*"`.

  - `:root` — the HTML skeleton (doctype/head/body), set via `put_root_layout`
    in the browser pipeline.
  - `:public` — marketing chrome (header/footer) for public pages, set per
    controller via `plug :put_layout` (see `PageController`).

  Framework layouts share the page's render context, so assigns like
  `@current_user`, `@flash`, and `@inner_content` are available here without
  any forwarding from callers.
  """

  use ControlKeelWeb, :html

  embed_templates "layouts/*"

  # Keyboard focus visibility for focusable chrome controls. The docs sidebar
  # (`docs.html.heex`) styles its active/inactive links with it.
  @focus_ring "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"

  # Active/inactive link styling for the docs sidebar. Previously shared with
  # the retired global dashboard sidebar; now owned by the docs layout.
  defp sidebar_link_class(true) do
    "group flex items-center gap-3 rounded-xl bg-muted px-3 py-2.5 font-medium text-foreground shadow-sm ring-1 ring-border transition hover:bg-muted #{@focus_ring}"
  end

  defp sidebar_link_class(false) do
    "group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground #{@focus_ring}"
  end

  attr :id, :string, required: true
  attr :current_user, :any, required: true
  attr :compact, :boolean, default: false
  attr :class, :string, default: ""
  attr :popover_class, :string, default: "right-0 top-full mt-2"
  attr :rest, :global

  def user_menu(assigns) do
    ~H"""
    <div {@rest} class={"relative #{@class}"} id={@id}>
      <button
        type="button"
        phx-click={
          JS.toggle(to: "##{@id}-popover")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-haspopup="menu"
        aria-expanded="false"
        aria-label="User menu"
        class={[
          "transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded",
          if(@compact,
            do:
              "flex items-center gap-2 rounded-full px-1 py-1 text-sm font-semibold text-muted-foreground hover:text-foreground",
            else: "flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left"
          )
        ]}
      >
        <span class={[
          "flex shrink-0 items-center justify-center rounded-full bg-primary/20 font-semibold text-primary",
          if(@compact, do: "size-8", else: "size-8 text-sm ring-1 ring-primary/30")
        ]}>
          {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
        </span>
        <%= unless @compact do %>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-foreground">
              {@current_user.name || @current_user.email}
            </span>
          </span>
          <.icon name="hero-chevron-down" class="size-4 shrink-0 text-muted-foreground" />
        <% end %>
      </button>
      <div
        id={"#{@id}-popover"}
        phx-click-away={
          JS.hide(to: "##{@id}-popover")
          |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id} button")
        }
        class={"hidden absolute #{@popover_class} z-50 w-56 rounded-xl border bg-card p-3 shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <p class="text-sm font-semibold text-foreground">
          {@current_user.name || @current_user.email}
        </p>
        <p class="mt-0.5 text-xs text-muted-foreground">{@current_user.email}</p>
        <div class="my-2 border-t"></div>
        <%!-- TODO: Settings button disabled — it was a no-op that only closed the
             popover. Re-enable and wire to a user settings modal/dialog when functional.
        <button
          type="button"
          phx-click={JS.hide(to: "##{@id}-popover")}
          class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
        </button>
         <hr class="my-2 border-t" />
        --%>
        <a
          href={~p"/auth/logout"}
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-[var(--ck-danger)]"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
