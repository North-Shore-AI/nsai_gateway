import Config

# Gateway configuration
config :nsai_gateway,
  port: 4000,
  jwt_secret: System.get_env("JWT_SECRET") || "change-me-in-production",
  tenant_rate_limit: 1000,
  endpoint_rate_limits: %{
    "jobs" => 100,
    "samples" => 200,
    "labels" => 150,
    "experiments" => 50
  }

# Backend service URLs
config :nsai_gateway, :services, %{
  "work" => System.get_env("WORK_SERVICE_URL") || "http://localhost:4001",
  "forge" => System.get_env("FORGE_SERVICE_URL") || "http://localhost:4002",
  "anvil" => System.get_env("ANVIL_SERVICE_URL") || "http://localhost:4003",
  "crucible" => System.get_env("CRUCIBLE_SERVICE_URL") || "http://localhost:4004"
}

# API Keys (in production, use a database)
config :nsai_gateway, :api_keys, %{
  "demo-key-1" => "tenant-alpha",
  "demo-key-2" => "tenant-beta"
}

# Hammer rate limiter
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :tenant]

# Import environment specific config
import_config "#{config_env()}.exs"
