defmodule Trader.Runners.LiveRunner do
  require Logger
  use GenServer
  alias Trader.Db

  @initial_delay_ms 5_000
  @prediction_timeout 120_000

  ##########
  # Client #
  ##########

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      {:ok, pid} = GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
      Process.send_after(pid, :tick, @initial_delay_ms)
      {:ok, pid}
    else
      :ignore
    end
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    strategies = read_strategies()
    check_strategies(strategies)
    tick_width_ms = get_overall_tick_width(strategies)

    state = %{
      strategies: strategies,
      tick_width_ms: tick_width_ms,
      tick: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_tick_width, _from, %{tick_width_ms: tick_width} = state) do
    {:reply, tick_width, state}
  end

  @impl true
  def handle_info(
        :tick,
        %{tick_width_ms: tick_width_ms, tick: tick, strategies: strategies} = state
      ) do
    strategies
    |> Enum.filter(fn %TradingStrategy{cadence_ms: cadence} ->
      rem(tick * tick_width_ms, cadence) == 0
    end)
    |> Enum.map(fn %TradingStrategy{
                     prediction_model_config:
                       %PredictionModelConfig{
                         frame_config: %FrameConfig{frame_width_ms: frame_width}
                       } = prediction_config,
                     name: strategy_name
                   } ->
      %Prediction{
        Trader.Analyst.predict_price(get_window_start(frame_width), prediction_config)
        | strategy_name: strategy_name
      }
    end)
    |> Enum.each(fn p -> Trader.Orders.OrderCreation.submit_orders(p, :live) end)

    pid = self()
    spawn(fn -> Process.send_after(pid, :tick, tick_width_ms) end)
    {:noreply, %{state | tick: tick + 1}}
  end

  ###################
  # Private Methods #
  ###################
  defp read_strategies() do
    Application.app_dir(:trader, "priv")
    |> Path.join("active_strategies")
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

  defp get_overall_tick_width([]) do
    nil
  end

  defp get_overall_tick_width(strategies) do
    strategies
    |> Enum.map(fn %TradingStrategy{cadence_ms: c} -> c end)
    |> Enum.reduce(fn x, acc -> Integer.gcd(x, acc) end)
  end

  def get_window_start(frame_width_ms) do
    DateTime.utc_now() |> DateTime.add(-1 * frame_width_ms, :millisecond)
  end
end