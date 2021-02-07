defmodule Mix.Tasks.Trader.GetHistoricalData do
  require Logger

  def run(_argv) do
    {:ok, _} = Application.ensure_all_started(:trader)
    Logger.info("Working!")
  end
end
