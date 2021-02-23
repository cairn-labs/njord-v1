defmodule Mix.Tasks.Trader.Backtest do
  require Logger
  alias Trader.Runners.BacktestRunner

  def run([start_timestamp, end_timestamp, strategy_proto]) do
    {:ok, _} = Application.ensure_all_started(:trader)
    Logger.configure(level: :info, format: "[$level] $message\n")
    Logger.info("Running backtest from #{start_timestamp} to #{end_timestamp}...")

    BacktestRunner.load(strategy_proto)
    BacktestRunner.set_positions(%{"AAPL" => 100, "USD" => 10000})
    BacktestRunner.run(start_timestamp, end_timestamp)
  end
end
