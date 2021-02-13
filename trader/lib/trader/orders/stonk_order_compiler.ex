defmodule Trader.Orders.StonkOrderCompiler do
  @moduledoc """
  Takes current positions, current prices, and a set of predictions and
  generates orders. This will be more complex in the future, but currently
  does the following:

  1. Issue market sell orders for all shares for all holdings with
     predictions < -X% of current price - done!
  2. Check to see if there is at least one prediction for > +X% of market
     price. If not, exit.
  3. Issue market sell orders for all shares for all holdings with no
     predictions
  4. After fill of the above sell orders, select all predictions for > +X% of
     market price and allocate capital weighted by % difference
     from market price. Issue market buy orders.
  """
  alias Trader.PriceUtil
  require Logger

  @minimum_down_percentage_to_sell -0.025
  @minimum_up_percentage_to_buy 0.025

  def get_orders(
        %ExchangePositions{} = current_positions,
        prices,
        %Prediction{labels: labels} = prediction
      ) do
    down_prediction_sell_orders =
      get_down_prediction_sell_orders(current_positions, prices, labels)

    OrderTree.new(orders: down_prediction_sell_orders)
  end

  defp get_down_prediction_sell_orders(
         %ExchangePositions{} = current_positions,
         prices,
         labels
       ) do
    labels
    |> Enum.map(fn label ->
      {label.label_config.stonk_price_config.ticker, PriceUtil.as_float(label.value_decimal)}
    end)
    |> Enum.map(fn {ticker, predicted_price} ->
      {ticker, predicted_price, Map.get(prices, ticker)}
    end)
    |> Enum.filter(fn
      {_, _, 0} -> false
      {_, _, nil} -> false
      _ -> true
    end)
    |> Enum.filter(fn {_, predicted, current} ->
      (predicted - current) / current < @minimum_down_percentage_to_sell
    end)
    |> Enum.map(fn {ticker, _, _} -> ticker end)
    |> Enum.into(MapSet.new())
    |> sell_all(current_positions)
  end

  defp sell_all(
         tickers,
         %ExchangePositions{holdings: holdings, orders: orders} = current_positions
       ) do
    # First cancel all existing orders involving these tickers
    cancellations =
      orders
      |> Enum.filter(fn
        %Order{status: :PLACED, buy_product: b, sell_product: s} -> b in tickers or s in tickers
        _ -> false
      end)
      |> Enum.map(fn %Order{id: order_id} ->
        Order.new(
          id: UUID.uuid4(),
          order_type: :CANCEL_ORDER,
          status: :DRAFT,
          target_order_id: order_id
        )
      end)

    cancellation_ids = for %Order{id: i} <- cancellations, do: i

    # Now add market sell orders dependent on these cancellations
    sells =
      holdings
      |> Enum.filter(fn %ProductHolding{product: %Product{product_name: t}} -> t in tickers end)
      |> Enum.map(fn %ProductHolding{product: %Product{product_name: name}, amount: amount_str} ->
        Order.new(
          id: UUID.uuid4(),
          order_type: :MARKET_SELL,
          amount: amount_str,
          sell_product:
            Product.new(
              product_type: :STONK,
              product_name: name
            ),
          status: :DRAFT,
          parent_order_ids: cancellation_ids
        )
      end)

    cancellations ++ sells
  end
end
