defmodule Trader.PredictionModels.Inference do
  alias Trader.PredictionModels, as: Models

  def predict(current_time, %PredictionModelConfig{
        name: model_name,
        frame_config: frame_config
      }) do
    frame = Trader.Frames.FrameGeneration.generate_input_frame(current_time, frame_config)

    model =
      case model_name do
        "simple_linear_regression" ->
          Models.SimpleLinearRegressionModel
      end

    model.predict(frame)
  end
end
