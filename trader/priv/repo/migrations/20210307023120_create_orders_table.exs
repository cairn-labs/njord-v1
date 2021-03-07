defmodule Trader.Repo.Migrations.CreateOrdersTable do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE orders (
      time TIMESTAMPTZ NOT NULL,
      strategy TEXT,
      environment TEXT,
      data BYTEA
    );
    """

    execute "CREATE INDEX orders_strategy_idx ON orders (strategy);"
    execute "CREATE INDEX orders_time_idx ON orders (time);"
  end

  def down do
    execute """
    DROP TABLE orders;
    """
  end
end
