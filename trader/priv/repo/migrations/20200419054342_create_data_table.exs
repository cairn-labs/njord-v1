defmodule Trader.Repo.Migrations.CreateDataTable do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE data (
      time TIMESTAMPTZ NOT NULL,
      data_type SMALLINT,
      contents BYTEA
    );
    """

    execute """
    SELECT create_hypertable('data', 'time');
    """
  end

  def down do
    execute """
    DROP TABLE data;
    """
  end
end
