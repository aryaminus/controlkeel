defmodule ControlKeelWeb.SessionStartLayouts do
  @moduledoc """
  Standalone framework layout for the session-start onboarding flow
  (`/sessions/start`, Vercel-type wizard).

  Deliberately independent from `ControlKeelWeb.Layouts` and
  `ControlKeelWeb.OrganizationLayouts`: no sidebar, no breadcrumb header,
  no shared chrome — just a minimal top bar, a centered wizard column, and
  flashes. Shared primitives (`<.flash>`, `<.icon>`, `<.link>`) come from
  the `html_helpers` imports, not from the other layout modules.
  """

  use ControlKeelWeb, :html

  embed_templates "session_start_layouts/*"

  @doc """
  Sticky top bar. The left side renders a back button for the onboarding
  wizard (cloud → `/`, local → the default org page). Dashboard-style
  user menu on the right.
  """
  attr :current_user, :any, default: nil

  def topbar(assigns) do
    assigns =
      assigns
      |> assign_new(:mode, fn -> ControlKeel.Runtime.Mode.current() end)
      |> assign_new(:back_path, fn
        %{mode: :local} ->
          "/#{ControlKeel.Bootstrap.LocalDefaults.default_org_slug()}"

        _ ->
          "/"
      end)

    ~H"""
    <header class="sticky top-0 z-50 border-b bg-background/80 backdrop-blur">
      <div class="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-4 sm:px-8">
        <.link
          navigate={@back_path}
          class="inline-flex shrink-0 items-center gap-2 rounded-3xl px-4 py-2 text-sm font-semibold text-muted-foreground transition hover:bg-muted hover:text-foreground"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.link>

        <div class="flex shrink-0 items-center gap-2">
          <ControlKeelWeb.Layouts.user_menu
            :if={@current_user != nil and @mode != :local}
            id="session-start-user-menu"
            current_user={@current_user}
            compact
            show_dashboard
          />
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Vercel-style stepper for the 4-step session wizard.
  Steps: Scope (org/workspace, cloud only) → Domain → Describe → Interview → Review.
  """
  attr :step, :integer, default: 1
  attr :cloud_mode, :boolean, default: false

  def steps(assigns) do
    steps =
      if assigns.cloud_mode do
        ["Scope", "Domain", "Describe", "Interview", "Review"]
      else
        ["Domain", "Describe", "Interview", "Review"]
      end

    # Map wizard step (1-4) to stepper index; cloud mode prepends Scope.
    current_idx =
      if assigns.cloud_mode, do: assigns.step, else: assigns.step - 1

    assigns = assign(assigns, :steps, steps) |> assign(:current_idx, current_idx)

    ~H"""
    <ol class="flex flex-wrap items-center gap-2" aria-label="Progress">
      <%= for {label, idx} <- Enum.with_index(@steps) do %>
        <li class="flex items-center gap-2">
          <span class={[
            "flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-semibold transition",
            idx < @current_idx && "border-primary/30 bg-primary/10 text-primary",
            idx == @current_idx && "border-primary bg-primary text-primary-foreground",
            idx > @current_idx && "border-border bg-muted text-muted-foreground"
          ]}>
            <%= if idx < @current_idx do %>
              <.icon name="hero-check" class="size-3" />
            <% else %>
              <span class="tabular-nums">{idx + 1}</span>
            <% end %>
            {label}
          </span>
          <%= if idx < length(@steps) - 1 do %>
            <span aria-hidden="true" class="text-muted-foreground/50">/</span>
          <% end %>
        </li>
      <% end %>
    </ol>
    """
  end

  @doc """
  Flash list for the standalone layout (mirrors the `Layouts.flash_group`
  contract without depending on that module).
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_list(assigns) do
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
