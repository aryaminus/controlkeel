defmodule ControlKeelWeb.InvitationLive do
  @moduledoc """
  Invitation-acceptance page at `/invitations/:token`.

  Renders the org name and role for the invitee. Acceptance requires OAuth
  authentication — the invite token proves *what* the user gets access to
  (org + role); OAuth proves *who they are* (email ownership via Google/GitHub).

  ## Flow

  1. Unauthenticated visitor opens the link → sees invitation details + OAuth
     sign-in buttons.
  2. User signs in via Google/GitHub → OAuth callback redirects back to this
     page with an active session.
  3. Authenticated user whose email matches the invitation → sees "Accept"
     button.
  4. Authenticated user whose email does NOT match → sees an error.

  When the invitation has already been accepted or the token is invalid the
  page renders a clean error state.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(%{"token" => token}, session, socket) do
    socket = assign(socket, :page_title, "Invitation")
    current_user = current_user_from_session(session)

    case Accounts.lookup_invitation(token) do
      {:ok, %{membership: membership, org: org, user: invited_user}} ->
        {:ok,
         socket
         |> assign(:state, :ready)
         |> assign(:token, token)
         |> assign(:org, org)
         |> assign(:membership, membership)
         |> assign(:invited_user, invited_user)
         |> assign(:current_user, current_user)
         |> assign(:email_matches, email_matches?(current_user, invited_user))}

      {:error, :already_accepted} ->
        {:ok, assign(socket, :state, :already_accepted) |> assign(:current_user, current_user)}

      {:error, :invalid_token} ->
        {:ok, assign(socket, :state, :invalid) |> assign(:current_user, current_user)}
    end
  end

  @impl true
  def handle_event("accept", _params, socket) do
    if socket.assigns[:current_user] && socket.assigns[:email_matches] &&
         socket.assigns.state == :ready do
      case Accounts.accept_invitation(socket.assigns.token, socket.assigns.current_user.id) do
        {:ok, _membership} ->
          {:noreply, redirect(socket, to: ~p"/#{socket.assigns.org.slug}")}

        {:error, :invalid_token} ->
          {:noreply, assign(socket, :state, :invalid)}

        {:error, :already_accepted} ->
          {:noreply, assign(socket, :state, :already_accepted)}

        {:error, _reason} ->
          {:noreply, assign(socket, :state, :error)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(%{state: :ready} = assigns) do
    ~H"""
    <div class="min-h-screen bg-background text-foreground">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute left-1/2 top-8 h-80 w-80 -translate-x-1/2 rounded-full bg-primary/10 blur-3xl" />
      </div>

      <section class="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <%= if !(@current_user && !@email_matches) do %>
          <div class="mb-8 text-center">
            <p class="mb-2 text-xs font-semibold uppercase tracking-[0.32em] text-primary">
              Invitation
            </p>
            <h1 class="text-3xl font-semibold tracking-tight text-foreground">Join {@org.name}</h1>
            <p class="mt-3 text-sm text-muted-foreground">
              You've been invited as
              <span class="font-semibold text-primary">{@membership.role}</span>
            </p>
          </div>
        <% end %>

        <div class="overflow-hidden rounded-[2rem] border bg-card/95 p-8 shadow-[0_45px_120px_-40px_rgba(0,0,0,0.9)]">
          <%= cond do %>
            <% @current_user && @email_matches -> %>
              <div class="mb-6 flex items-center gap-3 rounded-2xl border bg-muted p-4">
                <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-[var(--ck-success)]/15">
                  <.icon name="hero-check-circle" class="size-5 text-[var(--ck-success)]" />
                </span>
                <div class="min-w-0">
                  <p class="text-sm font-medium text-foreground">Signed in</p>
                  <p class="truncate text-sm text-muted-foreground">{@current_user.email}</p>
                </div>
              </div>
              <button
                type="button"
                phx-click="accept"
                class="flex w-full items-center justify-center gap-2 rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
              >
                <.icon name="hero-check" class="size-5" /> Accept invitation
              </button>
              <a
                href={~p"/dashboard"}
                class="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Back to dashboard
              </a>
            <% @current_user && !@email_matches -> %>
              <div class="mb-6 flex items-center gap-3 rounded-2xl border border-destructive/20 bg-destructive/5 p-4">
                <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-destructive/15">
                  <.icon name="hero-exclamation-triangle" class="size-5 text-destructive" />
                </span>
                <div class="min-w-0">
                  <p class="text-sm font-medium text-foreground">Email mismatch</p>
                  <p class="mt-0.5 text-sm text-muted-foreground">
                    Invite sent to <code class="text-primary">{@invited_user.email}</code>
                  </p>
                  <p class="text-sm text-muted-foreground">
                    You're signed in as <code class="text-destructive">{@current_user.email}</code>
                  </p>
                </div>
              </div>
              <div class="mt-4 flex gap-3">
                <a
                  href={~p"/dashboard"}
                  class="flex flex-1 items-center justify-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
                >
                  <.icon name="hero-arrow-left" class="size-4" /> Dashboard
                </a>
                <a
                  href={~p"/auth/logout"}
                  class="flex flex-1 items-center justify-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
                </a>
              </div>
            <% true -> %>
              <div class="mb-6 rounded-2xl border bg-muted p-4 text-center">
                <p class="text-sm text-muted-foreground">
                  This invitation was issued to
                </p>
                <p class="mt-1 font-mono text-sm text-primary">{@invited_user.email}</p>
              </div>

              <div class="mb-6 flex items-center gap-3">
                <div class="h-px flex-1 bg-muted" />
                <span class="text-[11px] uppercase tracking-[0.28em] text-muted-foreground">
                  Sign in to accept
                </span>
                <div class="h-px flex-1 bg-muted" />
              </div>

              <div class="grid gap-3">
                <a
                  href={~p"/auth/invitation/#{@token}?provider=google"}
                  class="group flex items-center justify-center gap-3 rounded-2xl border bg-muted px-5 py-3.5 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-1 hover:bg-muted hover:border-primary"
                >
                  <span class="inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-muted">
                    <svg class="size-5" viewBox="0 0 24 24" aria-hidden="true">
                      <path
                        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"
                        fill="#4285F4"
                      />
                      <path
                        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                        fill="#34A853"
                      />
                      <path
                        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                        fill="#FBBC05"
                      />
                      <path
                        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                        fill="#EA4335"
                      />
                    </svg>
                  </span>
                  Continue with Google
                </a>

                <a
                  href={~p"/auth/invitation/#{@token}?provider=github"}
                  class="group flex items-center justify-center gap-3 rounded-2xl border bg-muted px-5 py-3.5 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-1 hover:bg-muted hover:border-primary"
                >
                  <span class="inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-muted">
                    <svg class="size-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                    </svg>
                  </span>
                  Continue with GitHub
                </a>
              </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  def render(%{state: :already_accepted} = assigns) do
    ~H"""
    <div class="min-h-screen bg-background text-foreground">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute left-1/2 top-8 h-80 w-80 -translate-x-1/2 rounded-full bg-primary/10 blur-3xl" />
      </div>

      <section class="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <div class="overflow-hidden rounded-[2rem] border bg-card/95 p-8 text-center shadow-[0_45px_120px_-40px_rgba(0,0,0,0.9)]">
          <div class="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-3xl border bg-muted">
            <.icon name="hero-check-badge" class="size-7 text-muted-foreground" />
          </div>
          <h1 class="text-2xl font-semibold tracking-tight text-foreground">Already accepted</h1>
          <p class="mt-3 text-sm text-muted-foreground">
            This invitation has already been used. If you didn't accept it, contact the org owner.
          </p>
          <a
            href={if @current_user, do: ~p"/dashboard", else: ~p"/"}
            class="mt-6 inline-flex items-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {if @current_user, do: "Back to dashboard", else: "Back to home"}
          </a>
        </div>
      </section>
    </div>
    """
  end

  def render(%{state: :invalid} = assigns) do
    ~H"""
    <div class="min-h-screen bg-background text-foreground">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute left-1/2 top-8 h-80 w-80 -translate-x-1/2 rounded-full bg-destructive/10 blur-3xl" />
      </div>

      <section class="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <div class="overflow-hidden rounded-[2rem] border bg-card/95 p-8 text-center shadow-[0_45px_120px_-40px_rgba(0,0,0,0.9)]">
          <div class="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-3xl border bg-muted">
            <.icon name="hero-x-circle" class="size-7 text-destructive" />
          </div>
          <h1 class="text-2xl font-semibold tracking-tight text-foreground">Invitation not found</h1>
          <p class="mt-3 text-sm text-muted-foreground">
            This invitation link is no longer valid. Ask the org owner to issue a new invitation.
          </p>
          <a
            href={if @current_user, do: ~p"/dashboard", else: ~p"/"}
            class="mt-6 inline-flex items-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {if @current_user, do: "Back to dashboard", else: "Back to home"}
          </a>
        </div>
      </section>
    </div>
    """
  end

  def render(%{state: :error} = assigns) do
    ~H"""
    <div class="min-h-screen bg-background text-foreground">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute left-1/2 top-8 h-80 w-80 -translate-x-1/2 rounded-full bg-destructive/10 blur-3xl" />
      </div>

      <section class="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <div class="overflow-hidden rounded-[2rem] border bg-card/95 p-8 text-center shadow-[0_45px_120px_-40px_rgba(0,0,0,0.9)]">
          <div class="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-3xl border bg-muted">
            <.icon name="hero-exclamation-triangle" class="size-7 text-destructive" />
          </div>
          <h1 class="text-2xl font-semibold tracking-tight text-foreground">Something went wrong</h1>
          <p class="mt-3 text-sm text-muted-foreground">
            Could not accept the invitation. Please try again or contact the org owner.
          </p>
          <a
            href={if @current_user, do: ~p"/dashboard", else: ~p"/"}
            class="mt-6 inline-flex items-center gap-2 rounded-2xl border bg-muted px-5 py-3 text-sm font-semibold text-foreground transition duration-200 hover:-translate-y-0.5 hover:bg-muted"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {if @current_user, do: "Back to dashboard", else: "Back to home"}
          </a>
        </div>
      </section>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp current_user_from_session(session) do
    user_id = Map.get(session, "current_user_id") || Map.get(session, :current_user_id)

    if is_integer(user_id) do
      Accounts.get_user(user_id)
    end
  end

  defp email_matches?(nil, _invited_user), do: false

  defp email_matches?(current_user, invited_user) do
    normalize_email(current_user.email) == normalize_email(invited_user.email)
  end

  defp normalize_email(email) do
    email |> to_string() |> String.downcase() |> String.trim()
  end
end
