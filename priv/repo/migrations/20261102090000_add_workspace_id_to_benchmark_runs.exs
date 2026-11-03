defmodule ControlKeel.Repo.Migrations.AddWorkspaceIdToBenchmarkRuns do
  @moduledoc """
  Workspace ownership on benchmark runs (docs/benchmarks-issue.md, slice 1).

  Adds a nullable `benchmark_runs.workspace_id` FK plus the two access
  indexes from the issue:
  `[:workspace_id]` and `[:workspace_id, :inserted_at]`.
  From this migration on, `Benchmark.Run.changeset/2` requires
  `workspace_id`, so every NEW run is workspace-owned; existing rows are
  backfilled and `workspace_id` flips to NOT NULL in a later operator-approved
  data migration (the two-phase pattern approved for `policy_sets` org
  ownership in `20260828000004` + `20261027120000`).

  `on_delete: :delete_all` means a workspace deletion drops its runs, and the
  `[:workspace_id, :inserted_at]` index serves the workspace-scoped recent-runs
  listing.
  """

  use Ecto.Migration

  def up do
    alter table(:benchmark_runs) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    create index(:benchmark_runs, [:workspace_id])
    create index(:benchmark_runs, [:workspace_id, :inserted_at])
  end

  def down do
    drop index(:benchmark_runs, [:workspace_id, :inserted_at])
    drop index(:benchmark_runs, [:workspace_id])

    alter table(:benchmark_runs) do
      remove :workspace_id
    end
  end
end
