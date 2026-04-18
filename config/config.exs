# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :atrium,
  ecto_repos: [Atrium.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :atrium, AtriumWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AtriumWeb.ErrorHTML, json: AtriumWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Atrium.PubSub,
  live_view: [signing_salt: "+VWkDIzA"]

config :triplex,
  repo: Atrium.Repo,
  tenant_prefix: "tenant_",
  migrations_path: "tenant_migrations"

config :atrium, Oban,
  repo: Atrium.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", Atrium.Accounts.SessionSweeper},
       {"0 2 * * *", Atrium.Audit.RetentionSweeper}
     ]}
  ],
  queues: [default: 10, maintenance: 2, audit: 5]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  atrium: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Enum.join([Path.expand("../assets/node_modules", __DIR__), Path.expand("../deps", __DIR__)], ":")}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  atrium: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Swoosh mailer — no HTTP client needed in dev/test
config :swoosh, :api_client, false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
