defmodule Trader.Alpaca.AlpacaDataCollector do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.Alpaca.AlpacaApi, as: Api
  alias Trader.DataCache, as: Cache

  ##########
  # Client #
  ##########

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ##########
  # Server #
  ##########

  @impl true
  def init(_state) do
    all_assets =
      if Keyword.get(Application.get_env(:trader, __MODULE__), :enable, true) do
        Logger.debug("Starting Alpaca DataCollector GenServer...")
        data = Cache.cached("all-alpaca-assets", 86_400, &get_all_assets/0)
        queue_next_tick(self())
        data
      else
        []
      end

    {:ok, %{all_assets: all_assets}}
  end

  @impl true
  def handle_info(:tick, %{all_assets: all_assets} = state) do
    all_assets
    |> Enum.chunk_every(100)
    |> Enum.map(&store_chunk_bars/1)

    queue_next_tick(self())
    {:noreply, state}
  end

  defp store_chunk_bars(assets) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    symbols = Enum.join(assets, ",")

    {:ok, %HTTPoison.Response{body: body}} =
      Api.call(:data, :GET, "v1/bars/minute?symbols=#{symbols}&limit=1&until=#{timestamp}")

    body
    |> Jason.decode!()
    |> Enum.flat_map(fn {ticker, bar} -> bar_to_datapoint(ticker, bar) end)
    |> Enum.each(&Db.DataPoints.insert_datapoint/1)
  end

  defp bar_to_datapoint(ticker, [%{"c" => c, "h" => h, "l" => l, "o" => o, "t" => t, "v" => v}]) do
    [
      DataPoint.new(
        event_timestamp: t * 1_000_000,
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate:
          StonkAggregate.new(
            ticker: ticker,
            open_price: o,
            high_price: h,
            low_price: l,
            close_price: c,
            volume: v,
            ts: t,
            width_minutes: 1
          )
      )
    ]
  end

  defp bar_to_datapoint(ticker, malformed) do
    Logger.warn("Malformed bar received for ticker #{ticker}: #{inspect(malformed)}")
    []
  end

  defp queue_next_tick(pid) do
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  defp get_all_assets() do
    {:ok, %HTTPoison.Response{body: body}} = Api.call(:trading, :GET, "v2/assets?status=active")

    body
    |> Jason.decode!()
    |> Enum.filter(fn
      %{"tradable" => true} -> true
      _ -> false
    end)
    |> Enum.map(fn %{"symbol" => s} -> s end)
  end
end
