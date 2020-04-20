defmodule TraderWeb.TrainingDataController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def get_training_data(conn, %{"frame_config" => frame_config_upload}) do
    frame_config =
      frame_config_upload.path
      |> File.read!()
      |> FrameConfig.decode()

    ApiUtil.send_success(conn, %{})
  end
end
