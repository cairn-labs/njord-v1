defmodule Mix.Tasks.Trader.GetHistoricalData do
  require Logger

  def run([mode | argv]) do
    {:ok, _} = Application.ensure_all_started(:trader)

    case mode do
      "stonks" ->
        download_stonk_data(argv)

      "reddit" ->
        download_reddit_data(argv)
    end
  end

  def download_stonk_data([ticker, start_date, end_date, window_length_minutes]) do
    Trader.Polygon.StockAggregateCollector.download_range(
      ticker,
      start_date,
      end_date,
      String.to_integer(window_length_minutes)
    )
  end

  def download_reddit_data(_argv) do
    raise "Not implemented yet"
  end
end
