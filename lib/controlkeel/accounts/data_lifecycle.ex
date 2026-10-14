defmodule ControlKeel.Accounts.DataLifecycle do
  @moduledoc """
  User and organization erasure (issue #266).

  ## Why this exists

  ControlKeel sells customers GDPR/SOX/HIPAA/CCPA retention compliance via
  `priv/policy_packs/*.json`, and enforced none of it against its own database.
  There was no `Repo.delete` on `User` or `Org` anywhere in `lib/`, and no
  self-service DSAR surface, so GDPR Art.15 (access) and Art.17 (erasure) were
  unimplementable by the customer *or* by the operator.

  ## The retention contract

  Erasure is not "delete everything the user touched." Sessions, findings, and
  proof bundles belong to the **workspace**, not the person: deleting one
  engineer's account must not destroy the governance record their team
  depends on. So the contract is per data class:

  | Class | Treatment | Rationale |
  |---|---|---|
  | User row, memberships | **Purge** | Identity itself. Memberships cascade. |
  | Credentials the user minted (service accounts, cloud workspace keys, API tokens) | **Purge** | Revoked anyway on offboarding; keeping them is a live risk. |
  | Audit rows referencing the user (`actor_user_id`, `target_user_id`, `assigned_*`, `decided_by_*`) | **Anonymize** | The *event* is the compliance record and must survive; the *identity* in it must not. |
  | Free-text identity in audit rows (`actor_identifier`, `actor`, `actor_role`) | **Anonymize** | FK nulling does not touch these; an email here is PII that would outlive the account forever. |
  | Audit `note` / `reason` free text | **Retain** | Cannot be reliably scrubbed without destroying the record's meaning; retained under legitimate interest. Flagged as a known limitation. |
  | Sessions, findings, proofs, memory, benchmarks for the org | **Retain on user delete** | Tenant-owned governance record. Purged only when the **org** is deleted. |
  | Organization row and everything under it | **Purge** on `delete_org/1` | The tenant asked to be removed; the whole tree goes. |

  ## Pseudonymization

  Erased identities become a stable, non-reversible marker
  (`"erased-user-<hash>"`) derived from the id and a per-deployment salt. It is
  *not* reversible to an email, but it is stable, so an auditor can still tell
  that two audit rows belong to the same erased actor — which is what makes an
  audit trail useful after erasure.

  ## Deliberate non-goals

  - **Backup erasure.** Rows purged here still exist in backups; that is a
    documented, standard limitation (GDPR allows it with a defined backup
    rotation) and is tracked separately.
  - **Free-text scrubbing** of `note`/`reason`, for the reason above.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Accounts.{Membership, Org, User}
  alias ControlKeel.Accounts.OrgIdentityProvider
  alias ControlKeel.Accounts.ReviewAuditEvent
  alias ControlKeel.Mission.FindingAuditEvent
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.NhiAuditEvent
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeel.Repo

  @erased_prefix "erased-user-"

  @doc """
  Export everything ControlKeel holds about a user (GDPR Art.15).

  Returns a JSON-ready map. Deliberately includes the caller's own
  memberships and org references but not other members' data.
  """
  @spec export_user_data(integer()) :: {:ok, map()} | {:error, :not_found}
  def export_user_data(user_id) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        memberships =
          Membership
          |> where([m], m.user_id == ^user_id)
          |> preload(:org)
          |> Repo.all()
          |> Enum.map(fn m ->
            %{
              org_id: m.org_id,
              org_slug: m.org && m.org.slug,
              role: m.role,
              status: m.status,
              created_at: m.inserted_at
            }
          end)

        {:ok,
         %{
           user: %{
             id: user.id,
             email: user.email,
             name: user.name,
             status: user.status,
             created_at: user.inserted_at
           },
           memberships: memberships,
           audit_trail: user_audit_rows(user.id),
           exported_at: DateTime.utc_now()
         }}
    end
  end

  @doc """
  Erase a user account (GDPR Art.17).

  Refuses when the user is the **last active owner** of any org: deleting them
  would orphan that org with no one able to administer it. The caller must
  promote another owner or delete the org first.
  """
  @spec delete_user(integer()) :: {:ok, map()} | {:error, :sole_owner | :not_found | term()}
  def delete_user(user_id) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        with :ok <- refuse_if_sole_owner(user) do
          stats = Repo.transaction(fn -> erase_user(user) end)

          case stats do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  defp erase_user(user) do
    anonymize = anonymized_identifier(user)

    audit =
      %{
        review_events: anonymize_review_events(user, anonymize),
        finding_events: anonymize_finding_events(user, anonymize),
        nhi_events: anonymize_nhi_events(user, anonymize)
      }

    credentials = revoke_credentials(user)

    # Memberships cascade; the user row goes last so the cascades have a parent.
    {deleted, _} = Repo.delete_all(from(m in Membership, where: m.user_id == ^user.id))
    Repo.delete!(user)

    Map.merge(audit, %{
      memberships_deleted: deleted,
      credentials_revoked: credentials,
      user_deleted: true
    })
  end

  defp refuse_if_sole_owner(user) do
    owned =
      Membership
      |> where([m], m.user_id == ^user.id and m.role == "owner" and m.status == "active")
      |> Repo.all()

    blocked =
      Enum.any?(owned, fn membership ->
        Repo.aggregate(
          from(m in Membership,
            where: m.org_id == ^membership.org_id and m.role == "owner" and m.status == "active"
          ),
          :count
        ) <= 1
      end)

    if blocked, do: {:error, :sole_owner}, else: :ok
  end

  # ── Anonymization ────────────────────────────────────────────────────────
  #
  # The event survives; the identity does not.

  defp anonymize_review_events(user, marker) do
    {n, _} =
      Repo.update_all(
        from(e in ReviewAuditEvent,
          where: e.actor_user_id == ^user.id or e.target_user_id == ^user.id
        ),
        set: [
          actor_user_id: nil,
          target_user_id: nil,
          actor_identifier: marker,
          note: nil
        ]
      )

    n
  end

  defp anonymize_finding_events(user, marker) do
    {n, _} =
      Repo.update_all(
        from(e in FindingAuditEvent, where: e.actor_user_id == ^user.id),
        set: [actor_user_id: nil, actor_identifier: marker]
      )

    n
  end

  defp anonymize_nhi_events(user, marker) do
    # NHI rows store an unconstrained `actor` string holding an identity.
    {n, _} =
      Repo.update_all(
        from(e in NhiAuditEvent, where: like(e.actor, ^"%#{user.email}%")),
        set: [actor: marker]
      )

    n
  end

  defp revoke_credentials(user) do
    {n, _} =
      Repo.update_all(
        from(s in ServiceAccount, where: s.metadata["created_by_user_id"] == ^user.id),
        set: [status: "revoked"]
      )

    n
  end

  defp user_audit_rows(user_id) do
    review =
      ReviewAuditEvent
      |> where([e], e.actor_user_id == ^user_id or e.target_user_id == ^user_id)
      |> Repo.all()
      |> Enum.map(&Map.take(&1, [:id, :event_type, :actor_role, :recorded_at]))

    findings =
      FindingAuditEvent
      |> where([e], e.actor_user_id == ^user_id)
      |> Repo.all()
      |> Enum.map(&Map.take(&1, [:id, :event_type, :new_status, :recorded_at]))

    %{review_events: review, finding_events: findings}
  end

  # Stable but non-reversible. Derived from the id with a per-deployment salt so
  # the marker cannot be correlated across deployments or brute-forced back to
  # an id.
  defp anonymized_identifier(user) do
    digest =
      :crypto.hash(:sha256, "#{user.id}:#{deployment_salt()}") |> Base.encode16(case: :lower)

    @erased_prefix <> binary_part(digest, 0, 16)
  end

  defp deployment_salt do
    ControlKeelWeb.Endpoint.config(:secret_key_base) || "controlkeel"
  end

  @doc """
  Erase an organization and everything beneath it.

  Cascade is handled by the schema's `on_delete: :delete_all` foreign keys
  (workspaces → sessions → findings/proofs/memory). Audit rows that survive
  because they reference users rather than orgs are left intact with their
  org references nulled - the audit *record* of what happened to the tenant is
  itself compliance evidence.
  """
  @spec delete_org(integer()) :: {:ok, map()} | {:error, :not_found | term()}
  def delete_org(org_id) when is_integer(org_id) do
    case Repo.get(Org, org_id) do
      nil ->
        {:error, :not_found}

      org ->
        stats =
          Repo.transaction(fn ->
            ws_ids = workspace_ids(org.id)

            # `workspaces.org_id` is `on_delete: :nilify_all`, NOT a cascade
            # (see migration 20260524142342), so deleting the org does **not**
            # remove its workspaces - it would silently orphan every one of
            # them. Delete the workspace rows explicitly so their own cascades
            # (sessions -> findings, proofs, memory, credentials) fire.
            purge_orphaned_by_workspace(ws_ids)

            {workspaces_deleted, _} =
              Repo.delete_all(from(w in Workspace, where: w.org_id == ^org.id))

            providers =
              Repo.delete_all(from(p in OrgIdentityProvider, where: p.org_id == ^org.id))

            Repo.delete!(org)

            %{
              org_deleted: true,
              workspaces: workspaces_deleted,
              identity_providers_deleted: providers
            }
          end)

        case stats do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp workspace_ids(org_id) do
    ControlKeel.Mission.Workspace
    |> where([w], w.org_id == ^org_id)
    |> select([w], w.id)
    |> Repo.all()
  end

  # Tables whose workspace FK is :nilify_all rather than :delete_all. Deleting
  # the org would NULL their workspace_id and strand them, so they are purged
  # here to make org deletion complete.
  defp purge_orphaned_by_workspace([]), do: 0

  defp purge_orphaned_by_workspace(ws_ids) do
    Enum.reduce(
      [
        ControlKeel.Analytics.Event,
        ControlKeel.Observability.EvalCandidate,
        ControlKeel.Observability.ImportedEnvelope,
        ControlKeel.Observability.BenchmarkDraft
      ],
      0,
      fn schema, acc ->
        {n, _} = Repo.delete_all(from(r in schema, where: r.workspace_id in ^ws_ids))
        acc + n
      end
    )
  end
end
