use Mix.Config

# Configure your database
config :trader, Trader.Repo,
  username: "trader_dev",
  password: "password",
  database: "trader_dev",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  timeout: 600_000

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :trader, TraderWeb.Endpoint,
  http: [port: 4000, protocol_options: [idle_timeout: 5_000_000, request_timeout: 5_000_000]],
  debug_errors: true,
  check_origin: false

config :trader, Trader.Analyst, analyst_url: "http://localhost:8001"

config :trader, Trader.Coinbase.L2DataCollector, enable: false

config :trader, Trader.Polygon.StockAggregateCollector, enable: false

config :trader, Trader.Newsapi.NewsapiDataCollector, enable: false

config :trader, Trader.Reddit.RedditDataCollector, enable: false

config :trader, Trader.Alpaca.AlpacaDataCollector, enable: false

config :trader, Trader.Runners.LiveRunner, enable: false

config :trader, Trader.Alpaca.Alpaca, enable: false

# Do not include metadata nor timestamps in development logs
config :logger,
  format: "[$level] $message\n",
  level: :info

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
