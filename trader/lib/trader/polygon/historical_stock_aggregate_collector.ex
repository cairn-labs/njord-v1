defmodule Trader.Polygon.HistoricalStockAggregateCollector do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.Polygon.PolygonApi, as: Api
  alias Trader.DataCache, as: Cache

  ##########
  # Client #
  ##########

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def download_range(ticker, start_date, end_date, window_length_minutes) do
    GenServer.call(
      __MODULE__,
      {:download_range, ticker, start_date, end_date, window_length_minutes},
      :infinity
    )
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    if Keyword.get(Application.get_env(:trader, __MODULE__), :enable, true) do
      Logger.debug("Starting Polygon HistoricalStockAggregateCollector GenServer...")
      queue_next_tick(self())
    end

    {:ok, %{all_products: []}}
  end

  @impl true
  def handle_info(:tick, state) do
    queue_next_tick(self())
    {:noreply, state}
  end

  @impl true
  def handle_call(
        {:download_range, ticker, start_date, end_date, window_length_minutes},
        _from,
        state
      ) do
    Trader.TimeUtil.date_range(start_date, end_date)
    |> Stream.chunk_every(5)
    |> Enum.map(fn chunk -> download_chunk(ticker, chunk, window_length_minutes) end)

    {:reply, :ok, state}
  end

  ###################
  # Private Methods #
  ###################

  defp queue_next_tick(pid) do
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  defp get_all_tickers() do
    Logger.debug("Retrieving all tickers from Polygon...")

    ticker_stream =
      Api.paginate(
        :GET,
        "v2/reference/tickers?market=stocks&locale=us",
        fn data -> Map.get(data, "tickers") end
      )

    ticker_stream
    |> Enum.map(fn m -> Map.get(m, "ticker") end)
  end

  defp download_chunk(ticker, dates, window_length_minutes) do
    start_date = List.first(dates)
    end_date = List.last(dates)
    Logger.debug("Downloading #{ticker} aggregates from #{start_date} to #{end_date}...")

    %HTTPoison.Response{body: body} =
      Api.call(
        :GET,
        "v2/aggs/ticker/#{ticker}/range/#{window_length_minutes}/minute/#{start_date}/#{end_date}"
      )

    results = Jason.decode!(body)

    if Map.get(results, "resultsCount") == 0 do
      []
    else
      Map.get(results, "results")
      |> Enum.flat_map(fn data -> aggregate_to_proto(data, ticker, window_length_minutes) end)
      |> Enum.each(&Db.DataPoints.insert_datapoint/1)
    end
  end

  def aggregate_to_proto(
        %{
          "c" => c,
          "h" => h,
          "l" => l,
          "n" => n,
          "o" => o,
          "t" => t,
          "v" => v,
          "vw" => vw
        },
        ticker,
        width_minutes
      ) do
    [
      DataPoint.new(
        event_timestamp: t * 1000,
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate:
          StonkAggregate.new(
            ticker: ticker,
            open_price: o,
            high_price: h,
            low_price: l,
            close_price: c,
            volume: v,
            vwap: vw,
            ts: t,
            n: n,
            width_minutes: width_minutes
          )
      )
    ]
  end

  def aggregate_to_proto(_, _, _) do
    []
  end
end
