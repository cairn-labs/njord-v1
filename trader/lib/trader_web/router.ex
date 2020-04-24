defmodule TraderWeb.Router do
  use TraderWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", TraderWeb do
    pipe_through(:browser)

    get("/", PageController, :index)
  end

  scope "/api", TraderWeb do
    pipe_through(:api)

    post("/get_training_data", TrainingDataController, :get_training_data)
  end
end
