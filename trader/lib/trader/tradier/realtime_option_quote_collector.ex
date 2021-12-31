defmodule Trader.Tradier.RealtimeOptionQuoteCollector do
  use WebSockex
  require Logger
  alias Trader.Db
  alias Trader.Tradier.TradierApi

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      url = Application.get_env(:trader, Trader.Tradier.TradierApi)[:streaming_api_url]
      {:ok, pid} = WebSockex.start_link(url, __MODULE__, :no_state)
      subscribe(pid)
      {:ok, pid}
    else
      :ignore
    end
  end

  def subscribe(pid) do
    {:ok, %{"stream" => %{"sessionid" => session_id}}} =
      TradierApi.call(:POST, "v1/markets/events/session", force_live: true)

    symbols = get_all_contracts()
    Logger.info("Streaming data for contracts: #{Enum.join(symbols, ",")}")

    message =
      %{
        "symbols" => symbols,
        "sessionid" => session_id,
        "linebreak" => true
      }
      |> Jason.encode!()

    WebSockex.send_frame(pid, {:text, message})
  end

  #############
  # Callbacks #
  #############

  def handle_connect(conn, state) do
    {:ok, state}
  end

  def handle_frame({:text, message}, state) do
    reply =
      message
      |> Jason.decode!()
      |> receive_message

    case reply do
      :ok -> {:ok, state}
      frame -> {:reply, frame, state}
    end
  end

  def receive_message(%{
        "ask" => ask,
        "askdate" => askdate,
        "askexch" => askexch,
        "asksz" => asksz,
        "bid" => bid,
        "biddate" => biddate,
        "bidexch" => bidexch,
        "bidsz" => bidsz,
        "symbol" => symbol,
        "type" => "quote"
      }) do
    ask_ts = String.to_integer(askdate) * 1000
    bid_ts = String.to_integer(biddate) * 1000

    datapoint =
      DataPoint.new(
        event_timestamp: max(ask_ts, bid_ts),
        data_point_type: :OPTION_QUOTE,
        option_quote:
          OptionQuote.new(
            ask: ask,
            askdate: askdate,
            askexch: askexch,
            asksz: asksz,
            bid: bid,
            biddate: biddate,
            bidexch: bidexch,
            bidsz: bidsz,
            symbol: symbol
          )
      )

    # By default this special process silently ignores errors, don't do that.
    try do
      Db.DataPoints.insert_datapoint(datapoint)
    rescue
      e ->
        Logger.error(inspect(e))
        raise e
    end

    :ok
  end

  def receive_message(%{"error" => message}) do
    Logger.error(message)
    raise message
  end

  def receive_message(m) do
    Logger.error(inspect(m))
    # Silently ignore other messages
    :ok
  end

  def get_all_contracts() do
    Application.get_env(:trader, __MODULE__)[:tickers]
    |> Enum.flat_map(&get_all_contracts/1)
  end

  def get_all_contracts(ticker) do
    current_price = get_current_price(ticker)
    max_otm_percent = Application.get_env(:trader, __MODULE__)[:max_otm_percent]

    {:ok, %{"symbols" => [%{"options" => symbols}]}} =
      TradierApi.call(:GET, "v1/markets/options/lookup", params: [{"underlying", ticker}])

    symbols
    |> Enum.filter(fn s -> is_near_atm?(s, current_price, max_otm_percent) end)
  end

  def get_current_price(ticker) do
    {:ok, %{"quotes" => %{"quote" => %{"last" => last_price}}}} =
      TradierApi.call(:GET, "v1/markets/quotes", params: [{"symbols", ticker}])

    last_price
  end

  defp is_near_atm?(symbol, current_price, max_otm_percent) do
    strike = Trader.Options.Util.parse_strike(symbol)

    current_price * (1 - max_otm_percent) <= strike and
      strike <= current_price * (1 + max_otm_percent)
  end
end
