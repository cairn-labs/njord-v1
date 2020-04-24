defmodule TraderWeb.TrainingDataController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def get_training_data(conn, %{"frame_config" => frame_config_upload}) do
    frame_config =
      frame_config_upload.path
      |> File.read!()
      |> FrameConfig.decode()

    {:ok, frames} = Trader.Frames.FrameGeneration.generate_frames(frame_config)

    files =
      frames
      |> Stream.with_index()
      |> Enum.map(fn {f, idx} ->
        {'component_' ++ to_charlist(idx) ++ '.pb', DataFrame.encode(f)}
      end)

    {:ok, {'mem', zip_bin}} = :zip.create('mem', files, [:memory])
    send_download(conn, {:binary, zip_bin}, filename: "frames.zip")
  end
end
