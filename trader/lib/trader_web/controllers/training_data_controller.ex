defmodule TraderWeb.TrainingDataController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def get_training_data(conn, params) do
    Logger.info("conn #{inspect(conn)}")
    Logger.info("params #{inspect(params)}")
    ApiUtil.send_success(conn, %{})
  end
end
