defmodule ControlKeel.Repo.Migrations.CreateInvocations do
  use Ecto.Migration

  def change do
    create table(:invocations) do
      add :source, :string, null: false
      add :tool, :string, null: false
      add :provider, :string
      add :model, :string
      add :input_tokens, :integer, null: false, default: 0
      add :cached_input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :estimated_cost_cents, :integer, null: false, default: 0
      add :decision, :string, null: false
      add :metadata, :map, null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:invocations, [:session_id])
    create index(:invocations, [:task_id])
    create index(:invocations, [:inserted_at])
    create index(:invocations, [:provider, :model])
  end
end
