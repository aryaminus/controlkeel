defmodule ControlKeel.Repo.Local.Migrations.ScopeBenchmarkSuiteSlugsByWorkspace do
  use Ecto.Migration

  # Tenant-created suites (observability benchmark draft materialization,
  # benchmark tenancy follow-up to #259) are per-workspace: two tenants may
  # independently derive the same suite_slug from their benchmark hints, so
  # slug uniqueness moves from global to (workspace_id, slug).
  #
  # Platform rows (workspace_id NULL) are distinct from every tenant row under
  # the composite index; a partial index enforces platform slug uniqueness.
  # A plain slug index is kept for the unscoped
  # platform-content lookups (get_suite_by_slug, CLI).
  def change do
    drop index(:benchmark_suites, [:slug])
    create unique_index(:benchmark_suites, [:workspace_id, :slug])

    create unique_index(:benchmark_suites, [:slug],
             where: "workspace_id IS NULL",
             name: :benchmark_suites_platform_slug_index
           )

    create index(:benchmark_suites, [:slug])
  end
end
