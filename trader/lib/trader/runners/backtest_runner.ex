defmodule Trader.Runners.BacktestRunner do
  require Logger
  use GenServer
  alias Trader.Db

  @prediction_timeout 30_000

  ##########
  # Client #
  ##########

  def start_link([]) do
    # TODO: we should probably make this instantiatable on the fly instead of a
    # singleton
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def load(strategies_dir) do
    GenServer.call(__MODULE__, {:load, strategies_dir})
  end

  def run(start_timestamp, end_timestamp) do
    {:ok, start_time, 0} = DateTime.from_iso8601(start_timestamp)
    {:ok, end_time, 0} = DateTime.from_iso8601(end_timestamp)
    tick_width = GenServer.call(__MODULE__, :get_tick_width)

    Stream.unfold(start_time, fn date ->
      case DateTime.compare(date, end_time) do
        :gt -> nil
        _ -> {date, DateTime.add(date, tick_width, :millisecond)}
      end
    end)
    |> Stream.flat_map(fn window_start ->
      GenServer.call(
        __MODULE__,
        {:get_predictions, start_time, window_start},
        @prediction_timeout
      )
    end)
    |> Enum.each(fn p -> Logger.info(inspect(p)) end)
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
        {:load, strategies_dir},
        _from,
        state
      ) do
    strategies = read_strategies(strategies_dir)
    check_strategies(strategies)
    tick_width_ms = get_overall_tick_width(strategies)

    state =
      state
      |> Map.put(:strategies, strategies)
      |> Map.put(:tick_width_ms, tick_width_ms)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_tick_width, _from, %{tick_width_ms: tick_width} = state) do
    {:reply, tick_width, state}
  end

  @impl true
  def handle_call(
        {:get_predictions, backtest_start, window_start},
        _from,
        %{strategies: strategies} = state
      ) do
    tick = DateTime.diff(window_start, backtest_start, :millisecond)

    # TODO: we definitely need Analyst.predict_price to return 0-N labels instead of always 1
    predictions =
      strategies
      |> Enum.filter(fn %TradingStrategy{cadence_ms: cadence} -> rem(tick, cadence) == 0 end)
      |> Enum.map(fn %TradingStrategy{
                       prediction_model_config: prediction_config,
                       name: strategy_name
                     } ->
        {strategy_name, Trader.Analyst.predict_price(window_start, prediction_config)}
      end)

    {:reply, predictions, state}
  end

  ###################
  # Private Methods #
  ###################
  defp read_strategies(dirname) do
    dirname
    |> Path.expand()
    |> Path.join("*.pb.txt")
    |> Path.wildcard()
    |> Enum.map(fn p ->
      Trader.ProtoUtil.parse_text_format(p, TradingStrategy, "trading_strategy.proto")
    end)
  end

  defp check_strategies(strategies) do
    total_allocation =
      strategies
      |> Enum.map(fn %TradingStrategy{capital_allocation: c} -> c end)
      |> Enum.sum()

    if total_allocation > 1.0 do
      raise "Total capital allocation of all strategies must be at most 1"
    end
  end

  def get_overall_tick_width(strategies) do
    strategies
    |> Enum.map(fn %TradingStrategy{cadence_ms: c} -> c end)
    |> Enum.reduce(fn x, acc -> Integer.gcd(x, acc) end)
  end
end
