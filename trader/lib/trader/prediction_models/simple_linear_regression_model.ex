defmodule Trader.PredictionModels.SimpleLinearRegressionModel do
  require Logger

  def predict(%DataFrame{} = frame) do
    Logger.info(inspect(frame))
    :ok
  end
end
