defmodule ControlKeel.Repo.Migrations.CreateOauthIdentities do
  use Ecto.Migration

  def change do
    create table(:oauth_identities) do
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      add :provider_email, :string, null: false
      add :provider_name, :string
      add :provider_avatar_url, :string
      add :provider_data, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_identities, [:provider, :provider_uid])
    create index(:oauth_identities, [:user_id])
    create index(:oauth_identities, [:provider_email])
  end
end
