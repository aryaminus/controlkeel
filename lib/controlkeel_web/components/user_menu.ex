defmodule ControlKeelWeb.UserMenu do
  @moduledoc """
  Shared user menu component used by every layout that shows account chrome
  (org sidebar, `/new/*` top bar).

  Two render modes:

  - **Identity** — signed-in user: initial avatar, name/email, and a popover
    with Docs / GitHub / Account. Account opens the account dialog (read-only
    identity info + data export + erasure, see `account_dialog/1`) over
    whatever page is rendered — pure client-side `JS.show`/`JS.hide`, no
    LiveView events, so it works over any layout.
  - **Placeholder** (`placeholder_label`, e.g. `"Local mode"`) — no identity:
    muted avatar with a device icon and the label; the Account entry still
    opens the dialog, but in a restricted variant (local mode has no user
    records and `/me/*` is blocked, so both tabs render a migrate-to-cloud
    notice). No mode checks live in this component; callers decide what to
    pass.
  """

  use ControlKeelWeb, :html

  attr :id, :string, required: true
  attr :current_user, :any, default: nil

  attr :placeholder_label, :string,
    default: nil,
    doc: "when set, renders a no-identity menu with a restricted account dialog"

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

          <%!-- Account opens the account dialog (identity info + data export +
               erasure); no navigation, so it works from any page, in both
               modes — the dialog itself renders the restricted variant when
               `placeholder_label` is set. --%>
          <button
            type="button"
            phx-click={
              JS.hide(to: "##{@id}-popover")
              |> JS.show(to: "##{@id}-account-dialog", display: "block")
            }
            class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            <.icon name="hero-user-circle" class="size-4" /> Account
          </button>
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

      <.account_dialog
        id={"#{@id}-account-dialog"}
        user={@current_user}
        restricted={not is_nil(@placeholder_label)}
      />
    </div>
    """
  end

  @doc """
  Account dialog, opened from the user menu's Account entry.

  Sidebar-over-content layout with two sections so more can slot in later:

  - **Account** — read-only identity info, with the erasure danger zone
    (Art.17) inside it.
  - **Data** — the Art.15 JSON export.

  Section switching is pure client-side `JS.show`/`JS.hide` — no LiveView
  events, so it works over any page's layout. Erasure posts to
  `AccountController.erase/2`; export links to
  `AccountController.export_data/2`. The server re-checks the typed email,
  so this markup is friction, not the boundary.

  When `restricted` is set (local mode's placeholder menu), both sections
  render a migrate-to-cloud notice instead: local mode has no user records
  and `/me/*` is blocked at the plug. `RequireCloudMode` and the controller
  enforce cloud-onlyness server-side regardless.

  Adding a section: append a nav button (unique `*-nav-*` id) and a panel
  (unique `*-panel-*` id), and extend each button's toggle chain to show
  its own panel and hide the others.
  """
  attr :id, :string, required: true
  attr :user, :any, required: true
  attr :restricted, :boolean, default: false

  def account_dialog(assigns) do
    assigns = assign(assigns, :erase_form, to_form(%{"confirm_email" => ""}, as: :erase))

    ~H"""
    <div
      id={@id}
      class="hidden relative z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click={JS.hide(to: "##{@id}")}
        aria-label="Close account dialog"
      />

      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <%!-- Fixed-size dialog (42rem × 33rem) that shrinks with the
               viewport on small screens; body columns scroll internally. --%>
          <div class="flex h-[min(33rem,calc(100dvh-2rem))] w-[min(42rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl border bg-card/95 shadow-card">
            <div class="flex shrink-0 items-start justify-between gap-4 border-b border-border/60 px-6 py-4">
              <div>
                <h2 id={"#{@id}-title"} class="text-lg font-semibold text-foreground">
                  Account
                </h2>
                <p class="mt-1 text-sm text-muted-foreground">
                  <%= if @restricted do %>
                    Local mode — account management needs cloud mode.
                  <% else %>
                    Signed in as <strong class="text-foreground">{@user.email}</strong>
                  <% end %>
                </p>
              </div>
              <button
                type="button"
                phx-click={JS.hide(to: "##{@id}")}
                aria-label="Close"
                class="rounded-lg p-1.5 text-muted-foreground transition hover:bg-muted hover:text-foreground"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="grid min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)] sm:grid-cols-[190px_minmax(0,1fr)] sm:grid-rows-1">
              <nav
                aria-label="Account sections"
                class="flex gap-1 overflow-x-auto border-b border-border/60 p-2 sm:min-h-0 sm:flex-col sm:overflow-y-auto sm:border-b-0 sm:border-r sm:p-3"
              >
                <button
                  id={"#{@id}-nav-account"}
                  type="button"
                  aria-current="true"
                  phx-click={
                    JS.set_attribute({"aria-current", "true"}, to: "##{@id}-nav-account")
                    |> JS.remove_attribute("aria-current", to: "##{@id}-nav-data")
                    |> JS.show(to: "##{@id}-panel-account")
                    |> JS.hide(to: "##{@id}-panel-data")
                  }
                  class="flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground aria-[current=true]:bg-primary/10 aria-[current=true]:font-semibold aria-[current=true]:text-primary"
                >
                  <.icon name="hero-user-circle" class="size-4" /> Account
                </button>
                <button
                  id={"#{@id}-nav-data"}
                  type="button"
                  phx-click={
                    JS.set_attribute({"aria-current", "true"}, to: "##{@id}-nav-data")
                    |> JS.remove_attribute("aria-current", to: "##{@id}-nav-account")
                    |> JS.show(to: "##{@id}-panel-data")
                    |> JS.hide(to: "##{@id}-panel-account")
                  }
                  class="flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground aria-[current=true]:bg-primary/10 aria-[current=true]:font-semibold aria-[current=true]:text-primary"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Data
                </button>
              </nav>

              <div class="min-h-0 overflow-y-auto p-6">
                <div
                  id={"#{@id}-panel-account"}
                  role="tabpanel"
                  aria-labelledby={"#{@id}-nav-account"}
                >
                  <%= if @restricted do %>
                    <div class="rounded-2xl border border-border/80 bg-muted/40 p-6 text-center">
                      <.icon
                        name="hero-lock-closed"
                        class="mx-auto size-8 text-muted-foreground/70"
                      />
                      <p class="mt-3 text-sm text-muted-foreground">
                        You need to migrate to cloud mode to use these settings.
                      </p>
                    </div>
                  <% else %>
                    <%!-- Read-only identity: display only, no editing — profile
                         changes belong to the identity provider. --%>
                    <dl class="grid gap-x-8 gap-y-4 sm:grid-cols-[auto_minmax(0,1fr)]">
                      <dt class="text-sm font-medium text-muted-foreground">Email</dt>
                      <dd class="text-sm text-foreground">{@user.email}</dd>
                      <dt class="text-sm font-medium text-muted-foreground">Name</dt>
                      <dd class="text-sm text-foreground">{@user.name || "—"}</dd>
                    </dl>

                    <div class="mt-8 rounded-xl border border-[var(--ck-danger)]/30 bg-[var(--ck-danger)]/5 p-4">
                      <div class="mb-3 flex items-center gap-3">
                        <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--ck-danger)]/15">
                          <.icon
                            name="hero-exclamation-triangle"
                            class="size-4 text-[var(--ck-danger)]"
                          />
                        </span>
                        <.card_title class="text-[var(--ck-danger)]">Danger zone</.card_title>
                      </div>
                      <p class="text-sm text-foreground">
                        <strong>Erasing your account is permanent.</strong> Your
                        account and memberships are deleted immediately. Audit
                        records survive with your identity replaced by a
                        non-reversible marker, and your organizations'
                        governance data is untouched. Service accounts you
                        created are revoked.
                      </p>
                      <p class="mt-2 text-sm text-muted-foreground">
                        If you are the last active owner of an organization,
                        erasure is refused — promote another owner or delete the
                        organization first.
                      </p>

                      <.form
                        id={"#{@id}-erase-form"}
                        for={@erase_form}
                        action={~p"/me/erase"}
                        method="post"
                        class="mt-4"
                      >
                        <.input
                          field={@erase_form[:confirm_email]}
                          label="Type your email to confirm erasure"
                          autocomplete="off"
                        />
                        <div class="mt-3">
                          <button
                            type="submit"
                            id={"#{@id}-erase-button"}
                            class="rounded-full bg-[var(--ck-danger)] px-4 py-2 text-sm font-medium text-white transition hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--ck-danger)]"
                          >
                            Erase my account
                          </button>
                        </div>
                      </.form>
                    </div>
                  <% end %>
                </div>

                <div
                  id={"#{@id}-panel-data"}
                  role="tabpanel"
                  aria-labelledby={"#{@id}-nav-data"}
                  class="hidden"
                >
                  <%= if @restricted do %>
                    <div class="rounded-2xl border border-border/80 bg-muted/40 p-6 text-center">
                      <.icon
                        name="hero-lock-closed"
                        class="mx-auto size-8 text-muted-foreground/70"
                      />
                      <p class="mt-3 text-sm text-muted-foreground">
                        You need to migrate to cloud mode to use these settings.
                      </p>
                    </div>
                  <% else %>
                    <.card_title>Download my data</.card_title>
                    <p class="mt-2 text-sm text-muted-foreground">
                      A JSON export of everything ControlKeel holds about your
                      account: your profile, your organization memberships, and
                      the audit trail that references you.
                    </p>
                    <a
                      href={~p"/me/export.json"}
                      class="mt-4 inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
                    >
                      <.icon name="hero-arrow-down-tray" class="size-4" /> Download JSON
                    </a>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
