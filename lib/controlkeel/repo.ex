defmodule ControlKeel.Repo do
  use Ecto.Repo,
    otp_app: :controlkeel,
    adapter: Ecto.Adapters.SQLite3
end
