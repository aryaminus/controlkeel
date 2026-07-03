defmodule ControlKeel.Repo.Migrations.AddActorMetadataToReviewAuditEvents do
  use Ecto.Migration

  # SQLite has no `ADD COLUMN IF NOT EXISTS`, so guard each column against the
  # adapter's live column metadata. Re-running this migration against a
  # partial/stale DB (or under concurrent boots) otherwise crashes app boot with
  # "duplicate column name: actor_source".
  @table :review_audit_events

  def up do
    existing = columns(@table)

    alter table(@table) do
      unless MapSet.member?(existing, "actor_source"),
        do: add(:actor_source, :string)

      unless MapSet.member?(existing, "actor_identifier"),
        do: add(:actor_identifier, :string)
    end
  end

  def down do
    alter table(@table) do
      remove_if_exists(:actor_source, :string)
      remove_if_exists(:actor_identifier, :string)
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
