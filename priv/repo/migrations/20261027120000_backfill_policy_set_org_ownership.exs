defmodule ControlKeel.Repo.Migrations.BackfillPolicySetOrgOwnership do
  @moduledoc """
  One-shot data + DDL migration for users upgrading from pre-org-ownership
  databases (approved review #3).

  The schema migration `20260828000004` adds a nullable `policy_sets.org_id`
  and drops `scope`; rows from older databases are left org-less — invisible
  in listings, not re-appliable, yet still evaluating rules. This migration
  finishes the job:

    1. If any org-less sets exist, the operator is asked to proceed (y/n).
       Answering `n` (or anything but y/yes) raises and aborts the migrate
       run so it can be retried later. Non-interactive runs (no stdin) get
       :eof and proceed with the default.
    2. Each org-less set is adopted via the approved cascade: unique
       assignment-hint org -> sole org -> oldest org -> newly created default
       org. The default org uses the reserved local-mode slug from
       `ControlKeel.Bootstrap.LocalDefaults` (the single source of truth for
       local provisioning, which runs right after migrations at boot), so the
       boot seed reuses this org instead of creating a second one — legacy
       sets and the Default Workspace end up in the same org.
    3. `org_id` is flipped to NOT NULL. Because `policy_sets` is the parent of
       `workspace_policy_sets` (ON DELETE CASCADE), dropping it directly on
       SQLite would cascade-wipe every assignment row (the hazard documented
       in `20260828000001`), so the join table is backed up first and
       restored after the rebuild.

  ## SQLite

  `org_id` is flipped via a table rebuild following the house pattern
  (`20260717220000`): join-table backup -> rebuild `policy_sets` with
  `org_id INTEGER NOT NULL` -> restore.

  ## Postgres

  `ALTER TABLE … ALTER COLUMN org_id SET NOT NULL` is native; the backfill
  above has already replaced any NULLs, so the flip validates in place.
  No table rebuild (and no join-table dance) is needed.

  Empty databases (fresh installs) have no org-less sets, so the prompt and
  default-org creation never fire — new installations are provisioned by
  `LocalDefaults` exactly as before. Fully self-contained: no app-code
  dependency, safe on fresh-DB runs.
  """

  use Ecto.Migration

  require Logger

  import Ecto.Query, warn: false

  # Mirrors ControlKeel.Bootstrap.LocalDefaults (intentionally hardcoded so
  # this migration stays self-contained; LocalDefaults owns the reserved slug).
  @default_org_name "Default Organization"
  @default_org_slug "default-organization"

  def up do
    org_ids = org_ids_oldest_first()

    org_less_sets =
      from(s in "policy_sets", where: is_nil(s.org_id), select: %{id: s.id, name: s.name})
      |> repo().all()

    case org_less_sets do
      [] ->
        Logger.info("policy_sets org backfill: nothing to backfill.")

      sets ->
        confirm_backfill!(sets)
        backfill_sets(sets, org_ids)
    end

    flip_org_not_null()
  end

  def down do
    if sqlite_repo?() do
      rebuild_policy_sets(org_not_null: false)
    else
      alter table(:policy_sets) do
        modify :org_id, :bigint, null: true
      end
    end
  end

  # Postgres flips the flag natively; the backfill above has already
  # eliminated NULLs, so SET NOT NULL validates in place.
  defp flip_org_not_null do
    if sqlite_repo?() do
      rebuild_policy_sets(org_not_null: true)
    else
      alter table(:policy_sets) do
        modify :org_id, :bigint, null: false
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3

  # Schema-less insert_all bypasses Ecto type casting: SQLite stores JSON in a
  # TEXT column (pre-encoded string), Postgres jsonb wants the native map.
  defp settings_payload do
    if sqlite_repo?(), do: Jason.encode!(%{}), else: %{}
  end

  # --- Ownership resolution (public + pure for tests) ---------------------

  @doc """
  Approved cascade: a unique assignment-hint org wins; otherwise a sole org;
  otherwise the oldest org; otherwise the created default org. The returned
  tag distinguishes confident assignments from defaults for logging.
  """
  def resolve_org_id(hint_org_ids, org_ids_oldest_first, default_org_id) do
    case Enum.uniq(hint_org_ids) do
      [org_id] ->
        {:hint_org, org_id}

      _ambiguous_or_empty_hints ->
        case org_ids_oldest_first do
          [sole_org_id] -> {:sole_org, sole_org_id}
          [oldest | _rest] -> {:oldest_org, oldest}
          [] -> {:default_org, default_org_id}
        end
    end
  end

  @doc """
  Interactive gate: empty input (enter) and non-interactive EOF proceed with
  the default; anything other than y/yes aborts the migration.

  `:eof` must never be compared as a string (to_string yields "eof"), or a
  headless release boot would abort mid-migration instead of taking the
  [Y/n] default.
  """
  def proceed_answer?(:eof), do: true

  def proceed_answer?(input) do
    case input |> to_string() |> String.trim() |> String.downcase() do
      "" -> true
      answer -> answer in ["y", "yes"]
    end
  end

  def default_org_attrs do
    %{name: @default_org_name, slug: @default_org_slug, status: "active"}
  end

  # --- Backfill -------------------------------------------------------------

  defp confirm_backfill!(sets) do
    prompt = """
    Found #{length(sets)} policy set(s) from an older ControlKeel version without an organization.

    Proceed with the policy migration? Each set will be assigned to its applied
    workspaces' organization, or the oldest organization in this database, and
    policy ownership becomes required. [Y/n]
    """

    if proceed_answer?(IO.gets(prompt)) do
      :ok
    else
      raise RuntimeError,
            "Policy migration aborted by operator. Re-run `mix ecto.migrate` and answer y " <>
              "to migrate old policy sets, or leave them unmigrated (they stay hidden " <>
              "from the org settings Policy sets tab)."
    end
  end

  defp backfill_sets(sets, org_ids) do
    {default_org_id, created_default_org?} = maybe_create_default_org(org_ids)

    {assignments, defaulted} =
      Enum.map_reduce(sets, [], fn set, defaulted ->
        {source, org_id} =
          resolve_org_id(assignment_hint_org_ids(set.id), org_ids, default_org_id)

        from(s in "policy_sets", where: s.id == ^set.id)
        |> repo().update_all(set: [org_id: org_id])

        {set.id, source, org_id}
        |> then(fn assignment ->
          {assignment,
           if(source in [:oldest_org, :default_org], do: [set.name | defaulted], else: defaulted)}
        end)
      end)

    Enum.each(assignments, fn {id, source, org_id} ->
      Logger.info("policy_sets org backfill: set ##{id} -> org ##{org_id} (#{source})")
    end)

    unless defaulted == [] do
      Logger.warning(
        "policy_sets org backfill: #{length(defaulted)} set(s) had no ownership hint and " <>
          "were assigned by default: #{Enum.join(defaulted, ", ")}"
      )
    end

    log_mismatched_assignments()

    if created_default_org? do
      Logger.warning(
        "policy_sets org backfill: database had no organizations; created default " <>
          "organization #{@default_org_name} (#{@default_org_slug})."
      )
    end

    :ok
  end

  defp org_ids_oldest_first do
    from(o in "orgs", order_by: [asc: o.id], select: o.id) |> repo().all()
  end

  defp assignment_hint_org_ids(policy_set_id) do
    from(j in "workspace_policy_sets",
      join: w in "workspaces",
      on: w.id == j.workspace_id,
      where: j.policy_set_id == ^policy_set_id and not is_nil(w.org_id),
      distinct: true,
      select: w.org_id
    )
    |> repo().all()
  end

  defp maybe_create_default_org([] = _org_ids) do
    # Zero-org DB: create the default org so every set gets an owner and the
    # NOT NULL flip below always succeeds. Only reachable when org-less sets
    # exist (guard in up/0), so test DBs are never polluted.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{"name" => @default_org_name, "slug" => @default_org_slug, "status" => "active"}
    |> Map.merge(%{
      "inserted_at" => now,
      "updated_at" => now,
      "settings" => settings_payload()
    })
    |> then(fn attrs -> repo().insert_all("orgs", [attrs]) end)

    [default_org_id] =
      from(o in "orgs", where: o.slug == ^@default_org_slug, select: o.id) |> repo().all()

    {default_org_id, true}
  end

  defp maybe_create_default_org([oldest | _rest]), do: {oldest, false}

  defp log_mismatched_assignments do
    # Assignment rows whose workspace org cannot match the (now org-owned)
    # set: workspaces of a different org than the defaulted set, or solo
    # org-nil workspaces. They keep evaluating rules.
    #
    # Known consequence for the solo-workspace rows (CK finding #20,
    # documented at WorkspacePolicySet.validate_same_org/1): their
    # assignments can no longer be toggled — disable/re-enable re-save
    # through the changeset, which rejects the org-nil workspace. Removal
    # still works, and is one-way. Deferred until the future PR requiring
    # every workspace to live inside an org.
    mismatched =
      from(j in "workspace_policy_sets",
        join: s in "policy_sets",
        on: s.id == j.policy_set_id,
        join: w in "workspaces",
        on: w.id == j.workspace_id,
        where: is_nil(w.org_id) or w.org_id != s.org_id,
        select: count(j.id)
      )
      |> repo().one()

    if mismatched && mismatched > 0 do
      Logger.warning(
        "policy_sets org backfill: #{mismatched} workspace assignment(s) reference a " <>
          "workspace whose organization does not match the set's organization. They still " <>
          "evaluate, but must be re-applied from the matching org to change. Assignments " <>
          "on org-less workspaces cannot be toggled (see WorkspacePolicySet.validate_same_org)."
      )
    end
  end

  # --- Table rebuild --------------------------------------------------------

  # SQLite cannot ALTER a column to NOT NULL; rebuild per the house pattern
  # (20260717220000, Postgres branch lives in flip_org_not_null/0).
  # policy_sets is the PARENT of workspace_policy_sets (ON DELETE CASCADE):
  # dropping it fires the cascade and wipes assignments, so the join table is
  # backed up and restored around the rebuild. Postgres never takes this path.
  defp rebuild_policy_sets(org_not_null: org_not_null) do
    execute(
      "CREATE TABLE workspace_policy_sets_backfill_backup AS SELECT * FROM workspace_policy_sets"
    )

    execute("DROP TABLE workspace_policy_sets")

    execute("""
    CREATE TABLE policy_sets_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      rules TEXT DEFAULT ('{}') NOT NULL,
      status TEXT DEFAULT 'active' NOT NULL,
      metadata TEXT DEFAULT ('{}') NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      #{org_column(org_not_null)}
    )
    """)

    execute("""
    INSERT INTO policy_sets_new (
      id, name, description, rules, status, metadata, inserted_at, updated_at, org_id
    )
    SELECT
      id, name, description, rules, status, metadata, inserted_at, updated_at, org_id
    FROM policy_sets
    """)

    execute("DROP TABLE policy_sets")
    execute("ALTER TABLE policy_sets_new RENAME TO policy_sets")

    create index(:policy_sets, [:status])
    create index(:policy_sets, [:org_id])

    execute("""
    CREATE TABLE workspace_policy_sets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workspace_id INTEGER NOT NULL CONSTRAINT workspace_policy_sets_workspace_id_fkey REFERENCES workspaces(id) ON DELETE CASCADE,
      policy_set_id INTEGER NOT NULL CONSTRAINT workspace_policy_sets_policy_set_id_fkey REFERENCES policy_sets(id) ON DELETE CASCADE,
      precedence INTEGER DEFAULT 100 NOT NULL,
      enabled INTEGER DEFAULT true NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO workspace_policy_sets (
      id, workspace_id, policy_set_id, precedence, enabled, inserted_at, updated_at
    )
    SELECT
      id, workspace_id, policy_set_id, precedence, enabled, inserted_at, updated_at
    FROM workspace_policy_sets_backfill_backup
    """)

    execute("DROP TABLE workspace_policy_sets_backfill_backup")

    create unique_index(:workspace_policy_sets, [:workspace_id, :policy_set_id])
    create index(:workspace_policy_sets, [:workspace_id, :precedence])
  end

  defp org_column(true),
    do:
      "org_id INTEGER NOT NULL CONSTRAINT policy_sets_org_id_fkey REFERENCES orgs(id) ON DELETE CASCADE"

  defp org_column(false),
    do: "org_id INTEGER CONSTRAINT policy_sets_org_id_fkey REFERENCES orgs(id) ON DELETE CASCADE"
end
