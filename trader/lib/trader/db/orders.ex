defmodule Trader.Db.Orders do
  alias Trader.Repo
  alias Ecto.Adapters.SQL
  require Logger

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

  def orders_by_strategy(strategy_name, start_datetime, end_datetime, environment \\ "live") do
    query = """
    SELECT data FROM orders WHERE strategy = $1 AND time >= $2 AND time <= $3 AND environment = $4
    ORDER BY time ASC
    """

    {:ok, %{rows: rows}} =
      SQL.query(Repo, query, [strategy_name, start_datetime, end_datetime, environment])

    for [data] <- rows do
      Order.decode(data)
    end
  end
end
