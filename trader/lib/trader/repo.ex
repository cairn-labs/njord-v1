defmodule Trader.Repo do
  use Ecto.Repo,
    otp_app: :trader,
    adapter: Ecto.Adapters.Postgres
end
