defmodule ControlKeel.Cloud.Workspace.KeyRegistry do
  @moduledoc """
  Multi-tenant registry of enrolled workspace public keys.

  This is the receiver-side counterpart to
  `ControlKeel.Cloud.Workspace.Identity`. Phase 7 introduces this so that
  controlkeel.com can verify Bearer tokens from many different laptops, each
  owning its own ed25519 keypair.

  Public API:

    - `enroll/1` — store or refresh a registration (idempotent on fingerprint).
    - `fetch/1` — look up the active registration for a workspace_id.
    - `revoke/1` — soft-delete a registration so its tokens stop verifying.
    - `list_for_org/1` — list workspaces visible to a given org_id (used by
      the org-scoped projects LiveView).
    - `fetch_by_mission_workspace/1` — resolve the cloud enrollment for a
      local mission workspace (bridges the `ws_` ULID to `workspaces.id`).
    - `touch_last_seen/1` — update last_seen_at on successful token verify.

  Self-host single-node deployments are not required to use this table at
  all — `AuthToken.verify/1` falls back to the local `Identity`
  when no registry row exists.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.Workspace.Key
  alias ControlKeel.Repo

  @type enrollment :: %{
          workspace_id: String.t(),
          public_key: String.t(),
          algorithm: String.t(),
          fingerprint: String.t(),
          name: String.t() | nil,
          org_id: integer() | nil,
          mission_workspace_id: integer() | nil
        }

  @doc """
  Insert or refresh a registration.

  When a row already exists for `workspace_id`, the public key, fingerprint,
  algorithm, name, and (optionally) org binding are updated and `revoked_at`
  is cleared. Otherwise a new row is inserted.

  Callers must compute the fingerprint themselves (hex SHA256 of the raw
  public key bytes) before calling. This keeps the registry agnostic to
  encoding choices.
  """
  @spec enroll(enrollment()) ::
          {:ok, %Key{}} | {:error, Ecto.Changeset.t() | :revoked}
  def enroll(%{workspace_id: ws} = attrs) when is_binary(ws) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    base = Map.put(attrs, :last_seen_at, now)

    case Repo.get_by(Key, workspace_id: ws) do
      nil ->
        %Key{}
        |> Key.changeset(base)
        |> Repo.insert()

      %Key{revoked_at: nil} = existing ->
        # Re-registration of a live key only refreshes the material.
        existing
        |> Key.changeset(base)
        |> Repo.update()

      %Key{revoked_at: %DateTime{}} ->
        # A revoked registration stays revoked. Previously this branch cleared
        # `revoked_at`, which let a caller holding the old private key silently
        # un-revoke itself by re-posting to the (unauthenticated) register
        # endpoint — revocation has to be terminal to mean anything. An operator
        # can re-provision by removing the row, which is an explicit action.
        {:error, :revoked}
    end
  end

  @doc """
  Look up the active registration for `workspace_id`.

  Returns `{:ok, key}` when an active (non-revoked) row exists,
  `{:error, :not_found}` otherwise.
  """
  @spec fetch(String.t()) :: {:ok, %Key{}} | {:error, :not_found}
  def fetch(workspace_id) when is_binary(workspace_id) do
    case Repo.get_by(Key, workspace_id: workspace_id) do
      nil -> {:error, :not_found}
      %Key{revoked_at: nil} = key -> {:ok, key}
      %Key{} -> {:error, :not_found}
    end
  end

  @doc "Soft-delete a registration."
  @spec revoke(String.t()) :: {:ok, %Key{}} | {:error, :not_found | Ecto.Changeset.t()}
  def revoke(workspace_id) when is_binary(workspace_id) do
    case Repo.get_by(Key, workspace_id: workspace_id) do
      nil ->
        {:error, :not_found}

      %Key{} = key ->
        key
        |> Key.changeset(%{
          revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  @doc "All active registrations bound to the given org."
  @spec list_for_org(integer() | nil) :: [%Key{}]
  def list_for_org(nil), do: []

  def list_for_org(org_id) when is_integer(org_id) do
    from(k in Key,
      where: k.org_id == ^org_id and is_nil(k.revoked_at),
      order_by: [desc: k.last_seen_at, desc: k.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Refresh `last_seen_at` on the row for `workspace_id` (best-effort)."
  @spec touch_last_seen(String.t()) :: :ok
  def touch_last_seen(workspace_id) when is_binary(workspace_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(k in Key, where: k.workspace_id == ^workspace_id)
    |> Repo.update_all(set: [last_seen_at: now])

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Find the active `Key` linked to a mission workspace.

  Returns `{:ok, key}` when an active enrollment exists for the given
  mission workspace ID, `{:error, :not_found}` otherwise. Useful for
  resolving the cloud identity of a local project workspace.
  """
  @spec fetch_by_mission_workspace(integer()) :: {:ok, %Key{}} | {:error, :not_found}
  def fetch_by_mission_workspace(mission_workspace_id) when is_integer(mission_workspace_id) do
    from(k in Key,
      where: k.mission_workspace_id == ^mission_workspace_id and is_nil(k.revoked_at),
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      %Key{} = key -> {:ok, key}
    end
  end

  @spec fingerprint_for(String.t()) :: {:ok, String.t()} | {:error, :public_key_invalid}
  def fingerprint_for(public_key_b64) when is_binary(public_key_b64) do
    case Base.decode64(public_key_b64) do
      {:ok, raw} -> {:ok, :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)}
      :error -> {:error, :public_key_invalid}
    end
  end
end
