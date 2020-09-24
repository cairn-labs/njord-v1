defmodule TraderWeb.Router do
  use TraderWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", TraderWeb do
    pipe_through(:api)

    get("/", IndexController, :index)
  end

  scope "/api", TraderWeb do
    pipe_through(:api)

    post("/get_training_data", TrainingDataController, :get_training_data)
  end
end
