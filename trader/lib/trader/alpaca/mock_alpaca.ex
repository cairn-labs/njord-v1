defmodule Trader.Alpaca.MockAlpaca do
  require Logger
  use GenServer
  alias Trader.Db

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

  def execute_order_tree(%OrderTree{} = order_tree) do
    Logger.info("Executing orders: #{inspect(order_tree)}")
    :ok
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
end
