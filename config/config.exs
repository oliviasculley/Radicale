# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :calex,
  ecto_repos: [Calex.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Invite-only unless REGISTRATION=public. runtime.exs overrides this in dev and prod.
config :calex, Calex.Accounts, registration: System.get_env("REGISTRATION", "invite")
config :calex, :email_disabled, false
config :calex, Calex.Application, automigrate: false

# Dev/test vault key. Production replaces it from CLOAK_KEY.
config :calex, Calex.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!("IRejKa/wJXRyI8Y9MAHmJvgFGARbycC09qh9WsyMy8A=")
    }
  ]

config :calex, Calex.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

# Configure the endpoint
config :calex, CalexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CalexWeb.ErrorHTML, json: CalexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Calex.PubSub,
  live_view: [signing_salt: "qyarl5A5"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  calex: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  calex: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
