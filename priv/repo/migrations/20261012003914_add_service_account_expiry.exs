defmodule ControlKeel.Repo.Local.Migrations.AddServiceAccountExpiry do
  use Ecto.Migration

  def change do
    alter table(:service_accounts) do
      add :expires_at, :utc_datetime
      add :rotated_at, :utc_datetime
    end
  end
end
