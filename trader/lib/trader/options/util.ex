defmodule Trader.Options.Util do
  def parse_strike(symbol) do
    int =
      symbol
      |> String.slice(-8..-1)
      |> String.to_integer
    int * 0.001
  end
end
