defmodule Trader.Coinbase.L2DataCollector do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.Coinbase.CoinbaseApi, as: Api

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
    if Keyword.get(Application.get_env(:trader, __MODULE__), :enable, true) do
      Logger.debug("Starting Coinbase L2DataCollector GenServer...")
      queue_next_tick(self())
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    with {:ok, response} <- request_order_book("BTC-USD"),
         {:ok, proto} <- make_data_point_proto(response) do
      Db.DataPoints.insert_datapoint(proto)
    else
      {:error, m} ->
        Logger.error("Error retrieving L2 Data: #{inspect(m)}")
    end

    queue_next_tick(self())
    {:noreply, state}
  end

  defp queue_next_tick(pid) do
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  defp request_order_book(product_id) do
    with {:ok, %{body: body}} <- Api.call(:GET, "/products/#{product_id}/book?level=2"),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      _ -> :error
    end
  end

  defp make_data_point_proto(response) do
    proto =
      DataPoint.new(
        event_timestamp: DateTime.utc_now() |> DateTime.to_unix(:microsecond),
        data_point_type: :L2_ORDER_BOOK,
        l2_order_book: order_book_to_proto(response)
      )

    {:ok, proto}
  end

  defp order_book_to_proto(%{"bids" => bids, "asks" => asks}) do
    L2OrderBook.new(
      bids: Enum.map(bids, &order_book_entry_to_proto/1),
      asks: Enum.map(asks, &order_book_entry_to_proto/1)
    )
  end

  defp order_book_entry_to_proto([price, size, num_orders]) do
    L2OrderBookEntry.new(price: price, size: size, num_orders: num_orders)
  end
end
