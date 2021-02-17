defmodule Trader.Alpaca.AlpacaDataCollector do
  use WebSockex
  require Logger

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      url = Application.get_env(:trader, Trader.Alpaca.AlpacaApi)[:data_websocket_url]
      {:ok, pid} = WebSockex.start_link(url, __MODULE__, :no_state)
      subscribe(pid)
      {:ok, pid}
    else
      :ignore
    end
  end

  def subscribe(pid) do
    config = Application.get_env(:trader, Trader.Alpaca.AlpacaApi)

    message =
      %{
        "action" => "authenticate",
        "data" => %{
          key_id: config[:api_key],
          secret_key: config[:api_secret]
        }
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
        "data" => %{"action" => "authenticate", "status" => "authorized"},
        "stream" => "authorization"
      }) do
    message =
      %{
        "action" => "listen",
        "data" => %{
          "streams" => ["AM.*"]
        }
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

  def receive_message(message) do
    Logger.warn("Alpaca Websocket received unknown message: #{inspect(message)}")
    :ok
  end
end
