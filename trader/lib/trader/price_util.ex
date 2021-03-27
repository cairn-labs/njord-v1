defmodule Trader.PriceUtil do
  alias Decimal, as: D

  def price_from_data_point(%DataPoint{data_point_type: :L2_ORDER_BOOK, l2_order_book: book}) do
    price_from_order_book(book)
  end

  def price_from_data_point(%DataPoint{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: %StonkAggregate{vwap: vwap}
      })
      when vwap != 0 do
    vwap
  end

  def price_from_data_point(%DataPoint{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: %StonkAggregate{open_price: o, close_price: c}
      })
      when o == 0 do
    c
  end

  def price_from_data_point(%DataPoint{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: %StonkAggregate{open_price: o, close_price: c}
      })
      when c == 0 do
    o
  end

  def price_from_data_point(%DataPoint{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: %StonkAggregate{open_price: o, close_price: c}
      }) do
    0.5 * (o + c)
  end

  def price_from_data_point(_) do
    nil
  end

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

  def as_float(f) when is_float(f) or is_integer(f) do
    f
  end

  def as_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      _ -> nil
    end
  end

  def clip(value, min, nil) when value > min, do: value
  def clip(value, min, nil) when value <= min, do: min
  def clip(value, nil, max) when value < max, do: value
  def clip(value, nil, max) when value >= max, do: max
  def clip(value, min, max) when value < min, do: min
  def clip(value, min, max) when value > max, do: max
  def clip(value, _min, _max), do: value
end
