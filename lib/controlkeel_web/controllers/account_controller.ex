defmodule ControlKeelWeb.AccountController do
  @moduledoc """
  Self-service account endpoints backing the user-menu dialog
  (docs/dsar-erasure-plan.md, Slice 3).

  There is no `/account` page: the framework layouts render an account
  dialog from the user menu on every cloud LiveView, and this controller
  is its backing store:

    * `GET /me/export.json` — serves the GDPR Art.15 export produced by
      `ControlKeel.Accounts.DataLifecycle.export_user_data/1` as a JSON
      download. Scoped to the signed-in caller's own data only.
    * `POST /me/erase` — GDPR Art.17 erasure via `DataLifecycle.delete_user/1`.
      Confirmation is the user's own email, typed exactly; the server
      re-checks the match, so the dialog's check is friction, not the
      boundary. Success clears the browser session (the Slice 2
      `sign_out_everywhere/1` broadcast handles their other LiveViews) and
      redirects to the login screen. Sole-owner refusals land as a flash
      with actionable copy naming the organization(s)
      (`DataLifecycle.sole_owner_orgs/1`).

  Both routes run behind `:require_session_auth` (passthrough in local
  mode), and the user check here is the real gate: local mode has no
  signed-in user, so the feature is cloud-only by construction —
  `RequireCloudMode` additionally blocks `/me/*` in local mode.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts.DataLifecycle

  def export_data(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "sign in required"})

      user ->
        case DataLifecycle.export_user_data(user.id) do
          {:ok, export} ->
            filename = "controlkeel-account-export-#{date_stamp()}.json"

            conn
            |> put_resp_content_type("application/json")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, Jason.encode!(export))

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "not found"})
        end
    end
  end

  def erase(conn, %{"erase" => %{"confirm_email" => text}}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> redirect(to: ~p"/auth/login")

      user ->
        if String.trim(text) == user.email do
          run_erasure(conn, user)
        else
          refused(conn, "Type your email exactly to confirm deletion.")
        end
    end
  end

  def erase(conn, _params), do: refused(conn, "Type your email exactly to confirm deletion.")

  # Erasure succeeded: the Slice 2 post-commit work (sign_out_everywhere
  # broadcast + membership revocations) already fired inside delete_user/1;
  # clear this browser's session and land on the login screen.
  defp run_erasure(conn, user) do
    case DataLifecycle.delete_user(user.id) do
      {:ok, _stats} ->
        conn
        |> delete_session(:current_user_id)
        |> delete_session(:session_last_active)
        |> put_flash(:info, "Your account has been deleted.")
        |> redirect(to: ~p"/auth/login")

      {:error, :sole_owner} ->
        refused(conn, sole_owner_copy(user.id))

      {:error, _reason} ->
        refused(conn, "Deletion failed. Please try again or contact support.")
    end
  end

  defp refused(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end

  defp sole_owner_copy(user_id) do
    names = DataLifecycle.sole_owner_orgs(user_id) |> Enum.map(& &1.name)

    org_list =
      case names do
        [only] -> only
        list -> Enum.join(list, ", ")
      end

    "You are the last active owner of #{org_list}. " <>
      "Promote another owner in the organization's Members settings, " <>
      "or delete the organization first."
  end

  defp date_stamp, do: DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601()
end
