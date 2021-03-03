defmodule TraderWeb.StatusController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
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
end
