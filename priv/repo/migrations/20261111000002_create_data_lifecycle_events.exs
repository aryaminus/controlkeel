defmodule ControlKeel.Repo.Migrations.CreateDataLifecycleEvents do
  @moduledoc """
  Audit record of erasure actions (docs/dsar-erasure-plan.md, 1d).

  `DataLifecycle.delete_user/1` and `delete_org/1` previously wrote no durable
  record of the erasure itself — "who requested erasure of org X and when" was
  unanswerable. The existing audit tables are row-scoped (reviews, findings,
  service accounts), so erasure events get their own small table:

    - `event_type` — "user_erased" | "org_erased"
    - `subject`    — the erased user's pseudonymous marker
                     ("erased-user-…"), or the erased org's id as a string
    - `details`    — deletion stats captured at erase time

  Rows are inserted inside the erasure transactions, so a failed erase leaves
  no event. No FKs: the subjects are deleted or pseudonymized on purpose.
  Works on SQLite and Postgres (`:map` defaults follow the `orgs.settings`
  precedent from `20260524060847`).
  """

  use Ecto.Migration

  def change do
    create table(:data_lifecycle_events) do
      add :event_type, :string, null: false
      add :subject, :string, null: false
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:data_lifecycle_events, [:event_type])
  end
end
