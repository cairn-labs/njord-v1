defmodule Trader.Frames.LabelExtraction do
  alias Trader.Db
  alias Trader.PriceUtil
  require Logger

  def get_label(
        label_timestamp,
        %LabelConfig{label_type: :FX_RATE, fx_rate_config: config} = label_config
      ) do
    selector = Trader.Selectors.from_label_config(label_config)

    case Db.DataPoints.get_data_at_time(label_timestamp, :L2_ORDER_BOOK, selector) do
      %DataPoint{data_point_type: :L2_ORDER_BOOK, l2_order_book: order_book, event_timestamp: ts} ->
        Label.new(event_timestamp: ts, value_decimal: PriceUtil.price_from_order_book(order_book))

      _ ->
        nil
    end
  end

  def label_to_direction(:FX_RATE, "1"), do: :up
  def label_to_direction(:FX_RATE, "0"), do: :flat
  def label_to_direction(:FX_RATE, "-1"), do: :down
end
