defmodule Trader.Polygon.RealtimeStockAggregateCollector do
  use WebSockex
  require Logger
  alias Trader.Db

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      url = Application.get_env(:trader, Trader.Polygon.PolygonApi)[:websocket_api_url]
      {:ok, pid} = WebSockex.start_link(url, __MODULE__, :no_state)
      subscribe(pid)
      {:ok, pid}
    else
      :ignore
    end
  end

  def subscribe(pid) do
    config = Application.get_env(:trader, Trader.Polygon.PolygonApi)

    message =
      %{
        "action" => "auth",
        "params" => config[:api_key]
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

  def receive_message([%{"ev" => "status", "status" => "connected"}]) do
    Logger.info("Polygon RealtimeStockAggregateCollector: connected")
    :ok
  end

  def receive_message([%{"ev" => "status", "message" => message, "status" => "success"}]) do
    Logger.info("Polygon RealtimeStockAggregateCollector: #{message}")
    :ok
  end

  def receive_message([%{"ev" => "status",
                         "message" => "authenticated",
                         "status" => "auth_success"}]) do
    message =
      %{
        "action" => "subscribe",
        "params" => "AM.*"
      }
      |> Jason.encode!()

    {:text, message}
  end

  def receive_message(%{"sym" => ticker,
                        "c" => close_price,
                        "e" => ts_end,
                        "ev" => "AM",
                        "h" => high_price,
                        "l" => low_price,
                        "o" => open_price,
                        "s" => ts_start,
                        "v" => volume,
                        "vw" => vwap}) do
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

  def receive_message(messages) when is_list(messages) do
    Logger.info("Received multiple messages in one buffer, processing them all but ignoring responses")
    Enum.each(messages, &receive_message/1)
    :ok
  end

  def receive_message(message) do
    Logger.warn("Polygon Websocket received unknown message: #{inspect(message)}")
    :ok
  end
end
