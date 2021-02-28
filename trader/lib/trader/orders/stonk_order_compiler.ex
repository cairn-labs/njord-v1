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

  # When setting up a buy order that is contingent on a pending sell order,
  # assume that the sell order will fill within this percentage of current
  # market price, for the purposes of allocating capital.
  @sell_order_assumed_liquidity 0.95

  def get_orders(
        strategy,
        %ExchangePositions{} = current_positions,
        prices,
        %Prediction{labels: labels} = prediction
      ) do
    down_prediction_sell_orders =
      get_down_prediction_sell_orders(current_positions, prices, labels)

    if not any_up_predictions?(prices, labels) do
      OrderTree.new(orders: down_prediction_sell_orders)
    else
      no_prediction_sell_orders = get_no_prediction_sell_orders(current_positions, prices, labels)

      buy_orders =
        get_buy_orders(
          current_positions,
          prices,
          labels,
          down_prediction_sell_orders ++ no_prediction_sell_orders,
          strategy
        )

      OrderTree.new(
        orders: down_prediction_sell_orders ++ no_prediction_sell_orders ++ buy_orders
      )
    end
  end

  defp get_down_prediction_sell_orders(
         %ExchangePositions{} = current_positions,
         prices,
         labels
       ) do
    label_deltas(prices, labels)
    |> Enum.filter(fn {_, delta} -> delta < @minimum_down_percentage_to_sell end)
    |> Enum.map(fn {ticker, _} -> ticker end)
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
      |> remove_zero_orders

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
      |> remove_zero_orders

    cancellations ++ sells
  end

  def any_up_predictions?(prices, labels) do
    case Enum.filter(
           label_deltas(prices, labels),
           fn {_, delta} -> delta >= @minimum_up_percentage_to_buy end
         ) do
      [] -> false
      _ -> true
    end
  end

  def label_deltas(prices, labels) do
    labels
    |> Enum.map(fn label ->
      {label.label_config.stonk_price_config.ticker, PriceUtil.as_float(label.value_decimal),
       label.label_config.label_options}
    end)
    |> Enum.map(fn {ticker, predicted_value, label_options} ->
      {ticker, predicted_value, label_options, Map.get(prices, ticker)}
    end)
    |> Enum.filter(fn
      {_, _, _, 0} -> false
      {_, _, _, nil} -> false
      _ -> true
    end)
    |> Enum.map(fn
      {ticker, predicted, :ABSOLUTE_VALUE, current} ->
        {ticker, (predicted - current) / current}

      {ticker, predicted, :RELATIVE_VALUE, current} ->
        {ticker, predicted}
    end)
    |> Enum.into(%{})
  end

  def get_no_prediction_sell_orders(current_positions, prices, labels) do
    tickers_to_ignore =
      label_deltas(prices, labels)
      |> Enum.filter(fn {_, delta} ->
        delta < @minimum_down_percentage_to_sell or delta >= @minimum_up_percentage_to_buy
      end)
      |> Enum.map(fn {ticker, _} -> ticker end)
      |> Enum.into(MapSet.new())

    holdings_to_sell =
      current_positions.holdings
      |> Enum.filter(fn
        %ProductHolding{product: %Product{product_type: :STONK, product_name: t}} ->
          t not in tickers_to_ignore

        _ ->
          false
      end)
      |> Enum.map(fn %ProductHolding{product: %Product{product_name: t}} -> t end)

    orders_to_cancel =
      current_positions.orders
      |> Enum.filter(fn
        %Order{status: :PLACED, buy_product: b, sell_product: s} ->
          not (b in tickers_to_ignore or s in tickers_to_ignore)

        _ ->
          false
      end)
      |> Enum.flat_map(fn %Order{status: :PLACED, buy_product: b, sell_product: s} -> [b, s] end)

    (holdings_to_sell ++ orders_to_cancel)
    |> Enum.into(MapSet.new())
    |> sell_all(current_positions)
  end

  def get_buy_orders(
        %ExchangePositions{holdings: holdings, orders: orders} = current_positions,
        prices,
        labels,
        draft_sell_orders,
        strategy
      ) do
    cash_holding =
      Enum.find(
        holdings,
        fn
          %ProductHolding{product: %Product{product_type: :CURRENCY, product_name: "USD"}} -> true
          _ -> false
        end
      )

    available_cash =
      case cash_holding do
        %ProductHolding{amount: amount_str} -> PriceUtil.as_float(amount_str)
        _ -> 0
      end

    pending_sell_amount =
      draft_sell_orders
      |> Enum.map(fn order -> get_order_presumed_liquidity(order, prices) end)
      |> Enum.sum()

    buy_ticker_deltas =
      label_deltas(prices, labels)
      |> Enum.filter(fn {_, delta} -> delta > @minimum_up_percentage_to_buy end)

    total_weight = buy_ticker_deltas |> Enum.map(fn {_, delta} -> delta end) |> Enum.sum()

    sell_order_ids = for %Order{id: i} <- draft_sell_orders, do: i

    buy_ticker_deltas
    |> Enum.map(fn {ticker, delta} ->
      {ticker,
       floor(
         (available_cash + pending_sell_amount) * delta / total_weight / Map.get(prices, ticker)
       )}
    end)
    |> Enum.map(fn {ticker, amount_to_buy} ->
      create_buy_order(ticker, amount_to_buy, sell_order_ids, Map.get(prices, ticker), strategy)
    end)
    |> remove_zero_orders
  end

  defp create_buy_order(ticker, amount_to_buy, parent_order_ids, current_price, strategy) do
    Order.new(
      id: UUID.uuid4(),
      order_type: :MARKET_BUY,
      amount: "#{amount_to_buy}",
      buy_product:
        Product.new(
          product_type: :STONK,
          product_name: ticker
        ),
      status: :DRAFT,
      parent_order_ids: parent_order_ids,
      take_profit_percent: strategy.take_profit_percent,
      stop_loss_percent: strategy.stop_loss_percent
    )
  end

  defp get_order_presumed_liquidity(
         %Order{
           order_type: :MARKET_SELL,
           sell_product: %Product{product_name: ticker},
           amount: amount_str
         },
         prices
       ) do
    @sell_order_assumed_liquidity * Map.get(prices, ticker, 0) * PriceUtil.as_float(amount_str)
  end

  defp get_order_presumed_liquidity(
         %Order{
           order_type: :LIMIT_SELL,
           sell_product: %Product{product_name: ticker},
           price: price_str,
           amount: amount_str
         },
         prices
       ) do
    PriceUtil.as_float(price_str) * PriceUtil.as_float(amount_str)
  end

  defp get_order_presumed_liquidity(_, _) do
    0
  end

  def remove_zero_orders(orders) do
    orders
    |> Enum.filter(fn
      %Order{amount: "0"} -> false
      %Order{amount: "0.0"} -> false
      _ -> true
    end)
  end
end
