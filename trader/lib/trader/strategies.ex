defmodule Trader.Strategies do
  def all_strategies_by_allocation do
    active_strategies
    |> Enum.map(fn %TradingStrategy{name: name, capital_allocation: capital_allocation} ->
      {name, capital_allocation}
    end)
    |> Enum.into(%{})
  end

  def active_strategies do
    strategies =
      Application.app_dir(:trader, "priv")
      |> Path.join("active_strategies")
      |> Path.join("*.pb.txt")
      |> Path.wildcard()
      |> Enum.map(fn p ->
        Trader.ProtoUtil.parse_text_format(p, TradingStrategy, "trading_strategy.proto")
      end)

    check_strategies(strategies)
    strategies
  end

  defp check_strategies(strategies) do
    total_allocation =
      strategies
      |> Enum.map(fn %TradingStrategy{capital_allocation: c} -> c end)
      |> Enum.sum()

    if total_allocation > 1.0 do
      raise "Total capital allocation of all strategies must be at most 1"
    end
  end
end
