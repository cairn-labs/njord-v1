defmodule Trader.Coinbase.L2DataCollector do
  require Logger
  use GenServer

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
    Logger.debug("Starting Coinbase L2DataCollector GenServer...")
    queue_next_tick(self())
    {:ok, %{}}
  end

  def handle_info(:tick, state) do
    Logger.debug("tick!")
    request_order_book("BTC-USD")
    queue_next_tick(self())
    {:noreply, state}
  end

  defp queue_next_tick(pid) do
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  defp request_order_book(product_id) do
    url =
      Application.get_env(:trader, __MODULE__)[:url]
      |> URI.parse()
      |> URI.merge("/api/#{product_id}/book?level=2")
      |> to_string

    Logger.info(url)
  end
end
