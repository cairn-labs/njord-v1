defmodule Trader.Analyst do
  @moduledoc """
  Contains the interface between the trader and the Analyst, which is a separate
  Python application to which we delegate ML/numeric tasks.
  """

  require Logger

  def predict_price(
        current_time,
        %PredictionModelConfig{
          name: model_name,
          frame_config: frame_config
        } = prediction_config
      ) do
    frame = Trader.Frames.FrameGeneration.generate_input_frame(current_time, frame_config)

    url =
      Keyword.get(Application.get_env(:trader, __MODULE__), :analyst_url)
      |> URI.merge("api/prices/predict")
      |> to_string

    data = %{
      "frame" => Base.encode64(DataFrame.encode(frame)),
      "config" => Base.encode64(PredictionModelConfig.encode(prediction_config))
    }

    %HTTPoison.Response{body: body, status_code: 200} =
      HTTPoison.post!(url, Jason.encode!(data), [{"Content-Type", "application/json"}])

    Label.decode(Base.decode64!(body))
  end
end
