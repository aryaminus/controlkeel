defmodule ControlKeel.Repo.Migrations.AddProxyTokenToSessions do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      add :proxy_token, :string
    end

    execute("""
    UPDATE sessions
    SET proxy_token = lower(hex(randomblob(24)))
    WHERE proxy_token IS NULL
    """)

    create unique_index(:sessions, [:proxy_token])
  end

  def down do
    drop_if_exists unique_index(:sessions, [:proxy_token])

    alter table(:sessions) do
      remove :proxy_token
    end
  end
end
