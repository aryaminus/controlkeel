defmodule ControlKeel.Repo.Migrations.BackfillWorkspaceIdOnBenchmarkRuns do
  @moduledoc """
  Phase 2 of benchmark-run workspace ownership (docs/benchmarks-issue.md,
  slice 1; the operator-approved data migration promised by
  `20261102090000_add_workspace_id_to_benchmark_runs`).

  Local-mode upgrades only in practice — controlkeel.com cloud does not exist,
  and fresh installs have no workspace-less runs, so both paths are no-ops or
  native flips.

  When an operator hits update (`mix ecto.migrate`):

    1. If any `workspace_id IS NULL` benchmark runs exist, the operator is
       asked to proceed (y/n). Answering `n`, blank input, EOF, or anything other
       than y/yes raises and aborts the migrate run so it can be retried later.
    2. Each unowned run is attached to the default workspace
       (`default-workspace` slug). If that slug is absent, the LATEST
       workspace (highest id) wins instead. A database with zero workspaces
       aborts the migration with a message — runs must have an owner, and we
       assume at least one workspace exists.
    3. `workspace_id` is flipped to NOT NULL. Because `benchmark_runs` is the
       parent of `benchmark_results` (ON DELETE CASCADE), dropping it directly
       on SQLite would cascade-wipe every result row (same hazard documented
       in `20260828000004`/`20261027120000`), so the results table is backed
       up first and restored after the rebuild.

  ## SQLite

  `workspace_id` is flipped via a table rebuild following the house pattern
  (`20260717220000`, `20261027120000`): results backup -> rebuild
  `benchmark_runs` with `workspace_id INTEGER NOT NULL` -> restore.

  ## Postgres

  `ALTER TABLE … ALTER COLUMN workspace_id SET NOT NULL` is native; the
  backfill above has already replaced any NULLs, so the flip validates in
  place. No table rebuild is needed.

  Empty or fully-owned databases never prompt — only the flip (or the SQLite
  rebuild) runs. Fully self-contained: no app-code dependency.
  """

  use Ecto.Migration

  require Logger

  import Ecto.Query, warn: false

  # Mirrors ControlKeel.Bootstrap.LocalDefaults (intentionally hardcoded so
  # this migration stays self-contained; LocalDefaults owns the reserved slug).
  @default_workspace_slug "default-workspace"

  def up do
    # Count rather than load: this check only needs "are there any?", and the
    # backfill below re-selects the rows in SQL anyway. Loading every unowned
    # run's id into memory would spike for no benefit on legacy-heavy tables.
    unowned_count =
      from(r in "benchmark_runs", where: is_nil(r.workspace_id))
      |> repo().aggregate(:count)

    if unowned_count == 0 do
      Logger.info("benchmark_runs workspace backfill: nothing to backfill.")
    else
      # Resolve the target workspace BEFORE prompting: with zero workspaces
      # the backfill can never succeed, so abort immediately rather than
      # asking a question whose answer is irrelevant. When a workspace
      # exists, its id is logged above the prompt so the operator can see
      # exactly what they are consenting to.
      workspace_id = resolve_workspace_id()
      confirm_backfill!()
      backfill_runs(workspace_id)
    end

    flip_workspace_not_null()
  end

  def down do
    if sqlite_repo?() do
      rebuild_benchmark_runs(workspace_not_null: false)
    else
      alter table(:benchmark_runs) do
        modify :workspace_id, :bigint, null: true
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3

  # Postgres flips the flag natively; the backfill above has already
  # eliminated NULLs, so SET NOT NULL validates in place.
  defp flip_workspace_not_null do
    if sqlite_repo?() do
      rebuild_benchmark_runs(workspace_not_null: true)
    else
      alter table(:benchmark_runs) do
        modify :workspace_id, :bigint, null: false
      end
    end
  end

  # --- Workspace resolution (public + pure for tests) ----------------------

  @doc """
  Ownership cascade: the `default-workspace` slug wins; otherwise the LATEST
  workspace (highest id); otherwise nil — the caller aborts with a message.
  """
  def resolve_workspace_id(default_workspace_id, latest_workspace_id) do
    cond do
      is_integer(default_workspace_id) -> {:default, default_workspace_id}
      is_integer(latest_workspace_id) -> {:latest, latest_workspace_id}
      true -> :none
    end
  end

  @doc """
  Interactive gate: only an explicit y/yes proceeds. Blank input, EOF, and
  every other answer abort the migration.
  """
  def proceed_answer?(:eof), do: false
  def proceed_answer?(nil), do: false

  def proceed_answer?(input) do
    answer = input |> to_string() |> String.trim() |> String.downcase()
    answer in ["y", "yes"]
  end

  # --- Resolution + backfill -------------------------------------------------

  defp resolve_workspace_id do
    default_id =
      from(w in "workspaces", where: w.slug == ^@default_workspace_slug, select: w.id)
      |> repo().one()

    latest_id =
      from(w in "workspaces", order_by: [desc: w.id], limit: 1, select: w.id)
      |> repo().one()

    case resolve_workspace_id(default_id, latest_id) do
      {source, workspace_id} ->
        Logger.info(
          "benchmark_runs workspace backfill: adopting workspace ##{workspace_id} (#{source})."
        )

        workspace_id

      :none ->
        raise RuntimeError,
              "benchmark_runs workspace backfill aborted: no workspace found. " <>
                "Benchmark runs must belong to a workspace; create one (run ControlKeel once to " <>
                "provision the default workspace), then re-run `mix ecto.migrate`."
    end
  end

  defp confirm_backfill! do
    prompt = """
    Found benchmark run(s) from an older ControlKeel version without a workspace.

    Proceed with the benchmark migration? Each unowned run will be attached to the \
    default workspace (or the latest workspace), and workspace ownership becomes \
    required. [y/N]
    """

    if proceed_answer?(IO.gets(prompt)) do
      :ok
    else
      raise RuntimeError,
            "Benchmark migration aborted by operator. Re-run `mix ecto.migrate` and answer y " <>
              "to migrate old benchmark runs, or leave them unowned (they stay hidden " <>
              "from workspace benchmark pages)."
    end
  end

  defp backfill_runs(workspace_id) do
    {count, _} =
      from(r in "benchmark_runs", where: is_nil(r.workspace_id))
      |> repo().update_all(set: [workspace_id: workspace_id])

    Logger.info(
      "benchmark_runs workspace backfill: #{count} run(s) -> workspace ##{workspace_id}."
    )
  end

  # --- Table rebuild ---------------------------------------------------------

  # SQLite cannot ALTER a column to NOT NULL; rebuild per the house pattern
  # (20260717220000, Postgres branch lives in flip_workspace_not_null/0).
  # benchmark_runs is the PARENT of benchmark_results (ON DELETE CASCADE):
  # dropping it fires the cascade and wipes results, so the results table is
  # backed up and restored around the rebuild. Postgres never takes this path.
  defp rebuild_benchmark_runs(workspace_not_null: workspace_not_null) do
    execute(
      "CREATE TABLE benchmark_results_ws_backfill_backup AS SELECT * FROM benchmark_results"
    )

    execute("DROP TABLE benchmark_results")

    execute("""
    CREATE TABLE benchmark_runs_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      suite_id INTEGER NOT NULL CONSTRAINT benchmark_runs_suite_id_fkey REFERENCES benchmark_suites(id) ON DELETE CASCADE,
      status TEXT DEFAULT 'pending' NOT NULL,
      baseline_subject TEXT NOT NULL,
      subjects TEXT DEFAULT '[]' NOT NULL,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      total_scenarios INTEGER DEFAULT 0 NOT NULL,
      caught_count INTEGER DEFAULT 0 NOT NULL,
      blocked_count INTEGER DEFAULT 0 NOT NULL,
      catch_rate NUMERIC DEFAULT 0.0 NOT NULL,
      median_latency_ms INTEGER,
      average_overhead_percent NUMERIC,
      metadata TEXT DEFAULT ('{}') NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      #{workspace_column(workspace_not_null)}
    )
    """)

    execute("""
    INSERT INTO benchmark_runs_new (
      id, suite_id, status, baseline_subject, subjects, started_at, finished_at,
      total_scenarios, caught_count, blocked_count, catch_rate, median_latency_ms,
      average_overhead_percent, metadata, inserted_at, updated_at, workspace_id
    )
    SELECT
      id, suite_id, status, baseline_subject, subjects, started_at, finished_at,
      total_scenarios, caught_count, blocked_count, catch_rate, median_latency_ms,
      average_overhead_percent, metadata, inserted_at, updated_at, workspace_id
    FROM benchmark_runs
    """)

    execute("DROP TABLE benchmark_runs")
    execute("ALTER TABLE benchmark_runs_new RENAME TO benchmark_runs")

    create index(:benchmark_runs, [:suite_id])
    create index(:benchmark_runs, [:status])
    create index(:benchmark_runs, [:started_at])
    create index(:benchmark_runs, [:workspace_id])
    create index(:benchmark_runs, [:workspace_id, :inserted_at])

    execute("""
    CREATE TABLE benchmark_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id INTEGER NOT NULL CONSTRAINT benchmark_results_run_id_fkey REFERENCES benchmark_runs(id) ON DELETE CASCADE,
      scenario_id INTEGER NOT NULL CONSTRAINT benchmark_results_scenario_id_fkey REFERENCES benchmark_scenarios(id) ON DELETE CASCADE,
      subject TEXT NOT NULL,
      subject_type TEXT NOT NULL,
      status TEXT DEFAULT 'pending' NOT NULL,
      decision TEXT,
      findings_count INTEGER DEFAULT 0 NOT NULL,
      matched_expected INTEGER DEFAULT false NOT NULL,
      latency_ms INTEGER,
      overhead_percent NUMERIC,
      payload TEXT DEFAULT ('{}') NOT NULL,
      metadata TEXT DEFAULT ('{}') NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO benchmark_results (
      id, run_id, scenario_id, subject, subject_type, status, decision,
      findings_count, matched_expected, latency_ms, overhead_percent,
      payload, metadata, inserted_at, updated_at
    )
    SELECT
      id, run_id, scenario_id, subject, subject_type, status, decision,
      findings_count, matched_expected, latency_ms, overhead_percent,
      payload, metadata, inserted_at, updated_at
    FROM benchmark_results_ws_backfill_backup
    """)

    execute("DROP TABLE benchmark_results_ws_backfill_backup")

    create unique_index(:benchmark_results, [:run_id, :scenario_id, :subject])
    create index(:benchmark_results, [:run_id])
    create index(:benchmark_results, [:scenario_id])
    create index(:benchmark_results, [:subject])
    create index(:benchmark_results, [:status])
  end

  defp workspace_column(true),
    do:
      "workspace_id INTEGER NOT NULL CONSTRAINT benchmark_runs_workspace_id_fkey REFERENCES workspaces(id) ON DELETE CASCADE"

  defp workspace_column(false),
    do:
      "workspace_id INTEGER CONSTRAINT benchmark_runs_workspace_id_fkey REFERENCES workspaces(id) ON DELETE CASCADE"
end
