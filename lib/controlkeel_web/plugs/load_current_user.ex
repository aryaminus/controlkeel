defmodule ControlKeelWeb.Plugs.LoadCurrentUser do
  @moduledoc """
  Loads the signed-in user from the browser session.

  Org context is URL-owned. Org-scoped pages resolve the org (and the
  visitor's membership in it) from the `:org_slug` in the path via
  `ControlKeelWeb.OrgAccess`; workspace-scoped pages resolve authority from
  `(user, workspace.org_id)` via `ControlKeelWeb.WorkspaceAccess`. Nothing
  about a "current org" is stored in the session, so ambient state can never
  influence an access decision or drift out of sync with the URL.
  """

  import Plug.Conn

  import Phoenix.Controller, only: [put_flash: 3]

  alias ControlKeel.Accounts

  # Shared with the OAuthLoginController's login-refusal copy: the same
  # explanation a re-attempted sign-in would give, shown when a live session
  # is cut by an offboarding.
  @account_disabled_message "This account has been disabled. Contact your administrator."

  def init(opts), do: opts

  def call(conn, _opts) do
    if session_expired?(conn) do
      conn
      |> delete_session(:current_user_id)
      |> delete_session(:session_last_active)
      |> assign(:current_user, nil)
    else
      user_id = get_session(conn, :current_user_id)

      case load_user(user_id) do
        {:ok, user} ->
          conn
          |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
          |> assign(:current_user, user)

        # A disabled account loses access immediately, even mid-session:
        # loading the user is the single point every authenticated surface
        # flows through. The session keys are cleared so re-enabling the
        # account cannot silently restore the old session, and the logout is
        # explained on the next login render (fetch_live_flash has already
        # run in the :browser pipeline, so a redirect persists the flash).
        {:error, :account_disabled} ->
          conn
          |> delete_session(:current_user_id)
          |> delete_session(:session_last_active)
          |> assign(:current_user, nil)
          |> put_flash(:error, @account_disabled_message)

        # Unknown/deleted user (e.g. after erasure): drop the stale session
        # quietly — a missing account is not a disabled one.
        {:error, :not_found} ->
          conn
          |> delete_session(:current_user_id)
          |> delete_session(:session_last_active)
          |> assign(:current_user, nil)
      end
    end
  end

  defp load_user(user_id) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      %Accounts.User{} = user ->
        if Accounts.user_active?(user), do: {:ok, user}, else: {:error, :account_disabled}

      _ ->
        {:error, :not_found}
    end
  end

  defp load_user(_user_id), do: {:error, :not_found}

  defp session_expired?(conn) do
    timeout = session_idle_timeout()

    if timeout > 0 do
      case get_session(conn, :session_last_active) do
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, last_active, _offset} ->
              DateTime.diff(DateTime.utc_now(), last_active, :second) > timeout

            _ ->
              false
          end

        _ ->
          false
      end
    else
      false
    end
  end

  defp session_idle_timeout do
    case System.get_env("SESSION_IDLE_TIMEOUT_SECONDS", "0") do
      "" -> 0
      s -> String.to_integer(s)
    end
  end
end
