defmodule ControlKeelWeb.AuthLive do
  @moduledoc """
  Sign-in page with OAuth provider buttons.

  Providers are read from `ControlKeel.Accounts.oauth_configured_providers/0`,
  which reflects `Application.get_env(:controlkeel, :oauth_providers)`. The page
  renders one button per configured provider, so it works in local mode (no
  providers → empty state) and cloud mode (Google + GitHub) without changes.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(_params, _session, socket) do
    providers =
      Accounts.oauth_configured_providers()
      |> Enum.map(fn provider ->
        {provider, provider_label(provider), provider_icon(provider)}
      end)

    {:ok, assign(socket, page_title: "Sign in", providers: providers)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="ck-shell" style="max-width: 480px; margin: 4rem auto;">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <div class="mb-8">
        <.link
          href={~p"/"}
          class="inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-lime-300 transition"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Home
        </.link>
      </div>

      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">ControlKeel Cloud</p>
          <h1 class="ck-section-title">Sign in</h1>
        </div>
      </div>

      <div class="mt-8 flex flex-col gap-3">
        <%= for {provider, label, icon} <- @providers do %>
          <.link
            href={~p"/auth/#{provider}/request"}
            class="flex items-center justify-center gap-3 rounded-lg border border-white/10 bg-zinc-900 px-4 py-3 text-sm font-medium text-zinc-200 transition hover:border-lime-300/30 hover:bg-zinc-800"
          >
            <.icon name={icon} class="size-5" />
            {label}
          </.link>
        <% end %>

        <%= if @providers == [] do %>
          <div class="rounded-lg border border-white/10 bg-zinc-900 px-4 py-6 text-center">
            <p class="text-sm text-zinc-300">No sign-in providers are configured.</p>
            <p class="mt-1 text-xs text-zinc-500">
              Set Google or GitHub OAuth credentials to enable sign-in.
            </p>
          </div>
        <% end %>
      </div>

      <%= if @providers != [] do %>
        <p class="mt-8 text-center text-xs text-zinc-600">
          No passwords. Sign in with a provider below.
        </p>
      <% end %>
    </section>
    """
  end

  defp provider_label(:google), do: "Sign in with Google"
  defp provider_label(:github), do: "Sign in with GitHub"
  defp provider_label(other), do: "Sign in with #{String.capitalize(to_string(other))}"

  defp provider_icon(:google), do: "hero-globe-alt"
  defp provider_icon(:github), do: "hero-code-bracket"
  defp provider_icon(_), do: "hero-key"
end
