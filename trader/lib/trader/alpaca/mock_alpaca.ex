defmodule Trader.Alpaca.MockAlpaca do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.PriceUtil

  @aggregate_width 1
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

  def execute_order_tree(%OrderTree{orders: orders}, _strategy_name) do
    # Need to toposort these orders into stages. For now, just submit
    # them sequentially.
    for order <- orders do
      submit_order(order)
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
  def handle_call({:set_timestamp, timestamp}, _from, state) do
    Logger.debug("Mock Alpaca exchange time set to #{timestamp}")
    {:reply, :ok, %{state | timestamp: timestamp}}
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
        %{positions: %ExchangePositions{holdings: holdings} = positions, timestamp: timestamp} =
          state
      ) do
    price = get_price(ticker, timestamp)

    Logger.info("MARKET_BUY #{ticker}: #{amount_str} @ $#{price}")

    new_holdings =
      holdings
      |> add_to_holding(
        %Product{product_type: :CURRENCY, product_name: "USD"},
        -1 * PriceUtil.as_float(amount_str) * price
      )
      |> add_to_holding(product, PriceUtil.as_float(amount_str))

    Logger.debug("New holdings: #{inspect(new_holdings)}")

    {:reply, :ok, %{state | positions: %ExchangePositions{positions | holdings: new_holdings}}}
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
end
