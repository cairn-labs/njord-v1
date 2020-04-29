defmodule Trader.PriceUtil do
  alias Decimal, as: D

  def price_from_order_book(%L2OrderBook{
        asks: [%L2OrderBookEntry{price: best_ask_str} | _],
        bids: [%L2OrderBookEntry{price: best_bid_str} | _]
      }) do
    best_ask = D.new(best_ask_str)
    best_bid = D.new(best_bid_str)

    best_ask
    |> D.add(best_bid)
    |> D.div(2)
    |> to_string
  end

  def price_from_order_book(%L2OrderBook{}), do: nil

  def as_float(nil), do: nil

  def as_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      _ -> nil
    end
  end
end
