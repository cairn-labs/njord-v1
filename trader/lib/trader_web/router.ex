defmodule TraderWeb.Router do
  use TraderWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", TraderWeb do
    pipe_through(:api)

    get("/", IndexController, :index)
    get("/status", StatusController, :get_status)
    get("/status/:strategy_name", StatusController, :get_strategy_status)
  end

  scope "/api", TraderWeb do
    pipe_through(:api)

    post("/get_training_data", TrainingDataController, :get_training_data)
    post("/test_predict", TrainingDataController, :test_predict)
  end
end
