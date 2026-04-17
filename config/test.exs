import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :atrium, Atrium.Repo,
  username: "marcinwalczak",
  password: "",
  hostname: "localhost",
  database: "atrium_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :atrium, AtriumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xbjYONIqp/LS1CB8zDO4gTiZPCR9A013nZnnfQL335iNvxR+rahpzaqnjBWw+6sL",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :atrium, Oban, testing: :manual

config :atrium, Atrium.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1",
       key: Base.decode64!("rQh7p5xQy9m+Uy8fN5TkLQJ8q8fM1N6lL6K/nHcRzq4="),
       iv_length: 12}
  ]
