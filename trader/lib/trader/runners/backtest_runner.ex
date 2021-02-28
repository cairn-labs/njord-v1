defmodule Trader.Runners.BacktestRunner do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.Alpaca.MockAlpaca

  @prediction_timeout 120_000

  ##########
  # Client #
  ##########

  def start_link([]) do
    # TODO: we should probably make this instantiatable on the fly instead of a
    # singleton
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def load(strategy_pb) do
    GenServer.call(__MODULE__, {:load, strategy_pb})
  end

  def set_positions(positions_map) do
    MockAlpaca.setup(positions_map)
  end

  def run(start_timestamp, end_timestamp) do
    {:ok, start_time, 0} = DateTime.from_iso8601(start_timestamp)
    {:ok, end_time, 0} = DateTime.from_iso8601(end_timestamp)
    tick_width = GenServer.call(__MODULE__, :get_tick_width)

    MockAlpaca.set_timestamp(start_time)
    portfolio_value = MockAlpaca.portfolio_value()
    Logger.info("Start portfolio value: $#{portfolio_value}")

    Stream.unfold(start_time, fn date ->
      case DateTime.compare(date, end_time) do
        :gt -> nil
        _ -> {date, DateTime.add(date, tick_width, :millisecond)}
      end
    end)
    |> Enum.each(fn window_start ->
      GenServer.call(
        __MODULE__,
        {:submit_predictions, start_time, window_start},
        @prediction_timeout
      )
    end)

    Logger.info("End portfolio value: $#{MockAlpaca.portfolio_value()}")
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(
        {:load, strategy_pb},
        _from,
        state
      ) do
    strategy = read_strategy(strategy_pb)

    state =
      state
      |> Map.put(:strategies, [strategy])
      |> Map.put(:tick_width_ms, strategy.cadence_ms)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_tick_width, _from, %{tick_width_ms: tick_width} = state) do
    {:reply, tick_width, state}
  end

  @impl true
  def handle_call(
        {:submit_predictions, backtest_start, window_start},
        _from,
        %{strategies: strategies} = state
      ) do
    tick = DateTime.diff(window_start, backtest_start, :millisecond)
    MockAlpaca.set_timestamp(window_start)

    prediction =
      strategies
      |> Enum.filter(fn strat -> Trader.Strategies.is_schedulable?(strat, window_start) end)
      |> Enum.filter(fn %TradingStrategy{cadence_ms: cadence} -> rem(tick, cadence) == 0 end)
      |> Enum.map(fn %TradingStrategy{
                       prediction_model_config: prediction_config,
                       name: strategy_name
                     } = strat ->
        {strat,
         %Prediction{
           Trader.Analyst.predict_price(window_start, prediction_config)
           | strategy_name: strategy_name
         }}
      end)
      |> Enum.each(fn {strat, p} ->
        Trader.Orders.OrderCreation.submit_orders(strat, p, :backtest)
      end)

    {:reply, :ok, state}
  end

  ###################
  # Private Methods #
  ###################
  defp read_strategy(filename) do
    filename
    |> Path.expand()
    |> Trader.ProtoUtil.parse_text_format(TradingStrategy, "trading_strategy.proto")
  end
end
