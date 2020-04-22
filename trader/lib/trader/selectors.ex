defmodule Trader.Selectors do
  def from_data_point(%DataPoint{
        data_point_type: :L2_ORDER_BOOK,
        l2_order_book: %L2OrderBook{
          product: %CurrencyPair{
            base: base,
            counter: counter
          }
        }
      }) do
    "#{Atom.to_string(base)}-#{Atom.to_string(counter)}"
  end

  def from_data_point(_), do: nil

  def from_feature_config(%FeatureConfig{
        data_point_type: :L2_ORDER_BOOK,
        l2_order_book_config: %L2OrderBookConfig{
          product: %CurrencyPair{
            base: base,
            counter: counter
          }
        }
      }) do
    "#{Atom.to_string(base)}-#{Atom.to_string(counter)}"
  end

  def from_feature_config(_), do: nil
end
