# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
