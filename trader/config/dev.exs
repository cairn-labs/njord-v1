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
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# Watch static and templates for browser reloading.
config :trader, TraderWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/trader_web/(live|views)/.*(ex)$",
      ~r"lib/trader_web/templates/.*(eex)$"
    ]
  ]

config :trader, Trader.Coinbase.CoinbaseApi,
  api_key: System.get_env("COINBASE_API_KEY"),
  api_passphrase: System.get_env("COINBASE_API_PASSPHRASE"),
  api_secret: System.get_env("COINBASE_API_SECRET"),
  rest_api_url: "https://api.pro.coinbase.com"

config :trader, Trader.Coinbase.L2DataCollector,
  enable: true,
  milliseconds_per_tick: 5_000

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
  max_calls_per_minute: 30

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
