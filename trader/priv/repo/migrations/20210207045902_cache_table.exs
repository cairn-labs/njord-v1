defmodule Trader.Repo.Migrations.CacheTable do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE data_cache (
      key TEXT NOT NULL,
      ts TIMESTAMPTZ NOT NULL DEFAULT (now() at time zone 'utc'),
      data JSONB NOT NULL
    )
    """

    execute """
    CREATE UNIQUE INDEX ON data_cache(key);
    """
  end

  def down do
    execute "DROP TABLE data_cache;"
  end
end
