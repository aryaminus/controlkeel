defmodule ControlKeelWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hooks for authentication and org context loading.

  Two hooks:

    * `:require_cloud_auth` — in cloud/self_hosted mode requires a signed-in
      user (`current_user`) **with at least one active membership**; users
      without any membership are redirected to `/new/org` instead of
      proceeding with effectively global read access. The standalone
      `/new/org` creation page and `/new/session` are exempt so membership-less
      users can create an org and see why starting a session needs one
      (issue #141, R3; creation lives at `/new/org` since #277). Signup
      auto-provisions a personal org (`OAuthLoginController`), so the
      membership-less branch is a safety net for pre-existing rows, not a
      reachable flow. In local mode this is a passthrough so local single-user
      deployments are unaffected.

    * `:load_if_available` — loads the user from session without gating.
      Use for pages that are public in local mode but show org-scoped data when
      a membership is present (e.g. home page).

  Both hooks assign:
    * `:current_user`        — `%Accounts.User{}` or `nil`
    * `:session_last_active` — `DateTime` or `nil`

  Org context is not ambient. Org-scoped pages resolve the org and the
  visitor's membership from the URL slug (`ControlKeelWeb.OrgAccess`);
  workspace-scoped pages resolve authority from `(user, workspace.org_id)`
  (`ControlKeelWeb.WorkspaceAccess`). Pages that need a membership for their
  own org keep it in a page-local assign.
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

        # `/new/org` and `/new/session` remain available to membership-less
        # users: creation happens at `/new/org`, and the launcher explains
        # why starting a session still needs an org.
        # Every other authenticated page requires membership. Signup
        # auto-provisioning makes this branch unreachable for new users; it
        # remains a safety net for pre-existing rows.
        socket.view in [
          ControlKeelWeb.NewOrgLive,
          ControlKeelWeb.NewSessionLive
        ] ->
          {:cont, attach_membership_eviction(socket)}

        not Accounts.any_active_membership?(socket.assigns.current_user.id) ->
          {:halt,
           socket
           |> put_flash(:info, "Join or create an organization to continue.")
           |> redirect(to: "/new/org")}

        true ->
          {:cont, attach_membership_eviction(socket)}
      end
    end
  end

  @doc false
  def on_mount(:load_if_available, _params, session, socket) do
    {:cont, load_auth(socket, session)}
  end

  # ── Real-time membership changes ─────────────────────────────────
  #
  # When a membership is revoked or its role changes, Accounts broadcasts
  # `{:membership_changed, %Membership{}}` on `membership:user:<id>`. We
  # subscribe per-socket here and attach a `:handle_info` hook so every
  # cloud-mode LiveView reacts uniformly. The hook returns `{:halt, socket}`
  # so subsequent application handlers don't fire after the redirect is queued.
  #
  # There is no ambient "current org": each page resolves its own org from the
  # URL and keeps the membership in a page-local `:current_membership` assign.
  # A revocation of that membership sends the visitor to `/new/org` — the
  # available organization setup surface — so the next page's own
  # access check decides what they may see. A role change refreshes the assign
  # so pages that derive permissions from it re-render in place. Changes to
  # other orgs are ignored; this page is unaffected. We do not sign the user
  # out: a revocation from one org must not end a session that still has
  # access to another.

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
         {:membership_changed, %{user_id: uid, org_id: org_id} = change},
         %{assigns: %{current_user: %{id: uid}}} = socket
       ) do
    case socket.assigns[:current_membership] do
      %Accounts.Membership{org_id: ^org_id} ->
        if Map.get(change, :status) == "revoked" do
          # The page's own membership is gone. Leave the page and let the next
          # page's access check decide what the visitor may see.
          {:halt,
           socket
           |> put_flash(:info, "Your access to this organization changed.")
           |> push_navigate(to: "/new/org")}
        else
          # Role change: refresh the page-local membership in place so pages
          # that derive permissions from it re-render without a reload.
          {:halt, assign(socket, :current_membership, change)}
        end

      _ ->
        # This page did not resolve a membership for this org, so there is
        # nothing page-specific to invalidate. A revocation may still have
        # removed the user's last membership; in that case no authenticated
        # page is valid anymore, so send them to /new/org rather than a login
        # screen. Role changes and changes in other orgs need no action here.
        if Map.get(change, :status) == "revoked" and
             not Accounts.any_active_membership?(uid) do
          {:halt,
           socket
           |> put_flash(:info, "You no longer have access to any organization.")
           |> push_navigate(to: "/new/org")}
        else
          {:halt, socket}
        end
    end
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
    # Prefer the user already put in socket.assigns by LoadCurrentUser
    # (set during the initial HTTP request). Fall back to session for
    # WebSocket reconnects and direct WS connections.
    user_id =
      (socket.assigns[:current_user] && socket.assigns.current_user.id) ||
        Map.get(session, "current_user_id") ||
        Map.get(session, :current_user_id)

    user = if is_integer(user_id), do: Accounts.get_user(user_id)

    # Session idle timeout — check last_active timestamp from session.
    # When idle exceeds the configured threshold, redirect to login.
    # A timeout of 0 (default) disables the idle check entirely.
    last_active =
      Map.get(session, "session_last_active") ||
        Map.get(session, :session_last_active)

    socket =
      socket
      |> assign(:current_user, user)
      |> assign(:session_last_active, parse_timestamp(last_active))

    check_session_idle(socket)
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
