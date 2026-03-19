defmodule ControlKeel.CloudRepo do
  use Ecto.Repo,
    otp_app: :controlkeel,
    adapter: Ecto.Adapters.Postgres
end
