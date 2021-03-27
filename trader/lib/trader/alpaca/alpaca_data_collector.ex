defmodule Trader.Alpaca.AlpacaDataCollector do
  use WebSockex
  require Logger
  alias Trader.Db

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      url = Application.get_env(:trader, Trader.Alpaca.AlpacaApi)[:data_websocket_url]
      WebSockex.start_link(url, __MODULE__, :no_state)
    else
      :ignore
    end
  end

  def subscribe(pid) do
    config = Application.get_env(:trader, Trader.Alpaca.AlpacaApi)

    message =
      %{
        "action" => "auth",
        "key" => config[:api_key],
        "secret" => config[:api_secret]
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

  def receive_message([%{"T" => "success", "msg" => "connected"}]) do
    config = Application.get_env(:trader, Trader.Alpaca.AlpacaApi)

    message =
      %{
        "action" => "auth",
        "key" => config[:api_key],
        "secret" => config[:api_secret]
      }
      |> Jason.encode!()

    Logger.info(message)
    {:text, message}
  end

  def receive_message([%{"T" => "success", "msg" => "authenticated"}]) do
    message =
      %{
        "action" => "subscribe",
        "bars" => "*"
      }
      |> Jason.encode!()

    {:text, message}
  end

  def receive_message(%{
        "stream" => "listening",
        "data" => %{
          "streams" => _
        }
      }) do
    Logger.info("Alpaca Websocket listening for 1-minute bars.")
    :ok
  end

  def receive_message(%{"data" => %{"T" => ticker,
                                    "c" => close_price,
                                    "e" => ts_end,
                                    "ev" => "AM",
                                    "h" => high_price,
                                    "l" => low_price,
                                    "o" => open_price,
                                    "s" => ts_start,
                                    "v" => volume,
                                    "vw" => vwap}, "stream" => _}) do
    datapoint =
      DataPoint.new(
        event_timestamp: ts_end * 1000,
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: StonkAggregate.new(
          ticker: ticker,
          open_price: open_price,
          high_price: high_price,
          low_price: low_price,
          close_price: close_price,
          volume: volume,
          vwap: vwap,
          ts: ts_start,
          width_minutes: 1
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

  def receive_message(message) do
    Logger.warn("Alpaca Websocket received unknown message: #{inspect(message)}")
    :ok
  end
end
