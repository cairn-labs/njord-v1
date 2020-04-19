defmodule Trader.Repo.Migrations.CreateDataTable do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE data (
      time TIMESTAMPTZ NOT NULL,
      data_type TEXT NOT NULL,
      contents JSONB NOT NULL DEFAULT '{}'
    );
    """

    execute """
    SELECT create_hypertable('data', 'time');
    """
  end
end
