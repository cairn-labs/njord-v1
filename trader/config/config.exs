# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :trader,
  ecto_repos: [Trader.Repo]

# Configures the endpoint
config :trader, TraderWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "kmdQgXsaPJC9nwRpICF5XUk1umB9vIOUJzhp49XgdJe44vM2t5Nr0tjdZL32x0/S",
  render_errors: [view: TraderWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Trader.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [signing_salt: "6rBkMycF"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :trader, Trader.Coinbase.CoinbaseApi,
  api_key: System.get_env("COINBASE_API_KEY"),
  api_passphrase: System.get_env("COINBASE_API_PASSPHRASE"),
  api_secret: System.get_env("COINBASE_API_SECRET"),
  rest_api_url: "https://api.pro.coinbase.com"

config :trader, Trader.Coinbase.L2DataCollector,
  enable: true,
  milliseconds_per_tick: 5_000

config :trader, Trader.Polygon.PolygonApi,
  api_key: System.get_env("POLYGON_API_KEY"),
  rest_api_url: "https://api.polygon.io/",
  websocket_api_url: "wss://socket.polygon.io/stocks"

config :trader, Trader.Polygon.HistoricalStockAggregateCollector,
  enable: true,
  milliseconds_per_tick: 60_000

config :trader, Trader.Newsapi.NewsapiDataCollector,
  enable: true,
  api_key: System.get_env("NEWSAPI_KEY"),
  max_calls_per_day: 450

config :trader, Trader.Reddit.RedditDataCollector,
  enable: true,
  api_secret: System.get_env("REDDIT_API_SECRET"),
  api_id: System.get_env("REDDIT_API_ID"),
  api_user: System.get_env("REDDIT_API_USER"),
  api_password: System.get_env("REDDIT_API_PASSWORD"),
  max_calls_per_minute: 15

config :trader, Trader.Alpaca.AlpacaApi,
  api_key: System.get_env("ALPACA_PAPER_API_KEY_ID"),
  api_secret: System.get_env("ALPACA_PAPER_API_SECRET"),
  trading_api_url: "https://paper-api.alpaca.markets",
  data_api_url: "https://data.alpaca.markets",
  data_websocket_url: "wss://data.alpaca.markets/stream"

# Fuck this shitty data collector
config :trader, Trader.Alpaca.AlpacaDataCollector, enable: false

config :trader, Trader.Polygon.RealtimeStockAggregateCollector, enable: true

config :trader, Trader.Runners.LiveRunner, enable: true

config :trader, Trader.Alpaca.Alpaca,
  enable: true,
  environment: "paper",
  milliseconds_per_tick: 2_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
