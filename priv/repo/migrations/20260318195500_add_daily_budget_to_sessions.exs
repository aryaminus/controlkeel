defmodule ControlKeel.Repo.Migrations.AddDailyBudgetToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :daily_budget_cents, :integer, null: false, default: 0
    end

    execute("UPDATE sessions SET daily_budget_cents = budget_cents WHERE daily_budget_cents = 0")
  end
end
