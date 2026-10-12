defmodule ControlKeel.Repo.Migrations.CreateDeviceAuthorizations do
  use Ecto.Migration

  # RFC 8628 OAuth 2.0 Device Authorization Grant storage (issue #251).
  #
  # Both codes are stored as SHA-256 hashes, never plaintext: the device_code is
  # a bearer credential and the user_code is short/highly guessable, so neither
  # may sit in the database or a backup in the clear.
  def change do
    create table(:device_authorizations) do
      add :device_code_hash, :string, null: false
      add :user_code_hash, :string, null: false
      add :client_id, :string
      add :scope, :string, default: ""
      add :status, :string, null: false, default: "pending"
      add :user_id, references(:users, on_delete: :delete_all)
      add :last_polled_at, :utc_datetime
      add :poll_count, :integer, default: 0
      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime
      add :consumed_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :interval_seconds, :integer, null: false, default: 5
      add :verification_uri, :string
      add :client_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_authorizations, [:device_code_hash])
    create unique_index(:device_authorizations, [:user_code_hash])

    # Polling looks up by device_code_hash on every request.
    create index(:device_authorizations, [:device_code_hash, :status])
  end
end
