defmodule ControlKeelWeb.UserMenu do
  @moduledoc """
  Shared user menu component used by every layout that shows account chrome
  (org sidebar, `/new/*` top bar).

  Two render modes:

  - **Identity** — signed-in user: initial avatar, name/email, and a popover
    with Docs / GitHub / Settings (when `org_slug` is given).
  - **Placeholder** (`placeholder_label`, e.g. `"Local mode"`) — no identity:
    muted avatar with a device icon and the label; popover shows just the
    label. No mode checks live in this component; callers decide what to pass.
  """

  use ControlKeelWeb, :html

  attr :id, :string, required: true
  attr :current_user, :any, default: nil

  attr :placeholder_label, :string,
    default: nil,
    doc: "when set, renders a no-identity menu instead of user info"

  attr :org_slug, :string,
    default: nil,
    doc: "org slug for the Settings link (routes to org settings); nil hides the entry"

  attr :sign_out, :boolean,
    default: false,
    doc: "render the Sign out entry (cloud-only surfaces opt in; local mode has no session)"

  attr :class, :string, default: ""
  attr :popover_class, :string, default: "right-0 top-full mt-2"
  attr :rest, :global

  def user_menu(assigns) do
    ~H"""
    <div
      {@rest}
      class={"relative #{@class}"}
      id={@id}
      phx-click-away={
        JS.hide(to: "##{@id}-popover")
        |> JS.set_attribute(
          {"aria-expanded", "false"},
          to: "##{@id} [data-user-menu-trigger]"
        )
      }
    >
      <span
        role="button"
        tabindex="0"
        aria-label="User menu"
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-popover"}
        data-user-menu-trigger
        phx-click={
          JS.toggle(to: "##{@id}-popover")
          |> JS.toggle_attribute(
            {"aria-expanded", "true", "false"},
            to: "##{@id} [data-user-menu-trigger]"
          )
        }
        class={[
          "flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-full text-sm font-semibold ring-1 transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2",
          if(@placeholder_label,
            do: "bg-muted text-muted-foreground ring-border hover:ring-primary/40",
            else:
              "bg-primary/20 text-primary ring-primary/30 hover:bg-primary/30 hover:ring-primary/50"
          )
        ]}
      >
        <%= if @placeholder_label do %>
          <.icon name="hero-computer-desktop" class="size-4" />
        <% else %>
          {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
        <% end %>
      </span>

      <div
        id={"#{@id}-popover"}
        class={"hidden absolute #{@popover_class} z-50 w-56 rounded-xl border bg-card shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <div class="border-b px-4 py-3">
          <%= if @placeholder_label do %>
            <p class="text-sm font-semibold text-foreground">{@placeholder_label}</p>
          <% else %>
            <p class="text-sm font-semibold text-foreground">
              {@current_user.name || @current_user.email}
            </p>
            <p class="mt-0.5 text-xs text-muted-foreground">{@current_user.email}</p>
          <% end %>
        </div>

        <div class="flex flex-col gap-0.5 p-1.5">
          <.link
            href={~p"/docs"}
            target="_blank"
            rel="noopener"
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-book-open" class="size-4" /> Docs
          </.link>

          <a
            href="https://github.com/aryaminus/controlkeel"
            target="_blank"
            rel="noopener"
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-code-bracket" class="size-4" /> GitHub
          </a>

          <%!-- Settings routes to org settings (docs/dsar-erasure-plan.md Slice 3);
               the account surface (Art.15 export + Art.17 erasure) lives there as
               the Account tab. No close-on-click wiring: the popover is torn
               down by the navigation itself. --%>
          <.link
            :if={@org_slug}
            navigate={~p"/#{@org_slug}/settings"}
            class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
          </.link>
        </div>

        <div :if={@sign_out} class="border-t p-1.5">
          <a
            href={~p"/auth/logout"}
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-[var(--ck-danger)]"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
          </a>
        </div>
      </div>
    </div>
    """
  end
end
