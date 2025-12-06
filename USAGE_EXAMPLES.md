# NSAI Gateway Usage Examples

## Starting the Gateway

```bash
# Development mode
iex -S mix

# Production mode
MIX_ENV=prod mix run --no-halt
```

## Authentication Examples

### API Key Authentication

```bash
# Using Authorization header
curl -H "Authorization: ApiKey demo-key-1" \
  http://localhost:4000/api/v1/jobs

# Using query parameter
curl http://localhost:4000/api/v1/jobs?api_key=demo-key-1
```

### JWT Token Authentication

```elixir
# Generate a token (in IEx)
{:ok, token, claims} = NsaiGateway.Auth.JWT.generate("tenant-alpha", "user-123", 3600)

# Use the token
curl -H "Authorization: Bearer #{token}" \
  http://localhost:4000/api/v1/samples
```

```bash
# Example with real token
curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  http://localhost:4000/api/v1/experiments
```

## API Routes

### Health Check

```bash
curl http://localhost:4000/health
# Response: {"status":"healthy","service":"nsai_gateway"}
```

### Service Endpoints

```bash
# Work service (jobs)
curl -H "Authorization: ApiKey demo-key-1" \
  http://localhost:4000/api/v1/jobs/list

# Forge service (samples)
curl -H "Authorization: ApiKey demo-key-1" \
  http://localhost:4000/api/v1/samples/create \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"data": "example"}'

# Anvil service (labels)
curl -H "Authorization: ApiKey demo-key-1" \
  http://localhost:4000/api/v1/labels/123

# Crucible service (experiments)
curl -H "Authorization: ApiKey demo-key-1" \
  http://localhost:4000/api/v1/experiments?status=running
```

## Rate Limiting Examples

### Hitting Rate Limits

```bash
# Generate many requests to hit the limit
for i in {1..110}; do
  curl -H "Authorization: ApiKey demo-key-1" \
    http://localhost:4000/api/v1/jobs &
done
wait

# After 100 requests, you'll get:
# HTTP/1.1 429 Too Many Requests
# Retry-After: 60
# {"error":"Rate Limit Exceeded","message":"Too many requests. Please try again later."}
```

## Configuration Examples

### Environment Variables

```bash
# Set port
export PORT=8080

# Set JWT secret
export JWT_SECRET="your-secure-random-secret-here"

# Set service URLs
export WORK_SERVICE_URL="http://work-service:4001"
export FORGE_SERVICE_URL="http://forge-service:4002"
export ANVIL_SERVICE_URL="http://anvil-service:4003"
export CRUCIBLE_SERVICE_URL="http://crucible-service:4004"

# Start gateway
mix run --no-halt
```

### Custom Configuration

```elixir
# config/config.exs
config :nsai_gateway,
  port: 4000,
  tenant_rate_limit: 2000,  # 2000 requests per minute
  endpoint_rate_limits: %{
    "jobs" => 200,
    "samples" => 300,
    "labels" => 150,
    "experiments" => 100
  }

# Add new API key
config :nsai_gateway, :api_keys, %{
  "demo-key-1" => "tenant-alpha",
  "demo-key-2" => "tenant-beta",
  "prod-key-abc123" => "production-tenant"
}
```

## Telemetry Examples

### Attaching Custom Handlers

```elixir
# In your application startup
defmodule MyApp.TelemetryHandler do
  require Logger

  def setup do
    events = [
      [:nsai_gateway, :proxy, :success],
      [:nsai_gateway, :proxy, :error]
    ]

    :telemetry.attach_many(
      "my-app-gateway-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:nsai_gateway, :proxy, :success], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Send to your metrics system
    MyApp.Metrics.record("gateway.proxy.duration", duration_ms,
      service: metadata.service,
      status: metadata.status
    )
  end

  def handle_event([:nsai_gateway, :proxy, :error], measurements, metadata, _config) do
    # Track errors
    MyApp.Metrics.increment("gateway.proxy.errors",
      service: metadata.service,
      reason: metadata.reason
    )
  end
end
```

## Docker Example

```dockerfile
# Dockerfile
FROM elixir:1.18-alpine

WORKDIR /app

# Install dependencies
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application
COPY . .

# Compile
RUN mix compile

# Expose port
EXPOSE 4000

# Run
CMD ["mix", "run", "--no-halt"]
```

```bash
# Build and run
docker build -t nsai-gateway .
docker run -p 4000:4000 \
  -e JWT_SECRET="your-secret" \
  -e WORK_SERVICE_URL="http://work:4001" \
  nsai-gateway
```

## Docker Compose Example

```yaml
version: '3.8'

services:
  gateway:
    build: .
    ports:
      - "4000:4000"
    environment:
      - PORT=4000
      - JWT_SECRET=${JWT_SECRET}
      - WORK_SERVICE_URL=http://work:4001
      - FORGE_SERVICE_URL=http://forge:4002
      - ANVIL_SERVICE_URL=http://anvil:4003
      - CRUCIBLE_SERVICE_URL=http://crucible:4004
    depends_on:
      - work
      - forge
      - anvil
      - crucible

  work:
    image: nsai/work:latest
    ports:
      - "4001:4001"

  forge:
    image: nsai/forge:latest
    ports:
      - "4002:4002"

  anvil:
    image: nsai/anvil:latest
    ports:
      - "4003:4003"

  crucible:
    image: nsai/crucible:latest
    ports:
      - "4004:4004"
```

## Testing Examples

### Manual Testing

```bash
# Test authentication
curl -v http://localhost:4000/api/v1/jobs
# Should return 401 Unauthorized

curl -v -H "Authorization: ApiKey demo-key-1" http://localhost:4000/api/v1/jobs
# Should proxy to work service

# Test health check
curl http://localhost:4000/health
# Should return 200 with healthy status

# Test rate limiting
./scripts/rate_limit_test.sh
```

### Integration Testing

```elixir
# test/integration/gateway_test.exs
defmodule Integration.GatewayTest do
  use ExUnit.Case

  @gateway_url "http://localhost:4000"
  @api_key "demo-key-1"

  test "can authenticate and proxy request" do
    response = Req.get!(
      "#{@gateway_url}/api/v1/jobs",
      headers: [{"authorization", "ApiKey #{@api_key}"}]
    )

    assert response.status == 200
  end

  test "respects rate limits" do
    # Make 110 requests (limit is 100)
    results =
      for _ <- 1..110 do
        Req.get(
          "#{@gateway_url}/api/v1/jobs",
          headers: [{"authorization", "ApiKey #{@api_key}"}]
        )
      end

    # Count 429 responses
    rate_limited = Enum.count(results, fn
      {:ok, %{status: 429}} -> true
      _ -> false
    end)

    assert rate_limited > 0
  end
end
```

## Monitoring Examples

### Prometheus Integration

```elixir
# Add to your supervision tree
defmodule MyApp.Metrics do
  use Prometheus.PlugExporter

  def setup do
    # Define metrics
    Prometheus.Gauge.declare(
      name: :gateway_requests_total,
      help: "Total gateway requests",
      labels: [:service, :status]
    )

    Prometheus.Histogram.declare(
      name: :gateway_request_duration_seconds,
      help: "Gateway request duration",
      labels: [:service],
      buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5]
    )

    # Attach to telemetry
    :telemetry.attach(
      "prometheus-gateway",
      [:nsai_gateway, :proxy, :success],
      &handle_metrics/4,
      nil
    )
  end

  def handle_metrics(_event, measurements, metadata, _config) do
    Prometheus.Gauge.inc(
      name: :gateway_requests_total,
      labels: [metadata.service, metadata.status]
    )

    duration_seconds = System.convert_time_unit(
      measurements.duration,
      :native,
      :second
    )

    Prometheus.Histogram.observe(
      [name: :gateway_request_duration_seconds, labels: [metadata.service]],
      duration_seconds
    )
  end
end
```
