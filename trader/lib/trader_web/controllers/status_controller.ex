defmodule TraderWeb.StatusController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  alias Trader.TimeUtil
  require Logger

  def get_status(conn, params) do
    data_counts =
      Trader.Db.DataPoints.counts_by_type_in_window(
        DateTime.utc_now() |> DateTime.add(-60 * 60, :second),
        DateTime.utc_now()
      )

    positions_by_strategy =
      Trader.Alpaca.Alpaca.active_strategies()
      |> Enum.map(fn name -> {name, Trader.Alpaca.Alpaca.current_positions(name)} end)
      |> Enum.into(%{})

    ApiUtil.send_success(conn, %{
      "collected_in_past_hour" => data_counts,
      "strategies" => positions_by_strategy
    })
  end

  def get_strategy_status(conn, %{"strategy_name" => strategy_name} = params) do
    start_date =
      case Map.get(params, "start") do
        nil ->
          DateTime.now!("America/New_York") |> DateTime.to_date()

        date_str ->
          Date.from_iso8601!(date_str)
      end

    end_date =
      case Map.get(params, "end") do
        nil ->
          DateTime.now!("America/New_York") |> DateTime.to_date() |> Date.add(1)

        date_str ->
          Date.from_iso8601!(date_str)
      end

    orders =
      Trader.Db.Orders.orders_by_strategy(
        strategy_name,
        TimeUtil.est_date_to_datetime(start_date, ~T[00:00:00]),
        TimeUtil.est_date_to_datetime(end_date, ~T[00:00:00]),
        Application.get_env(:trader, Trader.Alpaca.Alpaca)[:environment]
      )

    ApiUtil.send_success(
      conn,
      %{
        start_date: Date.to_iso8601(start_date),
        end_date: Date.to_iso8601(end_date),
        orders: orders
      }
    )
  end
end
