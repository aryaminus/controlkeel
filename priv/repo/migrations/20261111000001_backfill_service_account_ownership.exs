defmodule ControlKeel.Repo.Migrations.BackfillServiceAccountOwnership do
  @moduledoc """
  One-shot attribution backfill for `service_accounts.created_by_user_id`
  (docs/dsar-erasure-plan.md, 1c). Runs after
  `20261111000000_add_created_by_user_id_to_service_accounts` — it must be a
  separate migration because the column's DDL has to be committed before
  `repo()`-based backfill queries can see it (Ecto runs each migration in its
  own transaction).

  Each unowned account adopts the user recorded as the `actor` on its
  earliest `"provisioned"` NHI event. Actors are bare emails (REST API) or
  `web:<email>` (LiveView), so known prefixes are stripped before an exact
  email lookup. Accounts with no attributable actor (system/CLI-minted) stay
  `nil` — they were not minted by a user and must not be revoked by user
  erasure.

  Works on SQLite (local) and Postgres (cloud): schema-less `repo()` queries
  only, no adapter-specific SQL.
  """

  use Ecto.Migration

  require Logger

  import Ecto.Query, warn: false

  # Actor prefixes seen in the NHI write paths. Keep in sync with the
  # provision call sites (ApiController, WorkspaceServiceAccountsLive).
  @actor_prefixes ["web:", "api:", "cli:"]

  def up do
    unowned =
      from(sa in "service_accounts",
        where: is_nil(sa.created_by_user_id),
        select: %{id: sa.id, name: sa.name}
      )
      |> repo().all()

    {attributed, unattributed} =
      Enum.reduce(unowned, {0, []}, fn sa, {count, skipped} ->
        case provisioned_actor(sa.id) |> resolve_user_id() do
          {:ok, user_id} ->
            from(s in "service_accounts", where: s.id == ^sa.id)
            |> repo().update_all(set: [created_by_user_id: user_id])

            {count + 1, skipped}

          :no_match ->
            {count, [sa.name | skipped]}
        end
      end)

    if unowned != [] do
      Logger.info(
        "service_accounts ownership backfill: attributed #{attributed}/#{length(unowned)} " <>
          "account(s) from NHI provisioned events."
      )
    end

    unless unattributed == [] do
      Logger.warning(
        "service_accounts ownership backfill: #{length(unattributed)} account(s) had no " <>
          "attributable provisioned actor and stay unowned (not user-minted): " <>
          Enum.join(Enum.reverse(unattributed), ", ")
      )
    end
  end

  def down do
    # Attribution is a best-effort historical record; the reverse migration
    # clears it (including any attributions made by the app after this
    # migration ran) so `up` on a fresh migrate reproduces a clean state.
    from(sa in "service_accounts")
    |> repo().update_all(set: [created_by_user_id: nil])

    :ok
  end

  # --- Attribution ------------------------------------------------------------

  defp provisioned_actor(service_account_id) do
    from(e in "nhi_audit_events",
      where:
        e.service_account_id == ^service_account_id and e.event_type == "provisioned" and
          not is_nil(e.actor),
      order_by: [asc: e.occurred_at, asc: e.id],
      limit: 1,
      select: e.actor
    )
    |> repo().one()
  end

  defp resolve_user_id(nil), do: :no_match

  defp resolve_user_id(actor) when is_binary(actor) do
    email = strip_prefixes(actor)

    if String.contains?(email, "@") do
      case from(u in "users", where: u.email == ^email, select: u.id) |> repo().one() do
        nil -> :no_match
        user_id -> {:ok, user_id}
      end
    else
      :no_match
    end
  end

  defp strip_prefixes(actor) do
    Enum.reduce(@actor_prefixes, actor, fn prefix, acc ->
      if String.starts_with?(acc, prefix),
        do: String.slice(acc, byte_size(prefix)..-1//1),
        else: acc
    end)
    |> String.trim()
  end
end
