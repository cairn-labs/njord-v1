defmodule Mix.Tasks.Trader.GetHistoricalData do
  require Logger

  def run(_argv) do
    {:ok, _} = Application.ensure_all_started(:trader)
    Trader.Polygon.StockAggregateCollector.download_range(
      "AAPL", "2021-01-11", "2021-02-15", 120
    )
    |> inspect
    |> Logger.info
  end
end
