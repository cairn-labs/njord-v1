defmodule Trader.Alpaca.MockAlpaca do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.PriceUtil

  @aggregate_width 20

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def setup(stock_amounts) do
    GenServer.call(__MODULE__, :reset)
    GenServer.call(__MODULE__, {:load_stocks, stock_amounts})
  end

  def current_positions() do
    GenServer.call(__MODULE__, :current_positions)
  end

  def current_price(ticker) do
    GenServer.call(__MODULE__, {:current_price, ticker})
  end

  def set_timestamp(timestamp) do
    GenServer.call(__MODULE__, {:set_timestamp, timestamp})
  end

  def execute_order_tree(%OrderTree{orders: orders}) do
    # Need to toposort these orders into stages. For now, just submit
    # them sequentially.
    for order <- orders do
      submit_order(order)
    end
  end

  def submit_order(%Order{} = order) do
    GenServer.call(__MODULE__, {:submit_order, order})
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
  def handle_call({:set_timestamp, timestamp}, _from, state) do
    Logger.debug("Mock Alpaca exchange time set to #{timestamp}")
    {:reply, :ok, %{state | timestamp: timestamp}}
  end

  @impl true
  def handle_call({:current_price, ticker}, _from, %{timestamp: timestamp} = state) do
    {:reply,
     Db.DataPoints.get_price_at_time(
       :STONK_AGGREGATE,
       "#{ticker}-#{@aggregate_width}",
       timestamp
     ), state}
  end

  @impl true
  def handle_call(
    {:submit_order,
     %Order{order_type: :MARKET_SELL,
            sell_product: %Product{
              product_name: ticker
            },
            amount: amount_str
     } = order},
    _from,
    %{positions: %ExchangePositions{holdings: holdings},
      timestamp: timestamp} = state) do

    price = Db.DataPoints.get_price_at_time(
      :STONK_AGGREGATE,
      "#{ticker}-#{@aggregate_width}",
      timestamp
    )

    holdings =
      holdings
      |> Enum.map(fn holding -> update_cash_holding(holding, PriceUtil.as_float(amount_str) * price) end)

    Logger.info("Sell order: #{inspect order}")
    Logger.info("holdings #{inspect holdings}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:submit_order, %Order{order_type: :MARKET_BUY} = order}, _from, state) do
    Logger.info("Buy order: #{inspect order}")
    {:reply, :ok, state}
  end

  ###################
  # Private Methods #
  ###################

  def update_cash_holding(
    %ProductHolding{product: %Product{product_type: :CURRENCY, product_name: "USD"},
                    amount: amount_str} = holding,
    delta) do
    new = %ProductHolding{holding | amount: "#{PriceUtil.as_float(amount_str) + delta}"}
    Logger.info("New: #{inspect new}")
    new
  end
  def update_cash_holding(holding, _) do
    holding
  end
end
