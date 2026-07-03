defmodule ControlKeel.Repo.Migrations.AddDecisionLinksToSessionEvents do
  use Ecto.Migration

  # Only add the reference columns that are actually missing, and create the
  # indexes with IF NOT EXISTS, so a partial/stale DB or concurrent boots cannot
  # crash the application during migration.
  @table :session_events

  def up do
    existing = columns(@table)

    alter table(@table) do
      unless MapSet.member?(existing, "review_id"),
        do: add(:review_id, references(:reviews, on_delete: :nilify_all))

      unless MapSet.member?(existing, "finding_id"),
        do: add(:finding_id, references(:findings, on_delete: :nilify_all))
    end

    create_if_not_exists index(@table, [:review_id, :inserted_at])
    create_if_not_exists index(@table, [:finding_id, :inserted_at])
  end

  def down do
    drop_if_exists index(@table, [:review_id, :inserted_at])
    drop_if_exists index(@table, [:finding_id, :inserted_at])

    alter table(@table) do
      remove_if_exists(:review_id, references(:reviews, on_delete: :nilify_all))
      remove_if_exists(:finding_id, references(:findings, on_delete: :nilify_all))
    end
  end

  defp columns(table) do
    table = to_string(table)

    rows =
      if sqlite_repo?() do
        %{rows: rows} = repo().query!("PRAGMA table_info(\"#{table}\")")
        Enum.map(rows, fn [_cid, name | _] -> name end)
      else
        %{rows: rows} =
          repo().query!(
            "SELECT column_name FROM information_schema.columns WHERE table_name = $1",
            [table]
          )

        Enum.map(rows, fn [name] -> name end)
      end

    MapSet.new(rows)
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
