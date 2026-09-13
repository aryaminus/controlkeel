defmodule ControlKeelWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hooks for authentication and org context loading.

  Two hooks:

    * `:require_cloud_auth` — in cloud/self_hosted mode requires a signed-in
      user (`current_user`) **with at least one active membership**; users
      without any membership are redirected to `/organizations` (the
      onboarding surface, which is exempt so they can join or create an
      org) instead of proceeding with effectively global read access
      (issue #141, R3). In local mode this is a passthrough so local
      single-user deployments are unaffected.

    * `:load_if_available` — loads user/membership from session without gating.
      Use for pages that are public in local mode but show org-scoped data when
      a membership is present (e.g. home page).

  Both hooks assign:
    * `:current_user`       — `%Accounts.User{}` or `nil`
    * `:current_org_id`     — integer org id or `nil`
    * `:current_membership` — `%Accounts.Membership{}` or `nil`

  These override whatever the LoadCurrentUser plug may have already put in
  socket.assigns (they carry the same values from the same source).
  """

  import Phoenix.LiveView,
    only: [redirect: 2, attach_hook: 4, put_flash: 3, push_navigate: 2, connected?: 1]

  import Phoenix.Component, only: [assign: 3]

  alias ControlKeel.{Accounts, Runtime.Mode}

  @doc false
  def on_mount(:require_cloud_auth, _params, session, socket) do
    mode = Mode.current()

    if mode == :local do
      {:cont, load_auth(socket, session)}
    else
      socket = load_auth(socket, session)

      cond do
        is_nil(socket.assigns[:current_user]) ->
          {:halt, redirect(socket, to: "/auth/login")}

        # `/organizations` is the onboarding surface (org list + create +
        # invite acceptance): a membership-less user is allowed there so they
        # can join or create an org. Everywhere else requires membership.
        socket.view == ControlKeelWeb.OrganizationsLive ->
          {:cont, attach_membership_eviction(socket)}

        not Accounts.any_active_membership?(socket.assigns.current_user.id) ->
          {:halt,
           socket
           |> put_flash(:info, "Join or create an organization to continue.")
           |> redirect(to: "/organizations")}

        true ->
          {:cont, attach_membership_eviction(socket)}
      end
    end
  end

  @doc false
  def on_mount(:load_if_available, _params, session, socket) do
    {:cont, load_auth(socket, session)}
  end

  # ── Real-time membership eviction ─────────────────────────────────
  #
  # When an org owner revokes or demotes a membership, Accounts broadcasts
  # `{:membership_changed, %Membership{}}` on `membership:user:<id>`. We
  # subscribe per-socket here and attach a `:handle_info` hook so every
  # cloud-mode LiveView reacts uniformly. The hook returns `{:halt, socket}`
  # so subsequent application handlers don't fire after the redirect is queued.

  defp attach_membership_eviction(socket) do
    if connected?(socket) and socket.assigns[:current_user] do
      uid = socket.assigns.current_user.id

      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.membership_topic(uid))
      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.signout_topic(uid))

      attach_hook(socket, :ck_membership_eviction, :handle_info, &handle_membership_event/2)
    else
      socket
    end
  end

  defp handle_membership_event(
         {:membership_changed, %{user_id: uid, status: "revoked"}},
         %{assigns: %{current_user: %{id: uid}}} = socket
       ) do
    {:halt,
     socket
     |> put_flash(:error, "Your access has changed. Please sign in again.")
     |> push_navigate(to: "/auth/login")}
  end

  defp handle_membership_event(
         {:membership_changed, %{user_id: uid, org_id: org_id}},
         %{assigns: %{current_user: %{id: uid}, current_org_id: org_id}} = socket
       ) do
    # Role changed but the membership is still active (revocation is handled
    # by the clause above): refresh the socket's membership in place so the
    # assigns never carry a stale elevated role, and let the page rebind its
    # own permission-derived UI without bouncing to login. Falls back to
    # re-login if the membership is gone entirely.
    case Accounts.get_active_membership(uid, org_id) do
      %Accounts.Membership{} = membership ->
        {:halt, assign(socket, :current_membership, membership)}

      _ ->
        {:halt,
         socket
         |> put_flash(:info, "Your access has changed. Please sign in again.")
         |> push_navigate(to: "/auth/login")}
    end
  end

  defp handle_membership_event(
         {:membership_changed, %{user_id: uid, org_id: _org_id}},
         %{assigns: %{current_user: %{id: uid}}} = socket
       ) do
    # Cross-org event: irrelevant to this socket, and no LiveView handles
    # {:membership_changed, ...} directly (this hook is the sole consumer),
    # so consume it here. Returning :cont would leak the message into the
    # module's handle_info/2, which crashes views that define no clause for
    # it (e.g. CloudProjectsLive only handles :refresh).
    {:halt, socket}
  end

  defp handle_membership_event(:sign_out_everywhere, %{assigns: %{current_user: _user}} = socket) do
    {:halt,
     socket
     |> put_flash(:info, "You have been signed out from all sessions.")
     |> push_navigate(to: "/auth/login")}
  end

  defp handle_membership_event(_msg, socket), do: {:cont, socket}

  # --- Private ---

  defp load_auth(socket, session) do
    # Prefer values already put in socket.assigns by LoadCurrentUser plug
    # (set during initial HTTP request). Fall back to session map for WebSocket
    # reconnects and direct WS connections.
    case socket.assigns[:current_membership] do
      %Accounts.Membership{} ->
        socket

      _ ->
        user_id =
          (socket.assigns[:current_user] && socket.assigns.current_user.id) ||
            Map.get(session, "current_user_id") ||
            Map.get(session, :current_user_id)

        org_id =
          socket.assigns[:current_org_id] ||
            Map.get(session, "current_org_id") ||
            Map.get(session, :current_org_id)

        user = if is_integer(user_id), do: Accounts.get_user(user_id)

        # Production never writes current_org_id (issue #141): when the
        # session carries no org, derive the default (first active
        # membership) so org-scoped consumers have a real value. This is a
        # default hint only — access decisions resolve (user, resource).
        org_id =
          if is_nil(org_id) && user,
            do: Accounts.default_org_for_user(user.id),
            else: org_id

        membership =
          if user && is_integer(org_id),
            do: Accounts.get_active_membership(user.id, org_id)

        # Session idle timeout — check last_active timestamp from session.
        # When idle exceeds the configured threshold, redirect to login.
        # A timeout of 0 (default) disables the idle check entirely.
        last_active =
          Map.get(session, "session_last_active") ||
            Map.get(session, :session_last_active)

        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_org_id, org_id)
          |> assign(:current_membership, membership)
          |> assign(:session_last_active, parse_timestamp(last_active))

        check_session_idle(socket)
    end
  end

  # ── Session idle timeout ──────────────────────────────────────────

  defp check_session_idle(%{assigns: %{current_user: nil}} = socket), do: socket

  defp check_session_idle(socket) do
    timeout = session_idle_timeout()

    if timeout > 0 do
      last = socket.assigns[:session_last_active] || DateTime.utc_now()
      diff = DateTime.diff(DateTime.utc_now(), last, :second)

      if diff > timeout do
        socket
        |> put_flash(:info, "Session expired. Please sign in again.")
        |> push_navigate(to: "/auth/login")
      else
        socket
      end
    else
      socket
    end
  end

  defp session_idle_timeout do
    case System.get_env("SESSION_IDLE_TIMEOUT_SECONDS", "0") do
      "" -> 0
      s -> String.to_integer(s)
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_timestamp(other), do: other
end
