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

  def test_predict(conn, %{"config" => config_upload}) do
    config =
      config_upload.path
      |> File.read!()
      |> PredictionModelConfig.decode()

    # For testing fx rate one
    # Trader.Analyst.predict_price(
    #   ~U[2021-02-09 00:12:53.000000Z],
    #   config
    # )

    Trader.Analyst.predict_price(
      ~U[2018-01-09 00:12:53.000000Z],
      config
    )

    ApiUtil.send_success(conn, %{message: "OK"})
  end
end
