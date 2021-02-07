defmodule Trader.Polygon.StockAggregateCollector do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.Polygon.PolygonApi, as: Api

  ##########
  # Client #
  ##########

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if Keyword.get(Application.get_env(:trader, __MODULE__), :enable, true) do
      Logger.debug("Starting Polygon StockAggregateCollector GenServer...")
      queue_next_tick(self())
    end

    {:ok, %{all_products: get_all_tickers()}}
  end

  @impl true
  def handle_info(:tick, state) do
    queue_next_tick(self())
    {:noreply, state}
  end

  defp queue_next_tick(pid) do
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  defp get_all_tickers() do
    Logger.debug("Retrieving all tickers from Polygon...")
    ticker_stream = Api.paginate(
      :GET,
      "v2/reference/tickers?market=stocks&locale=us",
      fn data -> Map.get(data, "tickers") end)

    ticker_stream
    |> Enum.map(fn m -> Map.get(m, "ticker") end)
  end
end
