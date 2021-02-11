defmodule Mix.Tasks.Trader.Backtest do
  require Logger
  alias Trader.Runners.BacktestRunner

  def run([start_timestamp, end_timestamp, strategies_dir]) do
    {:ok, _} = Application.ensure_all_started(:trader)

    Logger.info("Running backtest from #{start_timestamp} to #{end_timestamp}...")

    BacktestRunner.load(strategies_dir)
    BacktestRunner.set_positions(%{"SPY" => 1000})
    BacktestRunner.run(start_timestamp, end_timestamp)
  end
end
