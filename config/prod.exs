import Config

# Production configuration
config :nsai_gateway,
  port: String.to_integer(System.get_env("PORT") || "4000")

config :logger, level: :info
