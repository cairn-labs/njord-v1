defmodule TraderWeb.TrainingDataController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def get_training_data(conn, %{"frame_config" => frame_config_upload}) do
    frame_config =
      frame_config_upload.path
      |> File.read!()
      |> FrameConfig.decode()

    {:ok, results} = Trader.Frames.FrameGeneration.generate_frames(frame_config, 3)
    ApiUtil.send_success(conn, %{results: results})
  end
end
