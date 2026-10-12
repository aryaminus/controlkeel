defmodule ControlKeelWeb.CloudWorkspaceController do
  @moduledoc """
  Public enrolment endpoint for new workspaces joining the multi-tenant
  control plane.

  Wire protocol:

      POST /cloud/v1/workspaces/register
      Content-Type: application/json

      {
        "workspace_id": "ws_...",
        "algorithm": "ed25519",
        "public_key": "<base64>",
        "name": "my-laptop",          // optional
        "invite_token": "<token>",    // optional — binds workspace to an org
        "proof": {
          "payload":  "<base64url JSON>",
          "signature":"<base64url ed25519>"
        }
      }

  The endpoint is intentionally unauthenticated at the HTTP layer. Trust is
  established by `ControlKeel.Cloud.Enrollment.verify/1` which checks the
  embedded proof-of-possession signature against the supplied public key.

  Responses:

    - `201 Created` on first enrolment
    - `200 OK` on re-enrolment of an existing workspace_id (idempotent)
    - `400 Bad Request` on malformed envelope, missing fields, or unsupported algorithm
    - `401 Unauthorized` on proof signature failure
    - `409 Conflict` on fingerprint clash with a different workspace_id
    - `422 Unprocessable Entity` on persistence errors
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Enrollment
  alias ControlKeel.Cloud.Workspace.Key
  alias ControlKeel.Cloud.Workspace.KeyRegistry
  alias ControlKeel.Repo

  def register(conn, params) do
    with {:ok, verified} <- Enrollment.verify(params),
         {:ok, invite} <- resolve_invite(verified.invite_token),
         :ok <- ensure_fingerprint_unused(verified),
         {:ok, key, status} <- enroll(verified, invite) do
      conn
      |> put_status(status)
      |> json(summary(key))
    else
      {:error, :proof_signature_invalid} ->
        unauthorized(conn, "proof_signature_invalid")

      {:error, reason} when reason in [:malformed, :missing_fields] ->
        bad_request(conn, reason)

      {:error, reason}
      when reason in [
             :unsupported_algorithm,
             :public_key_invalid,
             :proof_expired,
             :proof_future_dated,
             :proof_payload_mismatch
           ] ->
        bad_request(conn, reason)

      {:error, :invalid_invite} ->
        bad_request(conn, "invalid_invite_token")

      {:error, :fingerprint_conflict} ->
        conflict(conn, "fingerprint_belongs_to_other_workspace")

      {:error, :revoked} ->
        # This workspace's registration was revoked. Re-enrollment must not
        # silently undo that, even for a caller that still holds the old key.
        conflict(conn, "workspace_registration_revoked")

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "persistence_failed", details: format_changeset(cs)})
    end
  end

  defp resolve_invite(nil), do: {:ok, %{org_id: nil, mission_workspace_id: nil}}
  defp resolve_invite(""), do: {:ok, %{org_id: nil, mission_workspace_id: nil}}

  defp resolve_invite(token) when is_binary(token) do
    case Accounts.lookup_invitation(token) do
      {:ok, %{org: %{id: org_id}, mission_workspace_id: mws_id}} ->
        {:ok, %{org_id: org_id, mission_workspace_id: mws_id}}

      _ ->
        {:error, :invalid_invite}
    end
  end

  defp ensure_fingerprint_unused(%{workspace_id: ws, fingerprint: fp}) do
    # DB-level check: if a key with this fingerprint exists and belongs to a
    # DIFFERENT workspace, reject. Same-workspace match is OK (re-enrollment).
    case Repo.get_by(Key, fingerprint: fp) do
      nil -> :ok
      %Key{workspace_id: ^ws} -> :ok
      %Key{} -> {:error, :fingerprint_conflict}
    end
  end

  defp enroll(verified, %{org_id: org_id, mission_workspace_id: mws_id}) do
    existing = Repo.get_by(Key, workspace_id: verified.workspace_id)
    status = if existing, do: :ok, else: :created

    case KeyRegistry.enroll(%{
           workspace_id: verified.workspace_id,
           public_key: verified.public_key,
           algorithm: verified.algorithm,
           fingerprint: verified.fingerprint,
           name: verified.name,
           org_id: org_id,
           mission_workspace_id: mws_id
         }) do
      {:ok, key} -> {:ok, key, status}
      {:error, :revoked} -> {:error, :revoked}
      {:error, cs} -> {:error, cs}
    end
  end

  defp summary(%Key{} = key) do
    %{
      workspace_id: key.workspace_id,
      fingerprint: key.fingerprint,
      algorithm: key.algorithm,
      name: key.name,
      org_id: key.org_id,
      mission_workspace_id: key.mission_workspace_id,
      enrolled_at: key.inserted_at,
      last_seen_at: key.last_seen_at
    }
  end

  defp bad_request(conn, reason) when is_atom(reason),
    do: bad_request(conn, Atom.to_string(reason))

  defp bad_request(conn, reason) when is_binary(reason) do
    conn |> put_status(:bad_request) |> json(%{error: reason})
  end

  defp unauthorized(conn, reason) do
    conn |> put_status(:unauthorized) |> json(%{error: reason})
  end

  defp conflict(conn, reason) do
    conn |> put_status(:conflict) |> json(%{error: reason})
  end

  defp format_changeset(%Ecto.Changeset{errors: errors}) do
    Enum.map(errors, fn {field, {message, _opts}} -> "#{field}: #{message}" end)
  end
end
