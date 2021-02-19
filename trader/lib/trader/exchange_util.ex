defmodule Trader.ExchangeUtil do
  require Logger

  def print_positions(title, %ExchangePositions{holdings: holdings, orders: orders}) do
    description =
      holdings
      |> Enum.map(fn %ProductHolding{amount: amount, product: %Product{product_name: name}} ->
        String.pad_trailing(name, 10) <> amount
      end)
      |> Enum.join("\n")

    IO.puts(title <> "\n" <> description <> "\n")
  end
end
