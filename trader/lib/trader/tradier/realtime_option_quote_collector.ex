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

    message =
      %{
        "symbols" => ["SPY", "AMD", "HLTH"],
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
        option_quote: OptionQuote.new(
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
    rescue e ->
        Logger.error(inspect(e))
      raise e
    end

    :ok
  end

  def receive_message(_) do
    # Silently ignore other messages
    :ok
  end
end
