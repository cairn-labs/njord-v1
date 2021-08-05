defmodule Trader.Alpaca.MockAlpaca do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.PriceUtil

  @aggregate_width 20
  @genserver_timeout 30_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def setup(stock_amounts) do
    GenServer.call(__MODULE__, :reset)
    GenServer.call(__MODULE__, {:load_stocks, stock_amounts})
  end

  def current_positions(_strategy_name) do
    GenServer.call(__MODULE__, :current_positions)
  end

  def current_price(ticker) do
    GenServer.call(__MODULE__, {:current_price, ticker}, @genserver_timeout)
  end

  def set_timestamp(timestamp) do
    GenServer.call(__MODULE__, {:set_timestamp, timestamp})
  end

  def execute_order_tree(%OrderTree{orders: orders}, strategy_name) do
    # Need to toposort these orders into stages. For now, just submit
    # them sequentially.
    for order <- orders do
      submit_order(%Order{order | source_strategy: strategy_name})
    end
  end

  def submit_order(%Order{} = order) do
    GenServer.call(__MODULE__, {:submit_order, order}, @genserver_timeout)
  end

  def portfolio_value() do
    GenServer.call(__MODULE__, :portfolio_value, @genserver_timeout)
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    {:ok, %{positions: ExchangePositions.new()}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{positions: ExchangePositions.new(), timestamp: DateTime.from_unix!(0)}}
  end

  @impl true
  def handle_call({:load_stocks, stock_amounts}, _from, %{positions: positions} = state) do
    holdings =
      for {name, amount} <- Enum.to_list(stock_amounts) do
        case name do
          "USD" ->
            ProductHolding.new(
              product:
                Product.new(
                  product_type: :CURRENCY,
                  product_name: name
                ),
              amount: "#{amount}"
            )

          ticker ->
            ProductHolding.new(
              product:
                Product.new(
                  product_type: :STONK,
                  product_name: ticker
                ),
              amount: "#{amount}"
            )
        end
      end

    positions = %ExchangePositions{positions | holdings: holdings}
    {:reply, :ok, %{state | positions: positions}}
  end

  @impl true
  def handle_call(:current_positions, _from, %{positions: positions} = state) do
    {:reply, positions, state}
  end

  @impl true
  def handle_call(:portfolio_value, _from, %{positions: positions, timestamp: timestamp} = state) do
    total_value_usd =
      positions.holdings
      |> Enum.map(fn
        %ProductHolding{
          product: %Product{product_type: :CURRENCY, product_name: "USD"},
          amount: amount_str
        } ->
          PriceUtil.as_float(amount_str)

        %ProductHolding{
          product: %Product{product_type: :STONK, product_name: ticker},
          amount: amount_str
        } ->
          PriceUtil.as_float(amount_str) * get_price(ticker, timestamp)
      end)
      |> Enum.sum()

    {:reply, total_value_usd, state}
  end

  @impl true
  def handle_call(
        {:set_timestamp, timestamp},
        _from,
        %{positions: positions, timestamp: previous_timestamp} = state
      ) do
    Logger.debug("Mock Alpaca exchange time set to #{timestamp}")
    new_positions = fill_orders_between_times(positions, previous_timestamp, timestamp)
    {:reply, :ok, %{state | timestamp: timestamp, positions: new_positions}}
  end

  @impl true
  def handle_call({:current_price, ticker}, _from, %{timestamp: timestamp} = state) do
    {:reply, get_price(ticker, timestamp), state}
  end

  @impl true
  def handle_call(
        {:submit_order,
         %Order{
           order_type: :MARKET_SELL,
           sell_product:
             %Product{
               product_name: ticker
             } = product,
           amount: amount_str
         } = order},
        _from,
        %{positions: %ExchangePositions{holdings: holdings} = positions, timestamp: timestamp} =
          state
      ) do
    price = get_price(ticker, timestamp)

    Logger.info("MARKET_SELL #{ticker}: #{amount_str} @ $#{price}")
    Db.Orders.log_order(order, "backtest", timestamp)

    new_holdings =
      holdings
      |> add_to_holding(
        %Product{product_type: :CURRENCY, product_name: "USD"},
        PriceUtil.as_float(amount_str) * price
      )
      |> add_to_holding(product, -1 * PriceUtil.as_float(amount_str))

    Logger.debug("New holdings: #{inspect(new_holdings)}")

    {:reply, :ok, %{state | positions: %ExchangePositions{positions | holdings: new_holdings}}}
  end

  @impl true
  def handle_call(
        {:submit_order,
         %Order{
           order_type: :MARKET_BUY,
           buy_product:
             %Product{
               product_name: ticker
             } = product,
           amount: amount_str
         } = order},
        _from,
        %{
          positions: %ExchangePositions{holdings: holdings, orders: orders} = positions,
          timestamp: timestamp
        } = state
      ) do
    price = get_price(ticker, timestamp)

    Logger.info("MARKET_BUY #{ticker}: #{amount_str} @ $#{price}")
    Db.Orders.log_order(order, "backtest", timestamp)

    new_holdings =
      holdings
      |> add_to_holding(
        %Product{product_type: :CURRENCY, product_name: "USD"},
        -1 * PriceUtil.as_float(amount_str) * price
      )
      |> add_to_holding(product, PriceUtil.as_float(amount_str))

    Logger.debug("New holdings: #{inspect(new_holdings)}")

    new_orders = orders ++ bracket_orders(order)

    {:reply, :ok,
     %{
       state
       | positions: %ExchangePositions{positions | holdings: new_holdings, orders: new_orders}
     }}
  end

  @impl true
  def handle_call(
        {:submit_order,
         %Order{
           order_type: :CANCEL_ORDER,
           target_order_id: target_order_id
         } = order},
        _from,
        %{
          positions: %ExchangePositions{orders: orders} = positions
        } = state
      ) do
    {:reply, :ok,
     %{
       state
       | positions: %ExchangePositions{
           positions
           | orders:
               Enum.filter(orders, fn
                 %Order{id: ^target_order_id} -> false
                 _ -> true
               end)
         }
     }}
  end

  @impl true
  def handle_call(
        {:submit_order, %Order{order_type: :TRAILING_STOP_SELL}},
        _from,
        state
      ) do
    Logger.warn("Ignoring TRAILING_STOP_SELL; backtesting framework has not yet implemented it.")
    {:reply, :ok, state}
  end

  ###################
  # Private Methods #
  ###################

  defp add_to_holding(holdings, product, delta) do
    case Enum.find(holdings, fn
           %ProductHolding{product: ^product} -> true
           _ -> false
         end) do
      nil -> add_new_holding(holdings, product, delta)
      _ -> update_holding(holdings, product, delta)
    end
  end

  defp add_new_holding(holdings, product, delta) do
    [
      ProductHolding.new(
        product: product,
        amount: "#{delta}"
      )
      | holdings
    ]
  end

  defp update_holding(holdings, product, delta) do
    holdings
    |> Enum.map(fn h -> update_holding_impl(h, product, delta) end)
  end

  defp update_holding_impl(
         %ProductHolding{
           product: product,
           amount: amount_str
         } = holding,
         target_product,
         delta
       )
       when product == target_product do
    %ProductHolding{holding | amount: "#{PriceUtil.as_float(amount_str) + delta}"}
  end

  defp update_holding_impl(holding, _, _) do
    holding
  end

  defp get_price(ticker, timestamp) do
    Db.DataPoints.get_price_at_time(
      :STONK_AGGREGATE,
      "#{ticker}-#{@aggregate_width}",
      timestamp
    )
  end

  defp bracket_orders(%Order{
         order_type: :MARKET_BUY,
         buy_product: product,
         amount: amount_str,
         take_profit_price: take_profit_price,
         stop_loss_price: stop_loss_price
       }) do
    take_profit_order =
      if take_profit_price != 0 do
        Order.new(
          id: UUID.uuid4(),
          order_type: :LIMIT_SELL,
          sell_product: product,
          amount: amount_str,
          price: to_string(take_profit_price),
          status: :PLACED
        )
      else
        nil
      end

    stop_loss_order =
      if stop_loss_price != 0 do
        Order.new(
          id: UUID.uuid4(),
          order_type: :SELL_STOP,
          sell_product: product,
          amount: amount_str,
          price: to_string(stop_loss_price),
          status: :PLACED
        )
      else
        nil
      end

    Enum.filter([take_profit_order, stop_loss_order], fn x -> x != nil end)
  end

  defp fill_orders_between_times(
         %ExchangePositions{holdings: holdings, orders: orders} = positions,
         previous_timestamp,
         timestamp
       ) do
    {new_holdings, filled_tickers} =
      orders
      |> Enum.map(fn
        %Order{
          order_type: :LIMIT_SELL,
          sell_product: %Product{product_name: ticker},
          price: price_str
        } = o ->
          {o,
           Db.DataPoints.price_crossing_timestamp(
             :STONK_PRICE,
             "#{ticker}-#{@aggregate_width}",
             PriceUtil.as_float(price_str),
             :above,
             previous_timestamp,
             timestamp
           )}

        %Order{
          order_type: :SELL_STOP,
          sell_product: %Product{product_name: ticker},
          price: price_str
        } = o ->
          {o,
           Db.DataPoints.price_crossing_timestamp(
             :STONK_PRICE,
             "#{ticker}-#{@aggregate_width}",
             PriceUtil.as_float(price_str),
             :below,
             previous_timestamp,
             timestamp
           )}
      end)
      |> Enum.filter(fn
        {_, nil} -> false
        _ -> true
      end)
      |> Enum.group_by(fn {o, _} ->
        if o.buy_product == nil, do: o.sell_product.product_name, else: o.buy_product.product_name
      end)
      |> Enum.map(fn {_ticker, data} ->
        {o, _} = Enum.min_by(data, fn {_, ts} -> ts end)
        o
      end)
      |> Enum.reduce({positions, MapSet.new()}, fn o, acc -> fill_order(o, acc, timestamp) end)

    %ExchangePositions{
      new_holdings
      | orders:
          Enum.filter(new_holdings.orders, fn
            %Order{buy_product: nil, sell_product: sell_product} ->
              not MapSet.member?(filled_tickers, sell_product.product_name)

            %Order{buy_product: buy_product, sell_product: nil} ->
              not MapSet.member?(filled_tickers, buy_product.product_name)
          end)
    }
  end

  defp fill_order(
         %Order{
           id: order_id,
           order_type: order_type,
           sell_product: product,
           price: price_str,
           amount: amount_str
         } = order,
         {%ExchangePositions{holdings: holdings, orders: orders}, filled_tickers},
         timestamp
       )
       when order_type == :SELL_STOP or order_type == :LIMIT_SELL do
    price = PriceUtil.as_float(price_str)
    amount = PriceUtil.as_float(amount_str)

    Logger.info(
      "#{Atom.to_string(order_type)} #{product.product_name}: #{amount_str} @ $#{price}"
    )

    Db.Orders.log_order(order, "backtest", timestamp)

    new_holdings =
      holdings
      |> add_to_holding(
        %Product{product_type: :CURRENCY, product_name: "USD"},
        amount * price
      )
      |> add_to_holding(product, -1 * amount)

    new_orders = Enum.filter(orders, fn %Order{id: id} -> id != order_id end)

    {ExchangePositions.new(holdings: new_holdings, orders: new_orders),
     MapSet.put(filled_tickers, product.product_name)}
  end
end
