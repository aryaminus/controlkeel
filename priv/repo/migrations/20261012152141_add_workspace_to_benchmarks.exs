defmodule ControlKeel.Repo.Migrations.AddWorkspaceToBenchmarks do
  use Ecto.Migration

  # Multi-tenant isolation for benchmark data (issue #248).
  #
  # Model: shared schema with a tenant discriminator column — the standard
  # default for B2B SaaS, and already the pattern used by every other table in
  # this schema (sessions, findings, workspaces all carry workspace_id).
  #
  # NULL workspace_id means **platform/builtin** content: the built-in suites
  # shipped with ControlKeel, which every tenant may run but no tenant owns.
  # Tenant-created rows always carry a workspace_id.
  #
  # Backfill: existing rows are left NULL. Pre-launch these are test/dev rows
  # and built-in suites; assigning them to an arbitrary tenant would be wrong,
  # and NULL correctly classifies them as platform content that stays visible.
  def change do
    alter table(:benchmark_suites) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    alter table(:benchmark_runs) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    create index(:benchmark_suites, [:workspace_id])
    create index(:benchmark_runs, [:workspace_id])
    create index(:benchmark_runs, [:workspace_id, :inserted_at])
  end
end