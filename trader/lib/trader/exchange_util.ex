defmodule Trader.ExchangeUtil do
  require Logger

  def print_positions(title, %ExchangePositions{holdings: holdings, orders: orders}) do
    holdings_description =
      holdings
      |> Enum.map(fn %ProductHolding{amount: amount, product: %Product{product_name: name}} ->
        String.pad_trailing(name, 10) <> amount
      end)
      |> Enum.join("\n")

    orders_description =
      orders
      |> Enum.map(&describe_order/1)
      |> Enum.join("\n")

    IO.puts(Enum.join([title, holdings_description, orders_description], "\n") <> "\n")
  end

  def describe_order(%Order{
        order_type: :MARKET_BUY,
        buy_product: %Product{product_name: product},
        amount: amount
      }) do
    "MARKET BUY: #{amount} #{product}"
  end

  def describe_order(%Order{
        order_type: :MARKET_SELL,
        sell_product: %Product{product_name: product},
        amount: amount
      }) do
    "MARKET SELL: #{amount} #{product}"
  end

  def describe_order(%Order{
        order_type: :CANCEL_ORDER,
        target_order_id: target
      }) do
    "CANCEL ORDER: #{target}"
  end
end
