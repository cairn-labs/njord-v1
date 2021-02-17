defmodule TraderWeb.StatusController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def get_status(conn, params) do
    results =
      Trader.Db.DataPoints.counts_by_type_in_window(
        DateTime.utc_now() |> DateTime.add(-60 * 60, :second),
        DateTime.utc_now()
      )

    ApiUtil.send_success(conn, %{"collected_in_past_hour" => results})
  end
end
