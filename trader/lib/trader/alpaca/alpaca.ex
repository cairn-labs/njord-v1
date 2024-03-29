defmodule Trader.Alpaca.Alpaca do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.PriceUtil
  alias Trader.Alpaca.AlpacaApi, as: Api

  @initial_delay_ms 1_000

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      {:ok, pid} = GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
      Process.send_after(pid, :tick, @initial_delay_ms)
      {:ok, pid}
    else
      :ignore
    end
  end

  def execute_order_tree(%OrderTree{} = order_tree, strategy_name) do
    GenServer.call(__MODULE__, {:execute_order_tree, order_tree, strategy_name})
  end

  def current_price(ticker) do
    Api.call(:data, :GET, "v1/last/stocks/#{ticker}")
    |> Api.parse_response()
    |> Map.get("last", %{})
    |> Map.get("price", nil)
  end

  def active_strategies() do
    GenServer.call(__MODULE__, :active_strategies)
  end

  def current_positions() do
    stonks =
      Api.call(:trading, :GET, "v2/positions", retry: true)
      |> Api.parse_response()
      |> Enum.filter(fn
        %{"side" => "long", "asset_class" => "us_equity"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"symbol" => ticker, "qty" => qty} ->
        ProductHolding.new(
          product:
            Product.new(
              product_type: :STONK,
              product_name: ticker
            ),
          amount: qty
        )
      end)

    cash_amount =
      Api.call(:trading, :GET, "v2/account")
      |> Api.parse_response()
      |> Map.get("cash")

    holdings = [
      ProductHolding.new(
        product:
          Product.new(
            product_type: :CURRENCY,
            product_name: "USD"
          ),
        amount: cash_amount
      )
      | stonks
    ]

    orders =
      Api.call(:trading, :GET, "v2/orders?status=open", retry: true)
      |> Api.parse_response()
      |> Enum.flat_map(&parse_order_from_exchange/1)

    ExchangePositions.new(holdings: holdings, orders: orders)
  end

  def current_positions(strategy_name) do
    GenServer.call(__MODULE__, {:get_strategy_positions, strategy_name})
  end

  def get_calendar() do
    Api.call(
      :trading,
      :GET,
      "v2/calendar"
    )
    |> Api.parse_response()
    |> Enum.map(fn %{"date" => date, "open" => open, "close" => close} ->
      {date, %{"o" => open, "c" => close}}
    end)
    |> Enum.into(%{})
  end

  def order_request_object(
        %Order{
          id: order_id,
          order_type: :MARKET_SELL,
          sell_product:
            %Product{
              product_name: ticker
            } = product,
          amount: amount_str
        } = order
      ) do
    %{
      symbol: ticker,
      qty: amount_str,
      side: "sell",
      type: "market",
      time_in_force: "gtc",
      client_order_id: order_id
    }
  end

  def order_request_object(
        %Order{
          id: order_id,
          order_type: :TRAILING_STOP_SELL,
          trail_percent: trail_percent_str,
          sell_product:
            %Product{
              product_name: ticker
            } = product,
          amount: amount_str
        } = order
      ) do
    %{
      symbol: ticker,
      qty: amount_str,
      side: "sell",
      type: "trailing_stop",
      time_in_force: "gtc",
      trail_percent: "#{PriceUtil.as_float(trail_percent_str) * 100}",
      client_order_id: order_id
    }
  end

  def order_request_object(
        %Order{
          id: order_id,
          order_type: :MARKET_BUY,
          buy_product:
            %Product{
              product_name: ticker
            } = product,
          amount: amount_str,
          take_profit_price: take_profit_price,
          stop_loss_price: stop_loss_price
        } = order
      ) do
    order = %{
      symbol: ticker,
      qty: amount_str,
      side: "buy",
      type: "market",
      time_in_force: "gtc",
      client_order_id: order_id
    }

    order =
      if take_profit_price != 0 do
        Map.put(order, :take_profit, %{limit_price: take_profit_price})
      else
        order
      end

    order =
      if stop_loss_price != 0 do
        Map.put(order, :stop_loss, %{stop_price: stop_loss_price})
      else
        order
      end

    order
  end

  def order_request_object(%Order{
        order_type: :CANCEL_ORDER,
        target_order_id: target,
        id: id
      }) do
    %{
      type: "cancel_order",
      target: target,
      client_order_id: id
    }
  end

  defp submit_order_request(%{type: "cancel_order", target: target_order_id, client_order_id: id}) do
    Logger.info("Order #{id}: Cancelling existing order #{target_order_id}")

    case Api.call(
           :trading,
           :GET,
           "v2/orders:by_client_order_id?client_order_id=#{target_order_id}"
         )
         |> Api.parse_response() do
      %{"id" => id} ->
        case Api.call(:trading, :DELETE, "v2/orders/#{id}") do
          %HTTPoison.Response{status_code: 204} ->
            :ok

          other ->
            Logger.warn("Order rejected: #{inspect(other)}")
            :error
        end

      _ ->
        Logger.warn("Attempted to cancel order #{target_order_id} that could not be found")
    end
  end

  defp submit_order_request(object) do
    Logger.info(
      "Placing #{object[:type]} #{object[:side]} order for #{object[:qty]} #{object[:symbol]}"
    )

    case Api.call(:trading, :POST, "v2/orders", object, retry: false) do
      %HTTPoison.Response{status_code: 200} ->
        :ok

      other ->
        Logger.warn("Order rejected: #{inspect(other)}")
        :error
    end
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    Logger.info("Cancelling all existing orders on Alpaca. Allocating initial positions:")
    %HTTPoison.Response{status_code: 207} = Api.call(:trading, :DELETE, "v2/orders", retry: true)
    exchange_positions = %ExchangePositions{holdings: holdings} = current_positions()
    strategy_positions = allocate_holdings_to_active_strategies(holdings)

    Trader.ExchangeUtil.print_positions("Exchange positions:", exchange_positions)

    for {name, positions} <- strategy_positions do
      Trader.ExchangeUtil.print_positions("Strategy #{name}:", positions)
    end

    {:ok,
     %{
       pending_orders: [],
       placed_orders: [],
       filled_orders: [],
       strategy_positions: strategy_positions
     }}
  end

  def handle_info(
        :tick,
        %{
          pending_orders: pending_orders,
          placed_orders: placed_orders,
          filled_orders: filled_orders,
          strategy_positions: strategy_positions
        } = state
      ) do
    all_exchange_orders =
      Api.call(:trading, :GET, "v2/orders?status=all", retry: true)
      |> Api.parse_response()

    exchange_filled_prices =
      all_exchange_orders
      |> Enum.filter(fn
        %{"status" => "filled"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"client_order_id" => id, "filled_avg_price" => price} -> {id, price} end)
      |> Enum.into(%{})

    canceled_ids =
      all_exchange_orders
      |> Enum.filter(fn
        %{"status" => "canceled"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"client_order_id" => id} -> id end)
      |> Enum.into(MapSet.new())

    # The exchange doesn't keep track of CANCEL_ORDER orders,
    # so add them here if their target order has indeed been canceled

    filled_ids =
      placed_orders
      |> Enum.filter(fn
        %Order{order_type: :CANCEL_ORDER} -> true
        _ -> false
      end)
      |> Enum.filter(fn %Order{target_order_id: target} -> target in canceled_ids end)
      |> Enum.map(fn %Order{id: id} -> id end)
      |> Enum.into(exchange_filled_prices |> Map.keys() |> MapSet.new())

    {can_run, still_pending} =
      pending_orders
      |> Enum.split_with(fn %Order{parent_order_ids: parents} ->
        MapSet.size(MapSet.difference(MapSet.new(parents), filled_ids)) == 0
      end)

    [accepted, rejected] =
      can_run
      |> Enum.map(fn o -> {o, submit_order_request(order_request_object(o))} end)
      |> Enum.split_with(fn
        {_, :ok} -> true
        {_, :error} -> false
      end)
      |> Tuple.to_list()
      |> Enum.map(fn os -> Enum.map(os, fn {o, _} -> o end) end)

    accepted = mark_orders_as(accepted, :PLACED)

    new_strategy_positions =
      update_strategy_positions(
        strategy_positions,
        accepted,
        filled_ids,
        canceled_ids,
        exchange_filled_prices
      )

    {now_filled, still_placed} =
      placed_orders
      |> Enum.split_with(fn %Order{id: id} -> id in filled_ids end)

    now_filled =
      now_filled
      |> mark_orders_as(:FILLED)
      |> set_orders_price(exchange_filled_prices)

    log_filled_orders(now_filled)

    pid = self()
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)

    {:noreply,
     %{
       state
       | pending_orders: remove_pending_with_rejected_parents(still_pending, rejected),
         placed_orders: still_placed ++ accepted,
         filled_orders: filled_orders ++ now_filled,
         strategy_positions: new_strategy_positions
     }}
  end

  def handle_call(
        {:execute_order_tree, %OrderTree{orders: orders}, strategy_name},
        _from,
        %{pending_orders: pending_orders} = state
      ) do
    tagged_orders =
      Enum.map(orders, fn order -> %Order{order | source_strategy: strategy_name} end)

    {:reply, :ok, %{state | pending_orders: pending_orders ++ tagged_orders}}
  end

  def handle_call(
        {:get_strategy_positions, strategy_name},
        _from,
        %{strategy_positions: strategy_positions} = state
      ) do
    {:reply, Map.get(strategy_positions, strategy_name), state}
  end

  def handle_call(:active_strategies, _from, %{strategy_positions: strategy_positions} = state) do
    {:reply, Map.keys(strategy_positions), state}
  end

  def update_strategy_positions(
        strategy_positions,
        placed_orders,
        filled_order_ids,
        canceled_order_ids,
        exchange_filled_prices
      ) do
    strategy_positions
    |> Enum.map(fn {strategy_name, positions} ->
      {strategy_name,
       update_strategy_position(
         strategy_name,
         positions,
         placed_orders,
         filled_order_ids,
         canceled_order_ids,
         exchange_filled_prices
       )}
    end)
    |> Enum.into(%{})
  end

  def update_strategy_position(
        strategy_name,
        %ExchangePositions{holdings: holdings, orders: orders} = old_positions,
        placed_orders,
        filled_order_ids,
        canceled_order_ids,
        exchange_filled_prices
      ) do
    new_orders =
      placed_orders
      |> Enum.filter(fn %Order{source_strategy: s} -> s == strategy_name end)

    new_positions = %ExchangePositions{
      holdings: update_holdings_from_filled_orders(holdings, orders, exchange_filled_prices),
      orders:
        Enum.filter(orders ++ new_orders, fn %Order{id: id} ->
          id not in filled_order_ids and id not in canceled_order_ids
        end)
    }

    if new_positions != old_positions do
      Trader.ExchangeUtil.print_positions(
        "New positions for strategy #{strategy_name}:",
        new_positions
      )
    end

    new_positions
  end

  def update_holdings_from_filled_orders(holdings, orders, exchange_filled_prices) do
    filled_order_values =
      orders
      |> Enum.filter(fn %Order{id: id} -> Map.has_key?(exchange_filled_prices, id) end)
      |> Enum.map(fn %Order{id: id, amount: amt_str} = o ->
        {o, PriceUtil.as_float(Map.get(exchange_filled_prices, id)) * PriceUtil.as_float(amt_str)}
      end)

    cash_delta =
      filled_order_values
      |> Enum.map(fn
        {%Order{order_type: t}, value} when t == :MARKET_BUY or t == :LIMIT_BUY ->
          -1 * value

        {%Order{order_type: t}, value}
        when t == :MARKET_SELL or t == :LIMIT_SELL or t == :TRAILING_STOP_SELL ->
          value
      end)
      |> Enum.sum()

    updated_holdings =
      holdings
      |> Enum.map(fn
        %ProductHolding{
          amount: amount_str,
          product: %Product{product_type: :CURRENCY, product_name: "USD"}
        } = cash_holding ->
          %ProductHolding{
            cash_holding
            | amount: to_string(PriceUtil.as_float(amount_str) + cash_delta)
          }

        %ProductHolding{
          amount: amount_str,
          product: %Product{product_type: :STONK, product_name: ticker}
        } = stonk_holding ->
          added =
            filled_order_values
            |> Enum.map(fn
              {%Order{amount: amt_str, buy_product: %Product{product_name: ^ticker}}, _} ->
                PriceUtil.as_float(amt_str)

              _ ->
                0
            end)
            |> Enum.sum()

          subtracted =
            filled_order_values
            |> Enum.map(fn
              {%Order{amount: amt_str, sell_product: %Product{product_name: ^ticker}}, _} ->
                PriceUtil.as_float(amt_str)

              _ ->
                0
            end)
            |> Enum.sum()

          %ProductHolding{
            stonk_holding
            | amount: to_string(PriceUtil.as_float(amount_str) + added - subtracted)
          }
      end)

    # Now go through and add any holdings that weren't in the list already

    new_holdings =
      filled_order_values
      |> Enum.flat_map(fn
        {
          %Order{
            amount: amt_str,
            buy_product: %Product{product_name: ticker, product_type: :STONK}
          },
          _
        } ->
          [{ticker, PriceUtil.as_float(amt_str)}]

        {%Order{
           amount: amt_str,
           sell_product: %Product{product_name: ticker, product_type: :STONK}
         }, _} ->
          [{ticker, -1 * PriceUtil.as_float(amt_str)}]

        _ ->
          []
      end)
      |> Enum.group_by(fn {t, _} -> t end)
      |> Enum.map(fn {t, data} -> {t, data |> Enum.map(fn {t, amt} -> amt end) |> Enum.sum()} end)
      |> Enum.flat_map(fn {ticker, delta} ->
        case Enum.find(holdings, fn p ->
               p.product.product_type == :STONK and p.product.product_name == ticker
             end) do
          nil ->
            [
              ProductHolding.new(
                product: Product.new(product_type: :STONK, product_name: ticker),
                amount: to_string(delta)
              )
            ]

          _ ->
            []
        end
      end)

    (new_holdings ++ updated_holdings)
    |> Enum.filter(fn %ProductHolding{amount: amt_str} -> PriceUtil.as_float(amt_str) != 0 end)
  end

  def allocate_holdings_to_active_strategies(holdings) do
    for %TradingStrategy{name: strategy_name, capital_allocation: allocation} <-
          Trader.Strategies.active_strategies() do
      strategy_holdings =
        Enum.map(holdings, fn %ProductHolding{amount: qty} = holding ->
          %ProductHolding{holding | amount: "#{floor(PriceUtil.as_float(qty) * allocation)}"}
        end)

      {strategy_name, ExchangePositions.new(holdings: strategy_holdings)}
    end
    |> Enum.into(%{})
  end

  defp parse_order_from_exchange(%{
         "client_order_id" => id,
         "type" => "market",
         "symbol" => ticker,
         "side" => "sell",
         "qty" => amount_str
       }) do
    [
      Order.new(
        id: id,
        status: :PLACED,
        order_type: :MARKET_SELL,
        sell_product: Product.new(product_name: ticker, product_type: :STONK),
        amount: amount_str
      )
    ]
  end

  defp parse_order_from_exchange(%{
         "client_order_id" => id,
         "type" => "trailing_stop",
         "symbol" => ticker,
         "side" => "sell",
         "qty" => amount_str,
         "trail_percent" => trail_percent,
         "stop_price" => stop_price
       }) do
    [
      Order.new(
        id: id,
        status: :PLACED,
        order_type: :TRAILING_STOP_SELL,
        price: stop_price,
        trail_percent: trail_percent,
        sell_product: Product.new(product_name: ticker, product_type: :STONK),
        amount: amount_str
      )
    ]
  end

  defp parse_order_from_exchange(%{
         "client_order_id" => id,
         "type" => "market",
         "symbol" => ticker,
         "side" => "buy",
         "qty" => amount_str
       }) do
    [
      Order.new(
        id: id,
        order_type: :MARKET_BUY,
        status: :PLACED,
        buy_product: Product.new(product_name: ticker, product_type: :STONK),
        amount: amount_str
      )
    ]
  end

  defp parse_order_from_exchange(order_object) do
    Logger.warn("Received unknown order type from Alpaca; skipping: #{inspect(order_object)}")
    []
  end

  def remove_pending_with_rejected_parents(pending_orders, rejected_orders) do
    rejected_ids =
      rejected_orders
      |> Enum.map(fn %Order{id: id} -> id end)
      |> Enum.into(MapSet.new())

    pending_orders
    |> Enum.filter(fn %Order{parent_order_ids: parents} ->
      MapSet.size(MapSet.intersection(MapSet.new(parents), rejected_ids)) == 0
    end)
  end

  def mark_orders_as(orders, status) do
    orders
    |> Enum.map(fn order -> %Order{order | status: status} end)
  end

  def set_orders_price(orders, exchange_filled_prices) do
    orders
    |> Enum.map(fn order ->
      %Order{order | price: Map.get(exchange_filled_prices, order.id, "")}
    end)
  end

  defp log_filled_orders(orders) do
    environment = Application.get_env(:trader, __MODULE__)[:environment]

    for order <- orders do
      Db.Orders.log_order(order, environment)
    end
  end
end
