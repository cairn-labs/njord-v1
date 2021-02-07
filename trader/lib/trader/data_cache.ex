defmodule Trader.DataCache do
  alias Trader.Repo
  alias Ecto.Adapters.SQL
  require Logger

  def cached(key, ttl_seconds, function) do
    case SQL.query(Repo, "SELECT ts, data FROM data_cache WHERE key = $1", [key]) do
      {:ok, %{rows: [[ts, data]]}} ->
        if DateTime.diff(DateTime.utc_now(), ts) > ttl_seconds do
          update_cache(key, function)
        else
          Logger.debug("Cached value found for #{key} from #{inspect(ts)}")
          data
        end

      _ ->
        update_cache(key, function)
    end
  end

  defp update_cache(key, function) do
    Logger.debug("Cached value for #{key} not found, computing...")
    data = function.()
    {:ok, _} = SQL.query(Repo, """
      INSERT INTO data_cache (key, ts, data)
      VALUES ($1, $2, $3)
      ON CONFLICT (key) DO UPDATE SET ts = EXCLUDED.ts, data = EXCLUDED.data
    """, [key, DateTime.utc_now(), data])
    data
  end
end
