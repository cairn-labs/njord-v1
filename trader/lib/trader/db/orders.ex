defmodule Trader.Db.Orders do
  alias Trader.Repo
  alias Ecto.Adapters.SQL

  def log_order(%Order{source_strategy: strategy} = order, environment, timestamp \\ nil) do
    timestamp =
      case timestamp do
        nil -> DateTime.utc_now()
        t -> t
      end

    data = Order.encode(order)

    query = """
    INSERT INTO orders (time, strategy, environment, data) VALUES ($1, $2, $3, $4)
    """

    {:ok, _} = SQL.query(Repo, query, [timestamp, strategy, environment, data])
  end
end
