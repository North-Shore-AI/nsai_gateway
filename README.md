# NSAI Gateway

Unified API Gateway for North Shore AI services, providing authentication, rate limiting, request routing, and telemetry.

## Overview

NSAI Gateway is a high-performance API gateway built with Elixir that sits between clients and backend NSAI services (Work, Forge, Anvil, Crucible). It provides:

- **Authentication**: API Key and JWT token support
- **Authorization**: Tenant isolation and access control
- **Rate Limiting**: Per-tenant and per-endpoint limits with sliding window algorithm
- **Request Routing**: Intelligent routing to backend services
- **Service Discovery**: Health checking and failover
- **Telemetry**: Comprehensive metrics and monitoring
- **Load Balancing**: Request distribution with retry logic

## Architecture

```
┌─────────┐
│ Clients │
└────┬────┘
     │
     ▼
┌─────────────────┐
│  NSAI Gateway   │
│                 │
│  ┌───────────┐  │
│  │ Auth      │  │
│  ├───────────┤  │
│  │ Rate Limit│  │
│  ├───────────┤  │
│  │ Router    │  │
│  ├───────────┤  │
│  │ Proxy     │  │
│  └───────────┘  │
└────┬─┬─┬─┬──────┘
     │ │ │ │
     ▼ ▼ ▼ ▼
┌────┐┌─────┐┌───────┐┌──────────┐
│Work││Forge││Anvil  ││Crucible  │
└────┘└─────┘└───────┘└──────────┘
```

## Installation

Add `nsai_gateway` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nsai_gateway, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure the gateway in `config/config.exs`:

```elixir
config :nsai_gateway,
  port: 4000,
  jwt_secret: System.get_env("JWT_SECRET"),
  tenant_rate_limit: 1000,  # requests per minute
  endpoint_rate_limits: %{
    "jobs" => 100,
    "samples" => 200,
    "labels" => 150,
    "experiments" => 50
  }

# Backend service URLs
config :nsai_gateway, :services, %{
  "work" => "http://localhost:4001",
  "forge" => "http://localhost:4002",
  "anvil" => "http://localhost:4003",
  "crucible" => "http://localhost:4004"
}

# API Keys (use database in production)
config :nsai_gateway, :api_keys, %{
  "your-api-key-here" => "tenant-name"
}
```

### Environment Variables

- `PORT`: HTTP server port (default: 4000)
- `JWT_SECRET`: Secret key for JWT signing
- `WORK_SERVICE_URL`: Work service backend URL
- `FORGE_SERVICE_URL`: Forge service backend URL
- `ANVIL_SERVICE_URL`: Anvil service backend URL
- `CRUCIBLE_SERVICE_URL`: Crucible service backend URL

## Usage

### Starting the Gateway

```bash
# Fetch dependencies
mix deps.get

# Compile
mix compile

# Run in development
mix run --no-halt

# Or with iex
iex -S mix
```

### API Routes

All API routes are prefixed with `/api/v1/{service}/`:

```
/api/v1/jobs/*        -> Work service
/api/v1/samples/*     -> Forge service
/api/v1/labels/*      -> Anvil service
/api/v1/experiments/* -> Crucible service
```

### Authentication

#### API Key Authentication

Include API key in the `Authorization` header:

```bash
curl -H "Authorization: ApiKey your-api-key-here" \
  http://localhost:4000/api/v1/jobs
```

Or as a query parameter:

```bash
curl http://localhost:4000/api/v1/jobs?api_key=your-api-key-here
```

#### JWT Token Authentication

Generate a token:

```elixir
{:ok, token, claims} = NsaiGateway.Auth.JWT.generate("tenant-name", "user-id", 3600)
```

Use the token:

```bash
curl -H "Authorization: Bearer eyJhbGc..." \
  http://localhost:4000/api/v1/jobs
```

### Health Check

```bash
curl http://localhost:4000/health

# Response:
# {"status": "healthy", "service": "nsai_gateway"}
```

## Rate Limiting

The gateway implements a sliding window rate limiter with two levels:

1. **Tenant-level**: Global limit per tenant (default: 1000 req/min)
2. **Endpoint-level**: Per-service limits (configurable)

When rate limited, responses include:

```
HTTP/1.1 429 Too Many Requests
Retry-After: 60

{
  "error": "Rate Limit Exceeded",
  "message": "Too many requests. Please try again later."
}
```

## Telemetry

The gateway emits telemetry events for monitoring:

- `[:nsai_gateway, :proxy, :success]` - Successful proxy requests
- `[:nsai_gateway, :proxy, :error]` - Failed proxy requests
- `[:nsai_gateway, :auth, :success]` - Successful authentication
- `[:nsai_gateway, :auth, :failure]` - Failed authentication
- `[:nsai_gateway, :rate_limit, :exceeded]` - Rate limit violations

### Attaching Handlers

```elixir
NsaiGateway.Telemetry.attach_handlers()
```

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/nsai_gateway/auth_test.exs
```

### Code Quality

```bash
# Format code
mix format

# Run Credo (if added)
mix credo --strict

# Run Dialyzer (if added)
mix dialyzer
```

## Architecture Details

### Request Flow

1. **HTTP Request** arrives at the gateway
2. **Router** matches the path to a backend service
3. **Authentication** validates API key or JWT token
4. **Rate Limiter** checks tenant and endpoint limits
5. **Proxy** forwards request to backend service with retry logic
6. **Response** is returned to the client
7. **Telemetry** events are emitted for monitoring

### Components

#### Router (`NsaiGateway.Router`)
- Plug-based HTTP router
- Route matching and dispatch
- Health check endpoint

#### Proxy (`NsaiGateway.Proxy`)
- HTTP request forwarding
- Service discovery integration
- Retry with exponential backoff
- Response streaming

#### Auth (`NsaiGateway.Auth`)
- API key validation
- JWT token verification
- Tenant assignment

#### RateLimiter (`NsaiGateway.RateLimiter`)
- Sliding window algorithm (Hammer)
- Per-tenant limits
- Per-endpoint limits

#### ServiceResolver (`NsaiGateway.ServiceResolver`)
- Service discovery
- Health checking
- Failover support

#### Telemetry (`NsaiGateway.Telemetry`)
- Metrics collection
- Event emission
- Performance monitoring

## Production Considerations

### Security

1. **JWT Secret**: Use strong, random secrets in production
2. **API Keys**: Store in secure database, not config files
3. **HTTPS**: Always use TLS in production
4. **Rate Limiting**: Tune limits based on capacity

### Performance

1. **Connection Pooling**: Configure HTTP client pools
2. **Caching**: Add caching layer for service discovery
3. **Load Balancing**: Use multiple gateway instances
4. **Monitoring**: Set up proper telemetry collection

### Scalability

1. **Horizontal Scaling**: Run multiple gateway instances
2. **Service Discovery**: Integrate with nsai_registry
3. **Circuit Breakers**: Add circuit breaker pattern
4. **Async Processing**: Use message queues for long operations

## Roadmap

- [ ] Integration with nsai_registry for dynamic service discovery
- [ ] Circuit breaker pattern for backend failures
- [ ] Request/response transformation hooks
- [ ] GraphQL gateway support
- [ ] WebSocket proxying
- [ ] API versioning strategies
- [ ] Response caching
- [ ] Request validation schemas

## Contributing

See the main [North-Shore-AI repository](https://github.com/North-Shore-AI/tinkerer) for contribution guidelines.

## License

MIT License - see LICENSE file for details.

## Related Projects

- [nsai_registry](../nsai_registry) - Service discovery and registration
- [crucible_framework](../crucible_framework) - ML experimentation framework
- [cns](../cns) - Critic-Network Synthesis

## Support

For issues and questions:
- GitHub Issues: https://github.com/North-Shore-AI/nsai_gateway/issues
- Documentation: https://hexdocs.pm/nsai_gateway
